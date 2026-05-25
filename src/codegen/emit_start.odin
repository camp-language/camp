package codegen

import "camp:base"
import "camp:ir"


get_main_return_type :: proc(ir_mod: ir.IR_Module, interner: ^base.Intern_Table) -> base.IR_Wasm_Type {
	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(interner, d.name.name)
			if name_str == "main" || name_str == "main!" {
				return d.return_type.wasm_type
			}
		case ^ir.IR_Decl_Const, ^ir.IR_Decl_Effect:
		}
	}
	return .I64
}

emit_start_function :: proc(
	env: ^Codegen_Env,
	main_decl: ^ir.IR_Decl_Fn,
	main_fn_idx: int,
	cont_func_idx: int,
	start_func_idx: int,
	worker_func_idx: int,
	runtime_func_indices: []int,
	ir_mod: ir.IR_Module,
	thread_count: int,
	deferred_handler_codes: ^[dynamic]Wasm_Code,
) {
	if start_func_idx >= 0 && main_decl != nil {
		env.next_local = 4
		env.tmp_local_base = 0
		env.tmp_count = 0

		code_buf: [dynamic]u8
		code_buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

		// is_effectful is set by the `!` suffix even when no effects are
		// inferred; cont_func_idx is only reserved when effects > 0. Gate
		// here too or the function/code sections drift out of sync.
		if main_decl.is_effectful && cont_func_idx >= 0 {
			// Effectful main: _start allocates evidence records, calls main!, exits

			// Emit top-level continuation function body for CPS-transformed main!
			// The continuation takes (env: i32, result: i64) and calls camp_exit(result & 127)
			cont_body_buf: [dynamic]u8
			cont_body_buf = make([dynamic]u8, 0, CODE_BUF_MINOR)
			emit_instruction(Wasm_Local_Get{index = 1}, &cont_body_buf)  // result (i64)
			emit_instruction(Wasm_I32_Wrap_I64{}, &cont_body_buf)         // to i32
			emit_instruction(Wasm_I32_Const{value = CAMP_EXIT_MASK}, &cont_body_buf)
			emit_instruction(Wasm_I32_And{}, &cont_body_buf)              // result & 127
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Exit])}, &cont_body_buf)
			emit_instruction(Wasm_Unreachable{}, &cont_body_buf)          // camp_exit doesn't return
			emit_instruction(Wasm_End{}, &cont_body_buf)

			cont_locals := make([]Wasm_Local_Decl, 0)
			append(&env.mod.codes, Wasm_Code{locals = cont_locals, body = copy_dynamic_bytes(cont_body_buf)})
			delete(cont_body_buf)

			ev_param_count := len(main_decl.effects)

			ev_local_indices := make([dynamic]int, 0, ev_param_count)

			// Allocate evidence records and collect local indices
			for i in 0..<ev_param_count {
				ev_local_idx := int(env.next_local)
				env.next_local += 1
				append(&ev_local_indices, ev_local_idx)

				// Determine evidence record size from effect definition
				eff := main_decl.effects[i]
				num_ops := 0
				for eff_def in ir_mod.effect_defs {
					if eff_def.name == eff {
						num_ops = len(eff_def.operations)
						break
					}
				}

				ev_record_size := num_ops * 4
				if ev_record_size == 0 {
					ev_record_size = 4
				}

				// Emit: ev_local = camp_alloc(ev_record_size)
				emit_instruction(Wasm_I32_Const{value = i32(ev_record_size)}, &code_buf)
				emit_instruction(Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Alloc])}, &code_buf)
				emit_instruction(Wasm_Local_Set{index = u32(ev_local_idx)}, &code_buf)
			}

			// Populate evidence record slots with default handler closures for prelude effects
			for i in 0..<ev_param_count {
				eff := main_decl.effects[i]
				eff_name := base.intern_get(env.interner, eff.name)
				ev_local_idx := ev_local_indices[i]

				if eff_name == "Console" {
					slot_offset := 0
					for eff_def in ir_mod.effect_defs {
						if eff_def.name == eff {
							for op_idx in 0..<len(eff_def.operations) {
								op_name := base.intern_get(env.interner, eff_def.operations[op_idx].name)
								if op_name == "println!" {
									println_handler_idx, println_code := emit_console_println_handler_fn(env, cont_func_idx)
									append(deferred_handler_codes, println_code)
									emit_handler_into_evidence(&code_buf, env, ev_local_idx, slot_offset, println_handler_idx, runtime_func_indices[:])
								} else if op_name == "readln!" {
									readln_handler_idx, readln_code := emit_console_readln_handler_fn(env)
									append(deferred_handler_codes, readln_code)
									emit_handler_into_evidence(&code_buf, env, ev_local_idx, slot_offset, readln_handler_idx, runtime_func_indices[:])
								}
								slot_offset += 4
							}
							break
						}
					}
				} else if eff_name == "Throw" {
					slot_offset := 0
					for eff_def in ir_mod.effect_defs {
						if eff_def.name == eff {
							for op_idx in 0..<len(eff_def.operations) {
								op_name := base.intern_get(env.interner, eff_def.operations[op_idx].name)
								if op_name == "throw!" {
									throw_handler_idx, throw_code := emit_throw_handler_fn(env, runtime_func_indices[:], env.throw_err_msg_offset, env.throw_err_suffix_offset)
									append(deferred_handler_codes, throw_code)
									emit_handler_into_evidence(&code_buf, env, ev_local_idx, slot_offset, throw_handler_idx, runtime_func_indices[:])
								}
								slot_offset += 4
							}
							break
						}
					}
				} else {
					// Generic unhandled effect handler: exit(1) for any operation
					slot_offset := 0
					for eff_def in ir_mod.effect_defs {
						if eff_def.name == eff {
							for op_idx in 0..<len(eff_def.operations) {
								handler_idx, handler_code := emit_unhandled_effect_handler_fn(env, eff_name, runtime_func_indices[:])
								append(deferred_handler_codes, handler_code)
								emit_handler_into_evidence(&code_buf, env, ev_local_idx, slot_offset, handler_idx, runtime_func_indices[:])
								slot_offset += 4
							}
							break
						}
					}
				}
			}

			// Push evidence pointers for the call to main!
			for ev_idx in ev_local_indices {
				emit_instruction(Wasm_Local_Get{index = u32(ev_idx)}, &code_buf)
			}
			delete(ev_local_indices)

			// Call main! with evidence pointers as arguments
			main_fn_idx, ok := env.func_map[u64(main_decl.name.name)]
			if !ok {
				mangled := base.mangle_name(main_decl.name.module, main_decl.name.name, env.interner)
				main_fn_idx = env.func_map[base.hash_string(mangled)]
			}

			// Allocate closure record for top-level continuation
			closure_local := env.next_local
			env.next_local += 1
			emit_instruction(Wasm_I32_Const{value = 24}, &code_buf)      // size = CAMP_TAG_HEADER_SIZE(8) + 2*8
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Alloc])}, &code_buf)
			emit_instruction(Wasm_Local_Set{index = closure_local}, &code_buf)

			// Set refcount = 1
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 1}, &code_buf)
			emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &code_buf)

			// Set tag = closure tag (0xFE)
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 0xFE}, &code_buf)
			emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &code_buf)

			// Set scan_size = 2 fields
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 2}, &code_buf)
			emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &code_buf)

			// Store function index = continuation function
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &code_buf)
			emit_instruction(Wasm_I32_Add{}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = i32(cont_func_idx)}, &code_buf)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &code_buf)

			// Store env = null
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, &code_buf)
			emit_instruction(Wasm_I32_Add{}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 0}, &code_buf)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &code_buf)

			// Push closure pointer as continuation argument
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)

			emit_instruction(Wasm_Call{index = u32(main_fn_idx)}, &code_buf)

			// CPS-transformed main! tail-calls the continuation — it never returns here
			emit_instruction(Wasm_Unreachable{}, &code_buf)
			emit_instruction(Wasm_End{}, &code_buf)

			start_locals := make([dynamic]Wasm_Local_Decl, 0, 8)
			append(&start_locals, Wasm_Local_Decl{count = 4, type = .I32})
			if ev_param_count > 0 {
				append(&start_locals, Wasm_Local_Decl{count = u32(ev_param_count), type = .I32})
			}
			append(&start_locals, Wasm_Local_Decl{count = 1, type = .I32})
			append(&env.mod.codes, Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)})
		} else {
			// Non-effectful main: inline the body
			main_body := extract_effectful_body(main_decl.body)

			env.local_map = make(map[base.Intern_ID]u32, 32)
			env.local_types = make(map[base.Intern_ID]base.IR_Type, 32)
			env.locals = make([dynamic]Wasm_Local_Decl, 0, 8)

			collected_locals: map[base.Intern_ID]base.IR_Type
			collected_locals = make(map[base.Intern_ID]base.IR_Type, 32)
			collect_locals(main_body, &collected_locals)
			for name, typ in collected_locals {
				env.local_map[name] = env.next_local
				env.local_types[name] = typ
				env.next_local += 1
			}

			emit_expr(main_body, &code_buf, env, runtime_func_indices[:])

			main_ret_type := get_main_return_type(ir_mod, env.interner)
			if main_ret_type == .I64 {
				emit_instruction(Wasm_I32_Wrap_I64{}, &code_buf)
				emit_instruction(Wasm_I32_Const{value = CAMP_EXIT_MASK}, &code_buf)
				emit_instruction(Wasm_I32_And{}, &code_buf)
			}

			emit_instruction(Wasm_Call{index = 0}, &code_buf)
			emit_instruction(Wasm_End{}, &code_buf)

			start_locals := make([dynamic]Wasm_Local_Decl, 0, 8)
			append(&start_locals, Wasm_Local_Decl{count = 4, type = .I32})
			for _, typ in collected_locals {
				append(&start_locals, Wasm_Local_Decl{count = 1, type = ir_wasm_type_to_value_type(typ.wasm_type)})
			}
			for l in env.locals {
				append(&start_locals, l)
			}
			append(&env.mod.codes, Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)})
			delete(collected_locals)
			delete(env.local_map)
			delete(env.local_types)
			delete(env.locals)
		}

		delete(code_buf)

		append(&env.mod.exports, Wasm_Export{name = "_start", kind = .Func, index = start_func_idx})

		// When threads > 1, also export camp_worker_entry for host-spawned workers
		if thread_count > 1 {
			// camp_worker_entry takes worker_id (i32) and calls camp_sched_worker_loop
			worker_entry_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
			worker_entry_func_idx := add_function(env, worker_entry_type_idx)

			worker_buf: [dynamic]u8
			worker_buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
			emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Sched_Worker_Loop])}, &worker_buf)
			emit_instruction(Wasm_End{}, &worker_buf)

			worker_locals := make([]Wasm_Local_Decl, 0)
			append(deferred_handler_codes, Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)})
			delete(worker_buf)

			append(&env.mod.exports, Wasm_Export{name = "camp_worker_entry", kind = .Func, index = worker_entry_func_idx})
		}
	}

	if worker_func_idx >= 0 {
		worker_buf: [dynamic]u8
		worker_buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)

		// Load env pointer from closure at CAMP_TAG_FIELDS_OFFSET + 8
		emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, &worker_buf)
		emit_instruction(Wasm_I32_Add{}, &worker_buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &worker_buf)

		// Load function index from closure at CAMP_TAG_FIELDS_OFFSET
		emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &worker_buf)

		// call_indirect with type (i32) -> (i32)
		worker_call_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
		emit_instruction(Wasm_Call_Indirect{type_idx = u32(worker_call_type_idx), table_idx = u32(env.table_idx)}, &worker_buf)

		emit_instruction(Wasm_End{}, &worker_buf)

		worker_locals := make([]Wasm_Local_Decl, 0)
		append(&env.mod.codes, Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)})
		delete(worker_buf)

		append(&env.mod.exports, Wasm_Export{name = "camp_worker_entry", kind = .Func, index = worker_func_idx})
	}
}

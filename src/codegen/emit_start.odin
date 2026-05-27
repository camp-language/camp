package codegen

import "camp:base"
import "camp:ir"


get_main_return_type :: proc(
	ir_mod: ir.IR_Module,
	interner: ^base.Intern_Table,
) -> base.IR_Wasm_Type {
	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(interner, d.name.name)
			if name_str == "main" || name_str == "main!" {
				if d.is_effectful && len(d.effects) > 0 {
					// CPS transform changes return_type to Void.
					// Recover the original type from the body's IR_Let chain.
					body := d.body
					for {
						#partial switch b in body {
						case ^ir.IR_Let:
							if b.type.wasm_type != .Void {
								return b.type.wasm_type
							}
							body = b.body
							continue
						}
						break
					}
				}
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
	main_entry_wrapper_fn_idx: int,
	main_entry_wrapper_code: ^Wasm_Code,
) {
	if start_func_idx >= 0 && main_decl != nil {
		env.next_local = 4
		env.tmp_local_base = 0
		env.tmp_count = 0

		code_buf: [dynamic]u8
		code_buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

		// `!` suffix sets is_effectful even with no inferred effects; cont_func_idx tracks the stronger condition.
		if main_decl.is_effectful && cont_func_idx >= 0 {
			// Effectful main: _start inits scheduler, spawns main!, runs loop, exits

			// Emit top-level continuation function body for CPS-transformed main!
			// The continuation takes (env: i32, result: i64) and calls camp_exit(result & 127)
			cont_body_buf: [dynamic]u8
			cont_body_buf = make([dynamic]u8, 0, CODE_BUF_MINOR)
			emit_instruction(Wasm_Local_Get{index = 1}, &cont_body_buf) // result (i64)
			emit_instruction(Wasm_I32_Wrap_I64{}, &cont_body_buf) // to i32
			emit_instruction(Wasm_I32_Const{value = CAMP_EXIT_MASK}, &cont_body_buf)
			emit_instruction(Wasm_I32_And{}, &cont_body_buf) // result & 127
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Exit])},
				&cont_body_buf,
			)
			emit_instruction(Wasm_Unreachable{}, &cont_body_buf) // camp_exit doesn't return
			emit_instruction(Wasm_End{}, &cont_body_buf)

			cont_locals := make([]Wasm_Local_Decl, 0)
			append(
				&env.mod.codes,
				Wasm_Code{locals = cont_locals, body = copy_dynamic_bytes(cont_body_buf)},
			)
			delete(cont_body_buf)

			// Append main entry wrapper code at correct position (after continuation)
			if main_entry_wrapper_code != nil {
				append(&env.mod.codes, main_entry_wrapper_code^)
			}

			ev_param_count := len(main_decl.effects)

			// Initialize scheduler before setting up evidence
			emit_instruction(Wasm_I32_Const{value = 0}, &code_buf) // worker_id = 0
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Sched_Init])},
				&code_buf,
			)

			ev_local_indices := make([dynamic]int, 0, ev_param_count)

			// Allocate evidence records and collect local indices
			for i in 0 ..< ev_param_count {
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
				emit_instruction(
					Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Alloc])},
					&code_buf,
				)
				emit_instruction(Wasm_Local_Set{index = u32(ev_local_idx)}, &code_buf)
			}

			// Populate evidence record slots with default handler closures for prelude effects
			for i in 0 ..< ev_param_count {
				eff := main_decl.effects[i]
				eff_name := base.intern_get(env.interner, eff.name)
				ev_local_idx := ev_local_indices[i]

				if eff_name == "Console" {
					slot_offset := 0
					for eff_def in ir_mod.effect_defs {
						if eff_def.name == eff {
							for op_idx in 0 ..< len(eff_def.operations) {
								op_name := base.intern_get(
									env.interner,
									eff_def.operations[op_idx].name,
								)
								if op_name == "println!" {
									println_handler_idx, println_code :=
										emit_console_println_handler_fn(env, cont_func_idx)
									append(deferred_handler_codes, println_code)
									emit_handler_into_evidence(
										&code_buf,
										env,
										ev_local_idx,
										slot_offset,
										println_handler_idx,
										runtime_func_indices[:],
									)
								} else if op_name == "readln!" {
									readln_handler_idx, readln_code :=
										emit_console_readln_handler_fn(env)
									append(deferred_handler_codes, readln_code)
									emit_handler_into_evidence(
										&code_buf,
										env,
										ev_local_idx,
										slot_offset,
										readln_handler_idx,
										runtime_func_indices[:],
									)
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
							for op_idx in 0 ..< len(eff_def.operations) {
								op_name := base.intern_get(
									env.interner,
									eff_def.operations[op_idx].name,
								)
								if op_name == "throw!" {
									throw_handler_idx, throw_code := emit_throw_handler_fn(
										env,
										runtime_func_indices[:],
										env.throw_err_msg_offset,
										env.throw_err_suffix_offset,
									)
									append(deferred_handler_codes, throw_code)
									emit_handler_into_evidence(
										&code_buf,
										env,
										ev_local_idx,
										slot_offset,
										throw_handler_idx,
										runtime_func_indices[:],
									)
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
							for op_idx in 0 ..< len(eff_def.operations) {
								handler_idx, handler_code := emit_unhandled_effect_handler_fn(
									env,
									eff_name,
									runtime_func_indices[:],
								)
								append(deferred_handler_codes, handler_code)
								emit_handler_into_evidence(
									&code_buf,
									env,
									ev_local_idx,
									slot_offset,
									handler_idx,
									runtime_func_indices[:],
								)
								slot_offset += 4
							}
							break
						}
					}
				}
			}

			// Allocate closure record for top-level continuation
			closure_local := env.next_local
			env.next_local += 1
			emit_instruction(Wasm_I32_Const{value = 24}, &code_buf) // size = CAMP_TAG_HEADER_SIZE(8) + 2*8
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Alloc])},
				&code_buf,
			)
			emit_instruction(Wasm_Local_Set{index = closure_local}, &code_buf)

			// Set refcount = 1
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 1}, &code_buf)
			emit_instruction(
				Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET},
				&code_buf,
			)

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

			// Allocate env record for main entry wrapper:
			// layout: [ev0, ev1, ..., evN, continuation_closure]
			// each slot is 4 bytes (i32), total = (ev_param_count + 1) * 4
			env_record_local := env.next_local
			env.next_local += 1
			env_record_size := (ev_param_count + 1) * 4
			emit_instruction(Wasm_I32_Const{value = i32(env_record_size)}, &code_buf)
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Alloc])},
				&code_buf,
			)
			emit_instruction(Wasm_Local_Set{index = env_record_local}, &code_buf)

			// Store evidence pointers into env record
			for i in 0 ..< ev_param_count {
				emit_instruction(Wasm_Local_Get{index = env_record_local}, &code_buf)
				emit_instruction(Wasm_I32_Const{value = i32(i * 4)}, &code_buf)
				emit_instruction(Wasm_I32_Add{}, &code_buf)
				emit_instruction(Wasm_Local_Get{index = u32(ev_local_indices[i])}, &code_buf)
				emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &code_buf)
			}
			delete(ev_local_indices)

			// Store continuation closure pointer into env record
			emit_instruction(Wasm_Local_Get{index = env_record_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = i32(ev_param_count * 4)}, &code_buf)
			emit_instruction(Wasm_I32_Add{}, &code_buf)
			emit_instruction(Wasm_Local_Get{index = closure_local}, &code_buf)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &code_buf)

			// Spawn main! via scheduler:
			// sched_spawn(fn_index=main_entry_wrapper_fn_idx, env_ptr=env_record, scope_id=0)
			emit_instruction(Wasm_I32_Const{value = i32(main_entry_wrapper_fn_idx)}, &code_buf)
			emit_instruction(Wasm_Local_Get{index = env_record_local}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 0}, &code_buf) // scope_id = 0
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Sched_Spawn])},
				&code_buf,
			)
			emit_instruction(Wasm_Drop{}, &code_buf) // discard handle_id

			// Enter scheduler loop
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Sched_Run_Single])},
				&code_buf,
			)

			// After scheduler exits, call camp_exit(0)
			emit_instruction(Wasm_I32_Const{value = 0}, &code_buf)
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Exit])},
				&code_buf,
			)
			emit_instruction(Wasm_Unreachable{}, &code_buf)
			emit_instruction(Wasm_End{}, &code_buf)

			start_locals := make([dynamic]Wasm_Local_Decl, 0, 8)
			append(&start_locals, Wasm_Local_Decl{count = 4, type = .I32})
			if ev_param_count > 0 {
				append(&start_locals, Wasm_Local_Decl{count = u32(ev_param_count), type = .I32})
			}
			append(&start_locals, Wasm_Local_Decl{count = 2, type = .I32})
			append(
				&env.mod.codes,
				Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)},
			)
		} else {
			// Non-effectful main: call main_fn and exit with its result.
			// main_fn's body is already emitted by the decl loop in codegen.odin
			// with its own local map. Inlining it here with a fresh local map
			// silently drops every let-binding (names aren't in the new map),
			// so call the existing function instead.
			emit_instruction(Wasm_Call{index = u32(main_fn_idx)}, &code_buf)

			main_ret_type := get_main_return_type(ir_mod, env.interner)
			if main_ret_type == .I64 {
				emit_instruction(Wasm_I32_Wrap_I64{}, &code_buf)
				emit_instruction(Wasm_I32_Const{value = CAMP_EXIT_MASK}, &code_buf)
				emit_instruction(Wasm_I32_And{}, &code_buf)
			} else if main_ret_type != .Void {
				emit_instruction(Wasm_I32_Const{value = CAMP_EXIT_MASK}, &code_buf)
				emit_instruction(Wasm_I32_And{}, &code_buf)
			}

			emit_instruction(Wasm_Call{index = 0}, &code_buf)
			emit_instruction(Wasm_End{}, &code_buf)

			start_locals := make([]Wasm_Local_Decl, 1)
			start_locals[0] = Wasm_Local_Decl {
				count = 4,
				type  = .I32,
			}
			append(
				&env.mod.codes,
				Wasm_Code{locals = start_locals, body = copy_dynamic_bytes(code_buf)},
			)
		}

		delete(code_buf)

		append(
			&env.mod.exports,
			Wasm_Export{name = "_start", kind = .Func, index = start_func_idx},
		)

		// When threads > 1, also export camp_worker_entry for host-spawned workers
		if thread_count > 1 {
			// camp_worker_entry takes worker_id (i32) and calls camp_sched_worker_loop
			worker_entry_type_idx := get_or_create_type(
				env,
				[]Wasm_Value_Type{.I32},
				[]Wasm_Value_Type{},
			)
			worker_entry_func_idx := add_function(env, worker_entry_type_idx)

			worker_buf: [dynamic]u8
			worker_buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
			emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
			emit_instruction(
				Wasm_Call{index = u32(runtime_func_indices[Runtime_Func.Sched_Worker_Loop])},
				&worker_buf,
			)
			emit_instruction(Wasm_End{}, &worker_buf)

			worker_locals := make([]Wasm_Local_Decl, 0)
			append(
				deferred_handler_codes,
				Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)},
			)
			delete(worker_buf)

			append(
				&env.mod.exports,
				Wasm_Export {
					name = "camp_worker_entry",
					kind = .Func,
					index = worker_entry_func_idx,
				},
			)
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
		emit_instruction(
			Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
			&worker_buf,
		)

		// call_indirect with type (i32) -> (i32)
		worker_call_type_idx := get_or_create_type(
			env,
			[]Wasm_Value_Type{.I32},
			[]Wasm_Value_Type{.I32},
		)
		emit_instruction(
			Wasm_Call_Indirect {
				type_idx = u32(worker_call_type_idx),
				table_idx = u32(env.table_idx),
			},
			&worker_buf,
		)

		emit_instruction(Wasm_End{}, &worker_buf)

		worker_locals := make([]Wasm_Local_Decl, 0)
		append(
			&env.mod.codes,
			Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)},
		)
		delete(worker_buf)

		append(
			&env.mod.exports,
			Wasm_Export{name = "camp_worker_entry", kind = .Func, index = worker_func_idx},
		)
	}
}


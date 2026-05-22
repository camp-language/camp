package camp

WASI_MODULE :: "wasi_snapshot_preview1"

RUNTIME_FUNC_COUNT :: 17

CAMP_TAG_HEADER_SIZE :: 8
CAMP_TAG_REFCOUNT_OFFSET :: 0
CAMP_TAG_TAG_OFFSET :: 4
CAMP_TAG_SCAN_SIZE_OFFSET :: 5
CAMP_TAG_FIELDS_OFFSET :: 8

		Codegen_Env :: struct {
	mod:           ^Wasm_Module,
	interner:      ^Intern_Table,
	type_map:      map[int]int,
	func_map:      map[int]int,
	next_type_idx: int,
	next_func_idx: int,
	import_count:  int,
	data_offset:   u32,
	locals:        [dynamic]Wasm_Local_Decl,
	local_map:     map[Intern_ID]u32,
	next_local:    u32,
	tmp_local_base: u32,
	tmp_count:     u32,
	table_idx:     int,
	func_type_indices: [dynamic]u32,
}

hash_func_type :: proc(params: []Wasm_Value_Type, results: []Wasm_Value_Type) -> int {
	h: int = 0x9E3779B9
	for p in params {
		h = h * 31 + int(p)
	}
	h = h * 37
	for r in results {
		h = h * 31 + int(r)
	}
	return h
}

get_or_create_type :: proc(env: ^Codegen_Env, params: []Wasm_Value_Type, results: []Wasm_Value_Type) -> int {
	h := hash_func_type(params, results)
	if idx, ok := env.type_map[h]; ok {
		return idx
	}
	idx := env.next_type_idx
	env.next_type_idx += 1
	env.type_map[h] = idx

	p_copy := make([]Wasm_Value_Type, len(params))
	for v, i in params {
		p_copy[i] = v
	}
	r_copy := make([]Wasm_Value_Type, len(results))
	for v, i in results {
		r_copy[i] = v
	}

	append(&env.mod.types, Wasm_Func_Type{params = p_copy, results = r_copy})
	return idx
}

add_import :: proc(env: ^Codegen_Env, module: string, field: string, kind: Wasm_External_Kind, type_idx: int) -> int {
	idx := env.next_func_idx
	env.next_func_idx += 1
	env.import_count += 1
	append(&env.mod.imports, Wasm_Import{
		module = module,
		field = field,
		kind = kind,
		index = type_idx,
	})
	return idx
}

add_function :: proc(env: ^Codegen_Env, type_idx: int) -> int {
	idx := env.next_func_idx
	env.next_func_idx += 1
	append(&env.mod.functions, type_idx)
	return idx
}

emit_wasi_imports :: proc(env: ^Codegen_Env) {
	proc_exit_type := get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	add_import(env, WASI_MODULE, "proc_exit", .Func, proc_exit_type)

	fd_write_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "fd_write", .Func, fd_write_type)

	args_get_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "args_get", .Func, args_get_type)

	args_sizes_get_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "args_sizes_get", .Func, args_sizes_get_type)
}

emit_runtime_types :: proc(env: ^Codegen_Env) {
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
}

codegen :: proc(ir_mod: IR_Module, ctx: ^Compilation_Context) -> Wasm_Module {
	mod: Wasm_Module
	mod.types = make([dynamic]Wasm_Func_Type, 0, 64)
	mod.imports = make([dynamic]Wasm_Import, 0, 16)
	mod.functions = make([dynamic]int, 0, 64)
	mod.tables = make([dynamic]Wasm_Table, 0, 4)
	mod.memories = make([dynamic]Wasm_Memory, 0, 4)
	mod.globals = make([dynamic]Wasm_Global, 0, 8)
	mod.exports = make([dynamic]Wasm_Export, 0, 16)
	mod.start = -1
	mod.elements = make([dynamic]Wasm_Element, 0, 4)
	mod.codes = make([dynamic]Wasm_Code, 0, 64)
	mod.datas = make([dynamic]Wasm_Data, 0, 16)

	env: Codegen_Env
	env.mod = &mod
	env.interner = &ctx.interner
	env.type_map = make(map[int]int, 64)
	env.func_map = make(map[int]int, 64)
	env.next_type_idx = 0
	env.next_func_idx = 0
	env.import_count = 0
	env.data_offset = 0
	env.locals = make([dynamic]Wasm_Local_Decl, 0, 32)
	env.local_map = make(map[Intern_ID]u32, 32)
	env.table_idx = -1
	env.func_type_indices = make([dynamic]u32, 0, 64)

	emit_wasi_imports(&env)
	emit_runtime_types(&env)

	// Memory: shared when threads > 1, with maximum for WASM threads
	if ctx.thread_count > 1 {
		append(&mod.memories, Wasm_Memory{min = 1, max = 65536, has_max = true, shared = true})
	} else {
		append(&mod.memories, Wasm_Memory{min = 1})
	}

	env.table_idx = len(mod.tables)
	append(&mod.tables, Wasm_Table{
		elem_type = .Funcref,
		min = 1,
		max = 1,
		has_max = true,
	})

	for entry in ir_mod.string_table {
		bytes := transmute([]u8)entry.value
		env.data_offset += u32(len(bytes))
	}

	heap_ptr_global_idx := len(mod.globals)
	heap_ptr_init: [dynamic]u8
	heap_ptr_init = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = i32(env.data_offset)}, &heap_ptr_init)
	append(&mod.globals, Wasm_Global{
		type = .I32,
		mutable = true,
		init = copy_dynamic_bytes(heap_ptr_init),
	})
	delete(heap_ptr_init)

	alloc_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	dup_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	drop_type_idx := dup_type_idx
	print_str_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	exit_type_idx := dup_type_idx

	runtime_func_indices: [RUNTIME_FUNC_COUNT]int
	alloc_func_idx := add_function(&env, alloc_type_idx)
	runtime_func_indices[0] = alloc_func_idx
	dup_func_idx := add_function(&env, dup_type_idx)
	runtime_func_indices[1] = dup_func_idx
	drop_func_idx := add_function(&env, drop_type_idx)
	runtime_func_indices[2] = drop_func_idx
	print_str_func_idx := add_function(&env, print_str_type_idx)
	runtime_func_indices[3] = print_str_func_idx
	exit_func_idx := add_function(&env, exit_type_idx)
	runtime_func_indices[4] = exit_func_idx

	// Scheduler runtime function types
	sched_init_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	sched_spawn_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	sched_join_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	sched_cancel_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	sched_complete_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32}, []Wasm_Value_Type{})
	sched_yield_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_block_io_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	sched_timer_insert_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	sched_timer_cancel_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	sched_notify_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_park_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_worker_loop_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})

	sched_init_func_idx := add_function(&env, sched_init_type_idx)
	runtime_func_indices[RUNTIME_SCHED_INIT] = sched_init_func_idx
	sched_spawn_func_idx := add_function(&env, sched_spawn_type_idx)
	runtime_func_indices[RUNTIME_SCHED_SPAWN] = sched_spawn_func_idx
	sched_join_func_idx := add_function(&env, sched_join_type_idx)
	runtime_func_indices[RUNTIME_SCHED_JOIN] = sched_join_func_idx
	sched_cancel_func_idx := add_function(&env, sched_cancel_type_idx)
	runtime_func_indices[RUNTIME_SCHED_CANCEL] = sched_cancel_func_idx
	sched_complete_func_idx := add_function(&env, sched_complete_type_idx)
	runtime_func_indices[RUNTIME_SCHED_COMPLETE] = sched_complete_func_idx
	sched_yield_func_idx := add_function(&env, sched_yield_type_idx)
	runtime_func_indices[RUNTIME_SCHED_YIELD] = sched_yield_func_idx
	sched_block_io_func_idx := add_function(&env, sched_block_io_type_idx)
	runtime_func_indices[RUNTIME_SCHED_BLOCK_IO] = sched_block_io_func_idx
	sched_timer_insert_func_idx := add_function(&env, sched_timer_insert_type_idx)
	runtime_func_indices[RUNTIME_SCHED_TIMER_INSERT] = sched_timer_insert_func_idx
	sched_timer_cancel_func_idx := add_function(&env, sched_timer_cancel_type_idx)
	runtime_func_indices[RUNTIME_SCHED_TIMER_CANCEL] = sched_timer_cancel_func_idx
	sched_notify_func_idx := add_function(&env, sched_notify_type_idx)
	runtime_func_indices[RUNTIME_SCHED_NOTIFY] = sched_notify_func_idx
	sched_park_func_idx := add_function(&env, sched_park_type_idx)
	runtime_func_indices[RUNTIME_SCHED_PARK] = sched_park_func_idx
	sched_worker_loop_func_idx := add_function(&env, sched_worker_loop_type_idx)
	runtime_func_indices[RUNTIME_SCHED_WORKER_LOOP] = sched_worker_loop_func_idx

	camp_alloc_code := emit_camp_alloc_body(heap_ptr_global_idx)
	append(&mod.codes, camp_alloc_code)

	camp_dup_code := emit_camp_dup_body()
	append(&mod.codes, camp_dup_code)

	camp_drop_code := emit_camp_drop_body(alloc_func_idx)
	append(&mod.codes, camp_drop_code)

	camp_print_str_code := emit_camp_print_str_body()
	append(&mod.codes, camp_print_str_code)

	camp_exit_code := emit_camp_exit_body()
	append(&mod.codes, camp_exit_code)

	// Scheduler runtime function bodies
	append(&mod.codes, emit_camp_sched_init_body())
	append(&mod.codes, emit_camp_sched_spawn_body())
	append(&mod.codes, emit_camp_sched_join_body())
	append(&mod.codes, emit_camp_sched_cancel_body())
	append(&mod.codes, emit_camp_sched_complete_body())
	append(&mod.codes, emit_camp_sched_yield_body())
	append(&mod.codes, emit_camp_sched_block_io_body())
	append(&mod.codes, emit_camp_sched_timer_insert_body())
	append(&mod.codes, emit_camp_sched_timer_cancel_body())
	append(&mod.codes, emit_camp_sched_notify_body())
	append(&mod.codes, emit_camp_sched_park_body())
	append(&mod.codes, emit_camp_sched_worker_loop_body())

	main_fn_idx := -1
	main_decl: ^IR_Decl_Fn = nil
	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			name_str := intern_get(&ctx.interner, d.name.name)
			params := make([]Wasm_Value_Type, len(d.params))
			for p, i in d.params {
				params[i] = ir_wasm_type_to_value_type(p.type.wasm_type)
			}
			results: []Wasm_Value_Type
			if d.return_type.wasm_type != .Void {
				results = make([]Wasm_Value_Type, 1)
				results[0] = ir_wasm_type_to_value_type(d.return_type.wasm_type)
			}
			
			type_idx := get_or_create_type(&env, params, results)
			func_idx := add_function(&env, type_idx)
			if d.name.module != NO_NAME {
				mangled := mangle_name(d.name.module, d.name.name, &ctx.interner)
				env.func_map[hash_string(mangled)] = func_idx
			}
			env.func_map[int(d.name.name)] = func_idx

			for len(env.func_type_indices) <= func_idx {
				append(&env.func_type_indices, 0)
			}
			env.func_type_indices[func_idx] = u32(type_idx)

			if name_str == "main" || name_str == "main!" {
				main_fn_idx = func_idx
				main_decl = d
			}
		case:
		}
	}

	start_func_idx := -1
	if main_fn_idx >= 0 && main_decl != nil {
		start_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
		start_func_idx = add_function(&env, start_type_idx)
	}

	append(&mod.exports, Wasm_Export{name = "memory", kind = .Memory, index = 0})

	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			is_main := intern_get(&ctx.interner, d.name.name) == "main" || intern_get(&ctx.interner, d.name.name) == "main!"

			if is_main && d.is_effectful {
				env.locals = make([dynamic]Wasm_Local_Decl, 0, 32)
				env.local_map = make(map[Intern_ID]u32, 32)
				env.next_local = u32(len(d.params))

				for p, i in d.params {
					env.local_map[p.name] = u32(i)
				}

				collected_locals: map[Intern_ID]IR_Type
				collected_locals = make(map[Intern_ID]IR_Type, 32)
				collect_locals(d.body, &collected_locals)

				local_groups: map[Wasm_Value_Type][dynamic]Intern_ID
				local_groups = make(map[Wasm_Value_Type][dynamic]Intern_ID, 8)

				for name, typ in collected_locals {
					vt := ir_wasm_type_to_value_type(typ.wasm_type)
					if vt in local_groups {
						append(&local_groups[vt], name)
					} else {
						list: [dynamic]Intern_ID
						list = make([dynamic]Intern_ID, 0, 8)
						append(&list, name)
						local_groups[vt] = list
					}
				}

				for vt, names in local_groups {
					for name in names {
						env.local_map[name] = env.next_local
						env.next_local += 1
					}
					append(&env.locals, Wasm_Local_Decl{count = u32(len(names)), type = vt})
					delete(names)
				}
				delete(local_groups)
				delete(collected_locals)

				env.tmp_local_base = env.next_local
				env.tmp_count = 0
				append(&env.locals, Wasm_Local_Decl{count = 4, type = .I32})
				env.next_local += 4

				body_buf: [dynamic]u8
				body_buf = make([dynamic]u8, 0, 512)
				emit_expr(d.body, &body_buf, &env, runtime_func_indices[:])
				emit_instruction(Wasm_End{}, &body_buf)

				locals_copy := make([]Wasm_Local_Decl, len(env.locals))
				for l, i in env.locals {
					locals_copy[i] = l
				}

				append(&mod.codes, Wasm_Code{locals = locals_copy, body = copy_dynamic_bytes(body_buf)})
				delete(body_buf)
				delete(env.locals)
				delete(env.local_map)
				continue
			}

			env.locals = make([dynamic]Wasm_Local_Decl, 0, 32)
			env.local_map = make(map[Intern_ID]u32, 32)
			env.next_local = u32(len(d.params))

			for p, i in d.params {
				env.local_map[p.name] = u32(i)
			}

			collected_locals: map[Intern_ID]IR_Type
			collected_locals = make(map[Intern_ID]IR_Type, 32)
			collect_locals(d.body, &collected_locals)

			local_groups: map[Wasm_Value_Type][dynamic]Intern_ID
			local_groups = make(map[Wasm_Value_Type][dynamic]Intern_ID, 8)

			for name, typ in collected_locals {
				vt := ir_wasm_type_to_value_type(typ.wasm_type)
				if vt in local_groups {
					append(&local_groups[vt], name)
				} else {
					list: [dynamic]Intern_ID
					list = make([dynamic]Intern_ID, 0, 8)
					append(&list, name)
					local_groups[vt] = list
				}
			}

			for vt, names in local_groups {
				for name in names {
					env.local_map[name] = env.next_local
					env.next_local += 1
				}
				append(&env.locals, Wasm_Local_Decl{count = u32(len(names)), type = vt})
				delete(names)
			}
			delete(local_groups)
			delete(collected_locals)

			env.tmp_local_base = env.next_local
			env.tmp_count = 0
			append(&env.locals, Wasm_Local_Decl{count = 4, type = .I32})
			env.next_local += 4

			body_buf: [dynamic]u8
			body_buf = make([dynamic]u8, 0, 512)
			emit_expr(d.body, &body_buf, &env, runtime_func_indices[:])
			emit_instruction(Wasm_End{}, &body_buf)

			locals_copy := make([]Wasm_Local_Decl, len(env.locals))
			for l, i in env.locals {
				locals_copy[i] = l
			}

			append(&mod.codes, Wasm_Code{locals = locals_copy, body = copy_dynamic_bytes(body_buf)})
			delete(body_buf)
			delete(env.locals)
			delete(env.local_map)
		case:
		}
	}

	if env.table_idx >= 0 && len(env.func_type_indices) > 0 {
		total_funcs := len(env.func_type_indices)

		mod.tables[env.table_idx].min = u32(total_funcs)
		mod.tables[env.table_idx].max = u32(total_funcs)

		elem_offset_buf: [dynamic]u8
		elem_offset_buf = make([dynamic]u8, 0, 8)
		emit_instruction(Wasm_I32_Const{value = 0}, &elem_offset_buf)

		elem_func_indices: [dynamic]int
		elem_func_indices = make([dynamic]int, 0, total_funcs)
		for i in 0..<total_funcs {
			append(&elem_func_indices, i)
		}

		append(&mod.elements, Wasm_Element{
			table_idx = env.table_idx,
			offset = copy_dynamic_bytes(elem_offset_buf),
			func_idxs = elem_func_indices[:],
		})
		delete(elem_offset_buf)
		delete(elem_func_indices)
	}

	if start_func_idx >= 0 && main_decl != nil {
		env.tmp_local_base = 0
		env.next_local = 4

		code_buf: [dynamic]u8
		code_buf = make([dynamic]u8, 0, 256)

		main_body := extract_effectful_body(main_decl.body)

		collected_locals: map[Intern_ID]IR_Type
		collected_locals = make(map[Intern_ID]IR_Type, 32)
		collect_locals(main_body, &collected_locals)
		env.local_map = make(map[Intern_ID]u32, 32)
		for name, typ in collected_locals {
			env.local_map[name] = env.next_local
			env.next_local += 1
		}

		emit_expr(main_body, &code_buf, &env, runtime_func_indices[:])

		main_ret_type := get_main_return_type(ir_mod, &ctx.interner)
		if main_ret_type == .I64 {
			emit_instruction(Wasm_I32_Wrap_I64{}, &code_buf)
			emit_instruction(Wasm_I32_Const{value = 127}, &code_buf)
			emit_instruction(Wasm_I32_And{}, &code_buf)
		}

		// If main is effectful, initialize scheduler before running main body
		// and enter worker loop after
		if main_decl.is_effectful {
			// Prepend scheduler init: camp_sched_init(thread_count)
			pre_buf: [dynamic]u8
			pre_buf = make([dynamic]u8, 0, 32)
			emit_instruction(Wasm_I32_Const{value = i32(ctx.thread_count)}, &pre_buf)
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_SCHED_INIT])}, &pre_buf)

			// Append worker loop entry: camp_sched_worker_loop(0)
			post_buf: [dynamic]u8
			post_buf = make([dynamic]u8, 0, 16)
			emit_instruction(Wasm_I32_Const{value = 0}, &post_buf)
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_SCHED_WORKER_LOOP])}, &post_buf)

			// Combine: pre + original body + post
			combined: [dynamic]u8
			combined = make([dynamic]u8, 0, len(pre_buf) + len(code_buf) + len(post_buf))
			for b in pre_buf { append(&combined, b) }
			for b in code_buf { append(&combined, b) }
			for b in post_buf { append(&combined, b) }
			delete(code_buf)
			code_buf = combined
			delete(pre_buf)
			delete(post_buf)
		}

		emit_instruction(Wasm_Call{index = 0}, &code_buf)
		emit_instruction(Wasm_End{}, &code_buf)

		start_locals := make([dynamic]Wasm_Local_Decl, 0, 8)
		append(&start_locals, Wasm_Local_Decl{count = 4, type = .I32})
		for _, typ in collected_locals {
			append(&start_locals, Wasm_Local_Decl{count = 1, type = ir_wasm_type_to_value_type(typ.wasm_type)})
		}
		append(&mod.codes, Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)})
		delete(collected_locals)
		delete(code_buf)
		delete(env.local_map)

		append(&mod.exports, Wasm_Export{name = "_start", kind = .Func, index = start_func_idx})

		// When threads > 1, also export camp_worker_entry for host-spawned workers
		if ctx.thread_count > 1 {
			// camp_worker_entry takes worker_id (i32) and calls camp_sched_worker_loop
			worker_entry_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
			worker_entry_func_idx := add_function(&env, worker_entry_type_idx)

			worker_buf: [dynamic]u8
			worker_buf = make([dynamic]u8, 0, 64)
			emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_SCHED_WORKER_LOOP])}, &worker_buf)
			emit_instruction(Wasm_End{}, &worker_buf)

			worker_locals := make([]Wasm_Local_Decl, 0)
			append(&mod.codes, Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)})
			delete(worker_buf)

			append(&mod.exports, Wasm_Export{name = "camp_worker_entry", kind = .Func, index = worker_entry_func_idx})
		}
	}

	env.data_offset = 0
	for entry in ir_mod.string_table {
		offset := env.data_offset
		bytes := transmute([]u8)entry.value
		env.data_offset += u32(len(bytes))

		offset_buf: [dynamic]u8
		offset_buf = make([dynamic]u8, 0, 8)
		emit_instruction(Wasm_I32_Const{value = i32(offset)}, &offset_buf)
		emit_instruction(Wasm_End{}, &offset_buf)

		append(&mod.datas, Wasm_Data{
			mem_idx = 0,
			offset = copy_dynamic_bytes(offset_buf),
			bytes = bytes,
		})
		delete(offset_buf)
	}

	delete(env.type_map)
	delete(env.func_map)
	delete(env.func_type_indices)
	return mod
}

get_main_return_type :: proc(ir_mod: IR_Module, interner: ^Intern_Table) -> IR_Wasm_Type {
	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			name_str := intern_get(interner, d.name.name)
			if name_str == "main" || name_str == "main!" {
				return d.return_type.wasm_type
			}
		case:
		}
	}
	return .I64
}

collect_locals :: proc(expr: IR_Expr, locals: ^map[Intern_ID]IR_Type) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Let:
		locals^[e.binding] = e.type
		collect_locals(e.value, locals)
		collect_locals(e.body, locals)
	case ^IR_Call:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^IR_Closure_Call:
		collect_locals(e.callee, locals)
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^IR_If:
		collect_locals(e.condition, locals)
		collect_locals(e.then_branch, locals)
		collect_locals(e.else_branch, locals)
	case ^IR_Match:
		collect_locals(e.scrutinee, locals)
		for arm in e.arms {
			collect_locals(arm.body, locals)
		}
	case ^IR_BinOp:
		collect_locals(e.left, locals)
		collect_locals(e.right, locals)
	case ^IR_Return:
		collect_locals(e.value, locals)
	case ^IR_Block:
		for stmt in e.statements {
			collect_locals(stmt, locals)
		}
	case ^IR_Construct_Tag:
		for p in e.payload {
			collect_locals(p, locals)
		}
	case ^IR_Construct_Record:
		for f in e.fields {
			collect_locals(f.value, locals)
		}
		collect_locals(e.rest, locals)
	case ^IR_Field_Access:
		collect_locals(e.record, locals)
	case ^IR_Method_Call:
		collect_locals(e.receiver, locals)
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^IR_Handle:
		collect_locals(e.body, locals)
		for arm in e.arms {
			collect_locals(arm.body, locals)
		}
	case ^IR_Perform:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^IR_Closure:
		collect_locals(e.env, locals)
		collect_locals(e.body, locals)
	case ^IR_Crash:
		collect_locals(e.message, locals)
	case ^IR_Resume:
		collect_locals(e.value, locals)
	case ^IR_Atomic_Load:
		collect_locals(e.ptr, locals)
	case ^IR_Atomic_Store:
		collect_locals(e.ptr, locals)
		collect_locals(e.value, locals)
	case ^IR_Atomic_RMW:
		collect_locals(e.ptr, locals)
		collect_locals(e.value, locals)
	case ^IR_Atomic_Fence:
	case ^IR_Wait:
		collect_locals(e.ptr, locals)
		collect_locals(e.expected, locals)
	case ^IR_Notify:
		collect_locals(e.ptr, locals)
		collect_locals(e.count, locals)
	case:
	}
}

RUNTIME_ALLOC :: 0
RUNTIME_DUP :: 1
RUNTIME_DROP :: 2
RUNTIME_PRINT_STR :: 3
RUNTIME_EXIT :: 4
RUNTIME_SCHED_INIT :: 5
RUNTIME_SCHED_SPAWN :: 6
RUNTIME_SCHED_JOIN :: 7
RUNTIME_SCHED_CANCEL :: 8
RUNTIME_SCHED_COMPLETE :: 9
RUNTIME_SCHED_YIELD :: 10
RUNTIME_SCHED_BLOCK_IO :: 11
RUNTIME_SCHED_TIMER_INSERT :: 12
RUNTIME_SCHED_TIMER_CANCEL :: 13
RUNTIME_SCHED_NOTIFY :: 14
RUNTIME_SCHED_PARK :: 15
RUNTIME_SCHED_WORKER_LOOP :: 16

extract_effectful_body :: proc(expr: IR_Expr) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Let:
		#partial switch b in e.body {
		case ^IR_Tail_Call, ^IR_Closure_Call:
			return e.value
		case:
			return expr
		}
	case:
		return expr
	}
}

emit_expr :: proc(expr: IR_Expr, buf: ^[dynamic]u8, env: ^Codegen_Env, runtime_indices: []int) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Literal_Int:
		if e.type.wasm_type == .I32 {
			emit_instruction(Wasm_I32_Const{value = i32(e.value)}, buf)
		} else {
			emit_instruction(Wasm_I64_Const{value = e.value}, buf)
		}
	case ^IR_Literal_Float:
		emit_instruction(Wasm_F64_Const{value = e.value}, buf)
	case ^IR_Literal_Bool:
		if e.value {
			emit_instruction(Wasm_I32_Const{value = 1}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
	case ^IR_Literal_String:
		emit_instruction(Wasm_I32_Const{value = i32(env.data_offset)}, buf)
		env.data_offset += u32(len(e.value))
	case ^IR_Var:
		if idx, ok := env.local_map[e.name]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
		} else if idx, ok := env.func_map[int(e.name)]; ok {
			emit_instruction(Wasm_I32_Const{value = i32(idx)}, buf)
		} else {
			emit_instruction(Wasm_I64_Const{value = 0}, buf)
		}
	case ^IR_Let:
		emit_expr(e.value, buf, env, runtime_indices)
		if idx, ok := env.local_map[e.binding]; ok {
			emit_instruction(Wasm_Local_Set{index = idx}, buf)
		} else {
			emit_instruction(Wasm_Drop{}, buf)
		}
		emit_expr(e.body, buf, env, runtime_indices)
		case ^IR_Call:
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		call_idx: int = 0
		if e.callee.module != NO_NAME {
			mangled := mangle_name(e.callee.module, e.callee.name, env.interner)
			if idx, ok := env.func_map[hash_string(mangled)]; ok {
				call_idx = idx
			} else if idx, ok := env.func_map[int(e.callee.name)]; ok {
				call_idx = idx
			}
		} else if idx, ok := env.func_map[int(e.callee.name)]; ok {
			call_idx = idx
		}
		emit_instruction(Wasm_Call{index = u32(call_idx)}, buf)
	case ^IR_Tail_Call:
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		tail_idx: int = 0
		if e.callee.module != NO_NAME {
			mangled := mangle_name(e.callee.module, e.callee.name, env.interner)
			if idx, ok := env.func_map[hash_string(mangled)]; ok {
				tail_idx = idx
			} else if idx, ok := env.func_map[int(e.callee.name)]; ok {
				tail_idx = idx
			}
		} else if idx, ok := env.func_map[int(e.callee.name)]; ok {
			tail_idx = idx
		}
		emit_instruction(Wasm_Return_Call{index = u32(tail_idx)}, buf)
	case ^IR_If:
		emit_expr(e.condition, buf, env, runtime_indices)
		block_type := ir_wasm_type_to_block_type(e.type.wasm_type)
		emit_instruction(Wasm_If{block_type = block_type}, buf)
		emit_expr(e.then_branch, buf, env, runtime_indices)
		emit_instruction(Wasm_Else{}, buf)
		emit_expr(e.else_branch, buf, env, runtime_indices)
		emit_instruction(Wasm_End{}, buf)
	case ^IR_Return:
		emit_expr(e.value, buf, env, runtime_indices)
		emit_instruction(Wasm_Return{}, buf)
	case ^IR_BinOp:
		emit_expr(e.left, buf, env, runtime_indices)
		emit_expr(e.right, buf, env, runtime_indices)
		operand_type := ir_operand_wasm_type(e.left)
		emit_binop(e.op, operand_type, buf)
	case ^IR_Dup:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_DUP])}, buf)
		}
	case ^IR_Drop:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_DROP])}, buf)
		}
	case ^IR_Block:
		for stmt, idx in e.statements {
			emit_expr(stmt, buf, env, runtime_indices)
			if idx < len(e.statements) - 1 && e.type.wasm_type != .Void {
				emit_instruction(Wasm_Drop{}, buf)
			}
		}
	case ^IR_Match:
		emit_instruction(Wasm_Block{block_type = ir_wasm_type_to_block_type(e.type.wasm_type)}, buf)

		emit_expr(e.scrutinee, buf, env, runtime_indices)
		scrutinee_local := env.tmp_local_base + 2
		emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

		emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
		emit_instruction(Wasm_I32_Load8U{offset = CAMP_TAG_TAG_OFFSET}, buf)

		num_arms := len(e.arms)
		default_target := u32(num_arms - 1)
		targets := make([]u32, num_arms)
		for i in 0..<num_arms {
			targets[i] = u32(i)
			#partial switch p in e.arms[i].pattern {
			case ^IR_Pat_Wildcard:
				default_target = u32(i)
			case:
			}
		}

		emit_instruction(Wasm_BrTable{targets = targets, default_idx = default_target}, buf)

		for arm_idx in 0..<len(e.arms) {
			arm := e.arms[arm_idx]
			emit_instruction(Wasm_Block{block_type = ir_wasm_type_to_block_type(e.type.wasm_type)}, buf)

			#partial switch p in arm.pattern {
			case ^IR_Pat_Tag:
				for j in 0..<len(p.payload) {
					payload_name := p.payload[j]
					emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
					emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + j * 8)}, buf)
					emit_instruction(Wasm_I32_Add{}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
					if local_idx, ok := env.local_map[payload_name]; ok {
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					} else {
						emit_instruction(Wasm_Drop{}, buf)
					}
				}
			case ^IR_Pat_Var:
				emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
				if local_idx, ok := env.local_map[p.name]; ok {
					emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
				} else {
					emit_instruction(Wasm_Drop{}, buf)
				}
			case ^IR_Pat_Wildcard:
			case ^IR_Pat_Record:
			}

			emit_expr(arm.body, buf, env, runtime_indices)
			emit_instruction(Wasm_Br{label = 1}, buf)
			emit_instruction(Wasm_End{}, buf)
		}

		emit_instruction(Wasm_Unreachable{}, buf)
		emit_instruction(Wasm_End{}, buf)

	case ^IR_Construct_Tag:
		num_fields := len(e.payload)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.tmp_local_base
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(e.tag_index)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

		for i in 0..<len(e.payload) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(e.payload[i], buf, env, runtime_indices)
			emit_store_for_type(ir_expr_wasm_type(e.payload[i]), buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^IR_Construct_Record:
		num_fields := len(e.fields)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.tmp_local_base
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 0xFF}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

		for i in 0..<len(e.fields) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(e.fields[i].value, buf, env, runtime_indices)
			emit_store_for_type(ir_expr_wasm_type(e.fields[i].value), buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^IR_Field_Access:
		emit_expr(e.record, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + e.field_index * 8)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_load_for_type(e.type.wasm_type, buf)
	case ^IR_Method_Call:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Handle:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Perform:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Closure:
		num_fields := len(e.params) + 2
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.tmp_local_base
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 0xFE}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		fn_idx := resolve_call_idx(e.fn_name, env)
		if fn_idx > 0 {
			emit_instruction(Wasm_I32_Const{value = i32(fn_idx)}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_expr(e.env, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^IR_Closure_Call:
		emit_expr(e.callee, buf, env, runtime_indices)

		callee_local := env.tmp_local_base + 1
		emit_instruction(Wasm_Local_Set{index = callee_local}, buf)

		emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}

		emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

		closure_params := make([]Wasm_Value_Type, len(e.args) + 1)
		closure_params[0] = .I32
		for idx := 0; idx < len(e.args); idx += 1 {
			closure_params[idx + 1] = ir_wasm_type_to_value_type(ir_expr_wasm_type(e.args[idx]))
		}
		closure_results := make([]Wasm_Value_Type, 1)
		closure_results[0] = ir_wasm_type_to_value_type(e.type.wasm_type)
		closure_type_idx := get_or_create_type(env, closure_params, closure_results)
		delete(closure_params)
		delete(closure_results)

		emit_instruction(Wasm_Call_Indirect{type_idx = u32(closure_type_idx), table_idx = u32(env.table_idx)}, buf)

	case ^IR_Drop_Reuse:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_DROP])}, buf)
		}
	case ^IR_Alloc_At:
		emit_instruction(Wasm_I32_Const{value = 16}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)
	case ^IR_Crash:
		emit_expr(e.message, buf, env, runtime_indices)
		emit_instruction(Wasm_Drop{}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_EXIT])}, buf)
	case ^IR_Resume:
		// Load closure from resume_id local
		if idx, ok := env.local_map[e.resume_id]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
		resume_local := env.tmp_local_base + 2
		emit_instruction(Wasm_Local_Set{index = resume_local}, buf)

		// One-shot check: load fn_idx, trap if zero (already consumed)
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_I32_Eq{}, buf)
		emit_instruction(Wasm_If{block_type = .Void}, buf)
		emit_instruction(Wasm_Unreachable{}, buf)
		emit_instruction(Wasm_End{}, buf)

		// Zero fn_idx (mark consumed)
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Const{value = 0}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

		// Load env_ptr, push value arg, load fn_idx, call_indirect
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

		emit_expr(e.value, buf, env, runtime_indices)

		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

		resume_params := make([]Wasm_Value_Type, 2)
		resume_params[0] = .I32
		resume_params[1] = ir_wasm_type_to_value_type(ir_expr_wasm_type(e.value))
		resume_results := make([]Wasm_Value_Type, 1)
		resume_results[0] = ir_wasm_type_to_value_type(e.type.wasm_type)
		resume_type_idx := get_or_create_type(env, resume_params, resume_results)
		delete(resume_params)
		delete(resume_results)

		emit_instruction(Wasm_Call_Indirect{type_idx = u32(resume_type_idx), table_idx = u32(env.table_idx)}, buf)

	case ^IR_Atomic_Load:
		emit_expr(e.ptr, buf, env, runtime_indices)
		emit_atomic_load(e.width, e.offset, buf)

	case ^IR_Atomic_Store:
		emit_expr(e.ptr, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_store(e.width, e.offset, buf)

	case ^IR_Atomic_RMW:
		emit_expr(e.ptr, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_rmw(e.op, e.width, e.offset, buf)

	case ^IR_Atomic_Fence:
		emit_instruction(Wasm_Atomic_Fence{}, buf)

	case ^IR_Wait:
		emit_expr(e.ptr, buf, env, runtime_indices)
		emit_expr(e.expected, buf, env, runtime_indices)
		if e.timeout >= 0 {
			emit_instruction(Wasm_I64_Const{value = e.timeout}, buf)
		} else {
			emit_instruction(Wasm_I64_Const{value = -1}, buf)
		}
		if e.width == .B8 {
			emit_instruction(Wasm_Memory_Atomic_Wait64{align = 3, offset = e.offset}, buf)
		} else {
			emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = e.offset}, buf)
		}

	case ^IR_Notify:
		emit_expr(e.ptr, buf, env, runtime_indices)
		emit_expr(e.count, buf, env, runtime_indices)
		emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = e.offset}, buf)

	case:
		emit_instruction(Wasm_Unreachable{}, buf)
	}
}

emit_binop :: proc(op: Token_Kind, operand_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Plus:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Add{}, buf)
		} else {
			emit_instruction(Wasm_I64_Add{}, buf)
		}
	case .Minus:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Sub{}, buf)
		} else {
			emit_instruction(Wasm_I64_Sub{}, buf)
		}
	case .Star:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Mul{}, buf)
		} else {
			emit_instruction(Wasm_I64_Mul{}, buf)
		}
	case .Eq_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Eq{}, buf)
		} else {
			emit_instruction(Wasm_I32_Eq{}, buf)
		}
	case .Bang_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ne{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ne{}, buf)
		}
	case .Lt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Lt_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Lt_S{}, buf)
		}
	case .Gt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Gt_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Gt_S{}, buf)
		}
	case .Lt_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Le_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Le_S{}, buf)
		}
	case .Gt_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ge_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ge_S{}, buf)
		}
	case .Kw_And:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_And{}, buf)
		} else {
			emit_instruction(Wasm_I32_And{}, buf)
		}
	case .Kw_Or:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Or{}, buf)
		} else {
			emit_instruction(Wasm_I32_Or{}, buf)
		}
	case:
		emit_instruction(Wasm_I64_Add{}, buf)
	}
}

ir_operand_wasm_type :: proc(expr: IR_Expr) -> IR_Wasm_Type {
	if expr == nil do return .I32
	#partial switch e in expr {
	case ^IR_Literal_Int: return e.type.wasm_type
	case ^IR_Literal_Float: return e.type.wasm_type
	case ^IR_Literal_Bool: return .I32
	case ^IR_Literal_String: return .I32
	case ^IR_Var: return e.type.wasm_type
	case ^IR_BinOp: return e.type.wasm_type
	case ^IR_Call: return e.type.wasm_type
	case ^IR_If: return e.type.wasm_type
	case ^IR_Closure_Call: return e.type.wasm_type
	case ^IR_Field_Access: return e.type.wasm_type
	case ^IR_Construct_Tag: return .I32
	case ^IR_Construct_Record: return .I32
	case ^IR_Closure: return .I32
	case ^IR_Resume: return e.type.wasm_type
	case ^IR_Atomic_Load: return e.type.wasm_type
	case ^IR_Atomic_RMW: return e.type.wasm_type
	case ^IR_Wait: return e.type.wasm_type
	case ^IR_Notify: return e.type.wasm_type
	case:
		return .I32
	}
	return .I32
}

ir_expr_wasm_type :: proc(expr: IR_Expr) -> IR_Wasm_Type {
	if expr == nil do return .I32
	#partial switch e in expr {
	case ^IR_Literal_Int: return e.type.wasm_type
	case ^IR_Literal_Float: return e.type.wasm_type
	case ^IR_Literal_Bool: return .I32
	case ^IR_Literal_String: return .I32
	case ^IR_Var: return e.type.wasm_type
	case ^IR_Let: return e.type.wasm_type
	case ^IR_Call: return e.type.wasm_type
	case ^IR_Tail_Call: return .Void
	case ^IR_If: return e.type.wasm_type
	case ^IR_Match: return e.type.wasm_type
	case ^IR_Construct_Tag: return .I32
	case ^IR_Construct_Record: return .I32
	case ^IR_Field_Access: return e.type.wasm_type
	case ^IR_BinOp: return e.type.wasm_type
	case ^IR_Closure: return .I32
	case ^IR_Closure_Call: return e.type.wasm_type
	case ^IR_Resume: return e.type.wasm_type
	case ^IR_Atomic_Load: return e.type.wasm_type
	case ^IR_Atomic_RMW: return e.type.wasm_type
	case ^IR_Atomic_Fence: return .Void
	case ^IR_Wait: return e.type.wasm_type
	case ^IR_Notify: return e.type.wasm_type
	case:
		return .I32
	}
	return .I32
}

emit_store_for_type :: proc(wasm_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch wasm_type {
	case .I64: emit_instruction(Wasm_I64_Store{align = 3, offset = 0}, buf)
	case .F64: emit_instruction(Wasm_F64_Store{align = 3, offset = 0}, buf)
	case: emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
	}
}

emit_load_for_type :: proc(wasm_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch wasm_type {
	case .I64: emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, buf)
	case .F64: emit_instruction(Wasm_F64_Load{align = 3, offset = 0}, buf)
	case: emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
	}
}

hash_string :: proc(s: string) -> int {
	h: int = 5381
	for i := 0; i < len(s); i += 1 {
		h = ((h << 5) + h) + int(s[i])
	}
	return h
}

resolve_call_idx :: proc(callee: Canonical_Name, env: ^Codegen_Env) -> int {
	if callee.module != NO_NAME {
		mangled := mangle_name(callee.module, callee.name, env.interner)
		if idx, ok := env.func_map[hash_string(mangled)]; ok {
			return idx
		}
	}
	if idx, ok := env.func_map[int(callee.name)]; ok {
		return idx
	}
	return 0
}

emit_atomic_load :: proc(width: Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	#partial switch width {
	case .B1:
		emit_instruction(Wasm_I32_Atomic_Load8U{align = 0, offset = offset}, buf)
	case .B2:
		emit_instruction(Wasm_I32_Atomic_Load16U{align = 1, offset = offset}, buf)
	case .B4:
		emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = offset}, buf)
	case .B8:
		emit_instruction(Wasm_I64_Atomic_Load{align = 3, offset = offset}, buf)
	}
}

emit_atomic_store :: proc(width: Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	#partial switch width {
	case .B1:
		emit_instruction(Wasm_I32_Atomic_Store8{align = 0, offset = offset}, buf)
	case .B2:
		emit_instruction(Wasm_I32_Atomic_Store16{align = 1, offset = offset}, buf)
	case .B4:
		emit_instruction(Wasm_I32_Atomic_Store{align = 2, offset = offset}, buf)
	case .B8:
		emit_instruction(Wasm_I64_Atomic_Store{align = 3, offset = offset}, buf)
	}
}

emit_atomic_rmw :: proc(op: Atomic_Op, width: Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Add:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_Add{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_Add{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_Add{align = 3, offset = offset}, buf)
		}
	case .Sub:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_Sub{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_Sub{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_Sub{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_Sub{align = 3, offset = offset}, buf)
		}
	case .And:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_And{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_And{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_And{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_And{align = 3, offset = offset}, buf)
		}
	case .Or:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_Or{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_Or{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_Or{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_Or{align = 3, offset = offset}, buf)
		}
	case .Xor:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_Xor{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_Xor{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_Xor{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_Xor{align = 3, offset = offset}, buf)
		}
	case .Xchg:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_Xchg{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_Xchg{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_Xchg{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_Xchg{align = 3, offset = offset}, buf)
		}
	case .CmpXchg:
		#partial switch width {
		case .B1: emit_instruction(Wasm_I32_Atomic_RMW8_CmpXchg{align = 0, offset = offset}, buf)
		case .B2: emit_instruction(Wasm_I32_Atomic_RMW16_CmpXchg{align = 1, offset = offset}, buf)
		case .B4: emit_instruction(Wasm_I32_Atomic_RMW_CmpXchg{align = 2, offset = offset}, buf)
		case .B8: emit_instruction(Wasm_I64_Atomic_RMW_CmpXchg{align = 3, offset = offset}, buf)
		}
	}
}

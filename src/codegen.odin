package camp

WASI_MODULE :: "wasi_snapshot_preview1"

CAMP_TAG_HEADER_SIZE :: 8
CAMP_TAG_REFCOUNT_OFFSET :: 0
CAMP_TAG_TAG_OFFSET :: 4
CAMP_TAG_SCAN_SIZE_OFFSET :: 5
CAMP_TAG_FIELDS_OFFSET :: 8

Codegen_Env :: struct {
	mod:            ^Wasm_Module,
	interner:       ^Intern_Table,
	type_map:       map[int]int,
	func_map:       map[int]int,
	next_type_idx:  int,
	next_func_idx:  int,
	import_count:   int,
	data_offset:    u32,
	locals:         [dynamic]Wasm_Local_Decl,
	local_map:      map[Intern_ID]u32,
	next_local:     u32,
	tmp_local_base: u32,
	tmp_count:      u32,
	table_idx:      int,
	func_type_indices: [dynamic]u32,
	next_scope_id:  int,
	async_id:       Intern_ID,
	spawn_id:       Intern_ID,
	parallel_id:    Intern_ID,
	file_id:        Intern_ID,
	console_id:     Intern_ID,
	time_id:        Intern_ID,
	decl_to_wasm_fn_idx: map[int]int,
}

cg_is_scheduler_effect :: proc(effect: Canonical_Name, env: ^Codegen_Env) -> bool {
	name := effect.name
	if name == env.async_id do return true
	if name == env.spawn_id do return true
	if name == env.parallel_id do return true
	if name == env.file_id do return true
	if name == env.console_id do return true
	if name == env.time_id do return true
	return false
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

	// WASI I/O imports for scheduler (Preview 1 style)
	// poll_oneoff(in, out, nsubs, nevents) -> errno
	poll_oneoff_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "poll_oneoff", .Func, poll_oneoff_type)

	// fd_read(fd, iovs, iovs_len, nread) -> errno
	fd_read_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "fd_read", .Func, fd_read_type)

	// fd_close(fd) -> errno
	fd_close_type := get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "fd_close", .Func, fd_close_type)

	// clock_time_get(clock_id, precision, time_ptr) -> errno
	clock_time_get_type := get_or_create_type(env, []Wasm_Value_Type{.I32, .I64, .I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "clock_time_get", .Func, clock_time_get_type)

	// sched_yield() -> errno
	sched_yield_type := get_or_create_type(env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "sched_yield", .Func, sched_yield_type)
}

// WASI import function indices (offset from import_count base)
WASI_IMPORT_POLL_ONEOFF   :: 5
WASI_IMPORT_FD_READ      :: 6
WASI_IMPORT_FD_CLOSE     :: 7
WASI_IMPORT_CLOCK_TIME_GET :: 8
WASI_IMPORT_SCHED_YIELD  :: 9

emit_runtime_types :: proc(env: ^Codegen_Env) {
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	get_or_create_type(env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
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
	env.next_scope_id = 1
	env.async_id = intern(&ctx.interner, "Async!")
	env.spawn_id = intern(&ctx.interner, "Spawn!")
	env.parallel_id = intern(&ctx.interner, "Parallel!")
	env.file_id = intern(&ctx.interner, "File!")
	env.console_id = intern(&ctx.interner, "Console!")
	env.time_id = intern(&ctx.interner, "Time!")

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
	dealloc_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})

	print_err_type_idx := print_str_type_idx
	list_alloc_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	list_push_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
	list_len_type_idx := alloc_type_idx
	list_get_type_idx := list_push_type_idx
	str_len_type_idx := alloc_type_idx
	str_eq_type_idx := list_push_type_idx

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
	dealloc_func_idx := add_function(&env, dealloc_type_idx)
	runtime_func_indices[5] = dealloc_func_idx

	print_err_func_idx := add_function(&env, print_err_type_idx)
	runtime_func_indices[6] = print_err_func_idx
	list_alloc_func_idx := add_function(&env, list_alloc_type_idx)
	runtime_func_indices[7] = list_alloc_func_idx
	list_push_func_idx := add_function(&env, list_push_type_idx)
	runtime_func_indices[8] = list_push_func_idx
	list_len_func_idx := add_function(&env, list_len_type_idx)
	runtime_func_indices[9] = list_len_func_idx
	list_get_func_idx := add_function(&env, list_get_type_idx)
	runtime_func_indices[10] = list_get_func_idx
	str_len_func_idx := add_function(&env, str_len_type_idx)
	runtime_func_indices[11] = str_len_func_idx
	str_eq_func_idx := add_function(&env, str_eq_type_idx)
	runtime_func_indices[12] = str_eq_func_idx

	async_init_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	async_enqueue_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
	async_dequeue_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	async_run_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})

	async_init_func_idx := add_function(&env, async_init_type_idx)
	runtime_func_indices[13] = async_init_func_idx
	async_enqueue_func_idx := add_function(&env, async_enqueue_type_idx)
	runtime_func_indices[14] = async_enqueue_func_idx
	async_dequeue_func_idx := add_function(&env, async_dequeue_type_idx)
	runtime_func_indices[15] = async_dequeue_func_idx
	async_run_func_idx := add_function(&env, async_run_type_idx)
	runtime_func_indices[16] = async_run_func_idx

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

	// Parallel! runtime function types
	// camp_parallel_map(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_map_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	// camp_parallel_reduce(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, init: i32, chunk_size: i32) -> i32
	parallel_reduce_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	// camp_parallel_any(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32) -> i32
	parallel_any_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	// camp_parallel_all(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_all_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	// camp_parallel_filter(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_filter_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	// camp_parallel_for_each(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> void
	parallel_for_each_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32}, []Wasm_Value_Type{})

	parallel_map_func_idx := add_function(&env, parallel_map_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_MAP] = parallel_map_func_idx
	parallel_reduce_func_idx := add_function(&env, parallel_reduce_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_REDUCE] = parallel_reduce_func_idx
	parallel_any_func_idx := add_function(&env, parallel_any_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_ANY] = parallel_any_func_idx
	parallel_all_func_idx := add_function(&env, parallel_all_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_ALL] = parallel_all_func_idx
	parallel_filter_func_idx := add_function(&env, parallel_filter_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_FILTER] = parallel_filter_func_idx
	parallel_for_each_func_idx := add_function(&env, parallel_for_each_type_idx)
	runtime_func_indices[RUNTIME_PARALLEL_FOR_EACH] = parallel_for_each_func_idx

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

	camp_dealloc_code := emit_camp_dealloc_body()
	append(&mod.codes, camp_dealloc_code)

	camp_print_err_code := emit_camp_print_err_body()
	append(&mod.codes, camp_print_err_code)

	camp_list_alloc_code := emit_camp_list_alloc_body()
	append(&mod.codes, camp_list_alloc_code)

	camp_list_push_code := emit_camp_list_push_body()
	append(&mod.codes, camp_list_push_code)

	camp_list_len_code := emit_camp_list_len_body()
	append(&mod.codes, camp_list_len_code)

	camp_list_get_code := emit_camp_list_get_body()
	append(&mod.codes, camp_list_get_code)

	camp_str_len_code := emit_camp_str_len_body()
	append(&mod.codes, camp_str_len_code)

	camp_str_eq_code := emit_camp_str_eq_body()
	append(&mod.codes, camp_str_eq_code)

	camp_async_init_code := emit_camp_async_init_body()
	append(&mod.codes, camp_async_init_code)

	camp_async_enqueue_code := emit_camp_async_enqueue_body()
	append(&mod.codes, camp_async_enqueue_code)

	camp_async_dequeue_code := emit_camp_async_dequeue_body()
	append(&mod.codes, camp_async_dequeue_code)

	camp_async_run_code := emit_camp_async_run_body()
	append(&mod.codes, camp_async_run_code)

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

	// Parallel! runtime function bodies
	append(&mod.codes, emit_camp_parallel_map_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_reduce_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_any_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_all_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_filter_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_for_each_body(runtime_func_indices))

	camp_alloc_name := intern(&ctx.interner, "camp_alloc")
	env.func_map[int(camp_alloc_name)] = alloc_func_idx
	camp_dealloc_name := intern(&ctx.interner, "camp_dealloc")
	env.func_map[int(camp_dealloc_name)] = dealloc_func_idx

	main_fn_idx := -1
	main_decl: ^IR_Decl_Fn = nil
	env.decl_to_wasm_fn_idx = make(map[int]int, len(ir_mod.decls))
	for decl, decl_idx in ir_mod.decls {
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
			env.decl_to_wasm_fn_idx[decl_idx] = func_idx

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

	cont_func_idx := -1
	main_ret_type := get_main_return_type(ir_mod, &ctx.interner)
	if main_fn_idx >= 0 && main_decl != nil && main_decl.is_effectful && len(main_decl.effects) > 0 {
		cont_ret_types := []Wasm_Value_Type{ir_wasm_type_to_value_type(main_ret_type)}
		cont_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I64}, cont_ret_types)
		cont_func_idx = add_function(&env, cont_type_idx)

		for len(env.func_type_indices) <= cont_func_idx {
			append(&env.func_type_indices, 0)
		}
		env.func_type_indices[cont_func_idx] = u32(cont_type_idx)
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

			if is_main && d.is_effectful {
				continue
			}
		case:
		}
	}

	worker_func_idx := -1
	if start_func_idx >= 0 {
		worker_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
		worker_func_idx = add_function(&env, worker_type_idx)
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
		env.next_local = 4

		code_buf: [dynamic]u8
		code_buf = make([dynamic]u8, 0, 256)

		if main_decl.is_effectful && len(main_decl.effects) > 0 {
			// Effectful main: _start allocates evidence records, calls main!, exits

			// Emit top-level continuation function body for CPS-transformed main!
			// The continuation takes (env: i32, result: i64) and calls camp_exit(result & 127)
			cont_body_buf: [dynamic]u8
			cont_body_buf = make([dynamic]u8, 0, 32)
			emit_instruction(Wasm_Local_Get{index = 1}, &cont_body_buf)  // result (i64)
			emit_instruction(Wasm_I32_Wrap_I64{}, &cont_body_buf)         // to i32
			emit_instruction(Wasm_I32_Const{value = 127}, &cont_body_buf)
			emit_instruction(Wasm_I32_And{}, &cont_body_buf)              // result & 127
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_EXIT])}, &cont_body_buf)
			emit_instruction(Wasm_Unreachable{}, &cont_body_buf)          // camp_exit doesn't return
			emit_instruction(Wasm_End{}, &cont_body_buf)

			cont_locals := make([]Wasm_Local_Decl, 0)
			append(&mod.codes, Wasm_Code{locals = cont_locals, body = copy_dynamic_bytes(cont_body_buf)})
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
				emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_ALLOC])}, &code_buf)
				emit_instruction(Wasm_Local_Set{index = u32(ev_local_idx)}, &code_buf)
			}

			// Populate evidence record slots with default handler closures for prelude effects
			for i in 0..<ev_param_count {
				eff := main_decl.effects[i]
				eff_name := intern_get(&ctx.interner, eff.name)
				ev_local_idx := ev_local_indices[i]

				if eff_name == "Console" {
					slot_offset := 0
					for eff_def in ir_mod.effect_defs {
						if eff_def.name == eff {
							for op_idx in 0..<len(eff_def.operations) {
								op_name := intern_get(&ctx.interner, eff_def.operations[op_idx].name)
								if op_name == "println!" {
									println_handler_idx := emit_console_println_handler_fn(&env, &mod, cont_func_idx)
									emit_handler_into_evidence(&code_buf, &env, ev_local_idx, slot_offset, println_handler_idx, runtime_func_indices[:])
								} else if op_name == "readln!" {
									readln_handler_idx := emit_console_readln_handler_fn(&env, &mod)
									emit_handler_into_evidence(&code_buf, &env, ev_local_idx, slot_offset, readln_handler_idx, runtime_func_indices[:])
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
								op_name := intern_get(&ctx.interner, eff_def.operations[op_idx].name)
								if op_name == "throw!" {
									throw_handler_idx := emit_throw_handler_fn(&env, &mod, runtime_func_indices[:])
									emit_handler_into_evidence(&code_buf, &env, ev_local_idx, slot_offset, throw_handler_idx, runtime_func_indices[:])
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
								handler_idx := emit_unhandled_effect_handler_fn(&env, &mod, eff_name, runtime_func_indices[:])
								emit_handler_into_evidence(&code_buf, &env, ev_local_idx, slot_offset, handler_idx, runtime_func_indices[:])
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
			main_fn_idx, ok := env.func_map[int(main_decl.name.name)]
			if !ok {
				mangled := mangle_name(main_decl.name.module, main_decl.name.name, env.interner)
				main_fn_idx = env.func_map[hash_string(mangled)]
			}

			// Allocate closure record for top-level continuation
			closure_local := env.next_local
			env.next_local += 1
			emit_instruction(Wasm_I32_Const{value = 24}, &code_buf)      // size = CAMP_TAG_HEADER_SIZE(8) + 2*8
			emit_instruction(Wasm_Call{index = u32(runtime_func_indices[RUNTIME_ALLOC])}, &code_buf)
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
			append(&mod.codes, Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)})
		} else {
			// Non-effectful main: inline the body
			main_body := extract_effectful_body(main_decl.body)

			env.local_map = make(map[Intern_ID]u32, 32)

			collected_locals: map[Intern_ID]IR_Type
			collected_locals = make(map[Intern_ID]IR_Type, 32)
			collect_locals(main_body, &collected_locals)
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

			emit_instruction(Wasm_Call{index = 0}, &code_buf)
			emit_instruction(Wasm_End{}, &code_buf)

			start_locals := make([dynamic]Wasm_Local_Decl, 0, 8)
			append(&start_locals, Wasm_Local_Decl{count = 4, type = .I32})
			for _, typ in collected_locals {
				append(&start_locals, Wasm_Local_Decl{count = 1, type = ir_wasm_type_to_value_type(typ.wasm_type)})
			}
			append(&mod.codes, Wasm_Code{locals = start_locals[:], body = copy_dynamic_bytes(code_buf)})
			delete(collected_locals)
			delete(env.local_map)
		}

		delete(code_buf)

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

	if worker_func_idx >= 0 {
		worker_buf: [dynamic]u8
		worker_buf = make([dynamic]u8, 0, 64)

		// Load env pointer from closure at CAMP_TAG_FIELDS_OFFSET + 8
		emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, &worker_buf)
		emit_instruction(Wasm_I32_Add{}, &worker_buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &worker_buf)

		// Load function index from closure at CAMP_TAG_FIELDS_OFFSET
		emit_instruction(Wasm_Local_Get{index = 0}, &worker_buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &worker_buf)

		// call_indirect with type (i32) -> (i32)
		worker_call_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
		emit_instruction(Wasm_Call_Indirect{type_idx = u32(worker_call_type_idx), table_idx = u32(env.table_idx)}, &worker_buf)

		emit_instruction(Wasm_End{}, &worker_buf)

		worker_locals := make([]Wasm_Local_Decl, 0)
		append(&mod.codes, Wasm_Code{locals = worker_locals, body = copy_dynamic_bytes(worker_buf)})
		delete(worker_buf)

		append(&mod.exports, Wasm_Export{name = "camp_worker_entry", kind = .Func, index = worker_func_idx})
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
	delete(env.decl_to_wasm_fn_idx)
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
		if e.type.wasm_type != .Void {
			locals^[e.binding] = e.type
		}
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
		if e.ev != nil {
			collect_locals(e.ev, locals)
		}
	case ^IR_I32_Load:
		collect_locals(e.base, locals)
	case ^IR_I32_Store:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^IR_Atomic_Load:
		collect_locals(e.base, locals)
	case ^IR_Atomic_Store:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^IR_Atomic_RMW:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^IR_Atomic_Fence:
	case ^IR_Wait:
		collect_locals(e.base, locals)
		collect_locals(e.expected, locals)
	case ^IR_Notify:
		collect_locals(e.base, locals)
		collect_locals(e.count, locals)
	case:
	}
}

RUNTIME_ALLOC :: 0
RUNTIME_DUP :: 1
RUNTIME_DROP :: 2
RUNTIME_PRINT_STR :: 3
RUNTIME_EXIT :: 4
RUNTIME_DEALLOC :: 5
RUNTIME_PRINT_ERR :: 6
RUNTIME_LIST_ALLOC :: 7
RUNTIME_LIST_PUSH :: 8
RUNTIME_LIST_LEN :: 9
RUNTIME_LIST_GET :: 10
RUNTIME_STR_LEN :: 11
RUNTIME_STR_EQ :: 12
RUNTIME_ASYNC_INIT :: 13
RUNTIME_ASYNC_ENQUEUE :: 14
RUNTIME_ASYNC_DEQUEUE :: 15
RUNTIME_ASYNC_RUN :: 16
RUNTIME_SCHED_INIT :: 17
RUNTIME_SCHED_SPAWN :: 18
RUNTIME_SCHED_JOIN :: 19
RUNTIME_SCHED_CANCEL :: 20
RUNTIME_SCHED_COMPLETE :: 21
RUNTIME_SCHED_YIELD :: 22
RUNTIME_SCHED_BLOCK_IO :: 23
RUNTIME_SCHED_TIMER_INSERT :: 24
RUNTIME_SCHED_TIMER_CANCEL :: 25
RUNTIME_SCHED_NOTIFY :: 26
RUNTIME_SCHED_PARK :: 27
RUNTIME_SCHED_WORKER_LOOP :: 28
RUNTIME_PARALLEL_MAP :: 29
RUNTIME_PARALLEL_REDUCE :: 30
RUNTIME_PARALLEL_ANY :: 31
RUNTIME_PARALLEL_ALL :: 32
RUNTIME_PARALLEL_FILTER :: 33
RUNTIME_PARALLEL_FOR_EACH :: 34
RUNTIME_FUNC_COUNT :: 35

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
		if e.type.wasm_type == .Void {
			// Void-typed let: value is for side effects only, no binding
		} else if idx, ok := env.local_map[e.binding]; ok {
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
		// Check if callee is a local variable (closure pointer) or a named function
		if local_idx, ok := env.local_map[e.callee.name]; ok {
			// Callee is a closure pointer in a local variable — use call_indirect
			emit_instruction(Wasm_Local_Get{index = local_idx}, buf)

			callee_local := env.tmp_local_base + 2
			emit_instruction(Wasm_Local_Set{index = callee_local}, buf)

			// Load env from closure record
			emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

			// Emit arguments after env
			for arg in e.args {
				emit_expr(arg, buf, env, runtime_indices)
			}

			// Load function index from closure record
			emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

			// Build closure call type: (env i32, args...) -> (result)
			// For tail calls to closures, the result type comes from the
			// continuation's return type, not from IR_Tail_Call (which is Void).
			// Infer it from the argument types: the continuation takes (env, result)
			// and returns the result type.
			closure_params := make([]Wasm_Value_Type, 1 + len(e.args))
			closure_params[0] = .I32
			for idx := 0; idx < len(e.args); idx += 1 {
				closure_params[idx + 1] = ir_wasm_type_to_value_type(ir_expr_wasm_type(e.args[idx]))
			}
			// The continuation returns the same type as its result parameter
			has_return := false
			return_value_type := Wasm_Value_Type(.I32)
			if len(e.args) > 0 {
				last_arg_type := ir_expr_wasm_type(e.args[len(e.args) - 1])
				if last_arg_type != .Void {
					has_return = true
					return_value_type = ir_wasm_type_to_value_type(last_arg_type)
				}
			}
			closure_results: []Wasm_Value_Type
			if has_return {
				closure_results = make([]Wasm_Value_Type, 1)
				closure_results[0] = return_value_type
			}
			closure_type_idx := get_or_create_type(env, closure_params, closure_results)
			delete(closure_params)
			if len(closure_results) > 0 {
				delete(closure_results)
			}

			emit_instruction(Wasm_Call_Indirect{type_idx = u32(closure_type_idx), table_idx = u32(env.table_idx)}, buf)

			// IR_Tail_Call is in a void-returning context (effectful function),
			// but call_indirect may return a value — drop it
			if has_return {
				emit_instruction(Wasm_Drop{}, buf)
			}
		} else {
			// Callee is a named function — use return_call
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
		}
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

		// Pre-compute interned "fn_idx" name for decl-to-wasm translation
		fn_idx_name := env.interner != nil ? intern(env.interner, "fn_idx") : 0
		for i in 0..<len(e.fields) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)

			// Translate "fn_idx" field from decls index to WASM function index
			if e.fields[i].name == fn_idx_name {
				if lit, ok := e.fields[i].value.(^IR_Literal_Int); ok {
					if wasm_idx, found := env.decl_to_wasm_fn_idx[int(lit.value)]; found {
						emit_instruction(Wasm_I32_Const{value = i32(wasm_idx)}, buf)
						emit_store_for_type(ir_expr_wasm_type(e.fields[i].value), buf)
						continue
					}
				}
			}
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
		if cg_is_scheduler_effect(e.effect, env) {
			// Allocate scope_id for structured concurrency cleanup
			scope_id := env.next_scope_id
			env.next_scope_id += 1

			// Emit body — IR_Perform nodes inside will call scheduler functions
			emit_expr(e.body, buf, env, runtime_indices)

			// On handler exit: iterate handle table, cancel all Pending handles with this scope_id
			// This implements structured concurrency (D10 Phase 1)
			handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
			// local for loop counter
			scope_local := env.tmp_local_base + env.tmp_count
			env.tmp_count += 1
			entry_addr_local := scope_local + 1
			env.tmp_count += 1

			// Loop over handle table entries
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
			emit_instruction(Wasm_Local_Set{index = scope_local}, buf)

			emit_instruction(Wasm_Block{block_type = .Void}, buf)
			emit_instruction(Wasm_Loop{block_type = .Void}, buf)

			// Check if counter < SCHED_MAX_HANDLES
			emit_instruction(Wasm_Local_Get{index = scope_local}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(SCHED_MAX_HANDLES)}, buf)
			emit_instruction(Wasm_I32_Ge_S{}, buf)
			emit_instruction(Wasm_Br_If{label = 1}, buf) // break

			// Compute entry address
			emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, buf)
			emit_instruction(Wasm_Local_Get{index = scope_local}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, buf)
			emit_instruction(Wasm_I32_Mul{}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_instruction(Wasm_Local_Set{index = entry_addr_local}, buf)

			// Check scope_id matches
			emit_instruction(Wasm_Local_Get{index = entry_addr_local}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = 20}, buf) // scope_id at offset 20
			emit_instruction(Wasm_I32_Const{value = i32(scope_id)}, buf)
			emit_instruction(Wasm_I32_Ne{}, buf)
			emit_instruction(Wasm_Br_If{label = 0}, buf) // continue (skip, wrong scope)

			// Check status == Pending
			emit_instruction(Wasm_Local_Get{index = entry_addr_local}, buf)
			emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, buf)
			emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_PENDING}, buf)
			emit_instruction(Wasm_I32_Ne{}, buf)
			emit_instruction(Wasm_Br_If{label = 0}, buf) // continue (skip, not pending)

			// Set status = Cancelled
			emit_instruction(Wasm_Local_Get{index = entry_addr_local}, buf)
			emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, buf)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

			// Increment counter, loop
			emit_instruction(Wasm_Local_Get{index = scope_local}, buf)
			emit_instruction(Wasm_I32_Const{value = 1}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_instruction(Wasm_Local_Set{index = scope_local}, buf)
			emit_instruction(Wasm_Br{label = 0}, buf) // continue loop

			emit_instruction(Wasm_End{}, buf) // end loop
			emit_instruction(Wasm_End{}, buf) // end block
		} else {
			emit_instruction(Wasm_Unreachable{}, buf)
		}
	case ^IR_Perform:
		if cg_is_scheduler_effect(e.effect, env) {
			effect_str := intern_get(env.interner, e.effect.name)
			op_str := intern_get(env.interner, e.op)

			if effect_str == "Async!" || effect_str == "Spawn!" {
				// Async!/Spawn! operations map to scheduler runtime functions
				if op_str == "spawn!" {
					// Args: thunk (closure ptr), scope_id
					// camp_sched_spawn(fn_index, env_ptr, scope_id) -> handle_id
					if len(e.args) >= 1 {
						// The thunk is a closure: extract fn_index and env_ptr
						thunk_local := env.tmp_local_base + env.tmp_count
						env.tmp_count += 1
						emit_expr(e.args[0], buf, env, runtime_indices)
						emit_instruction(Wasm_Local_Set{index = thunk_local}, buf)

						// fn_index = closure[CAMP_TAG_FIELDS_OFFSET]
						emit_instruction(Wasm_Local_Get{index = thunk_local}, buf)
						emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

						// env_ptr = closure[CAMP_TAG_FIELDS_OFFSET + 8]
						emit_instruction(Wasm_Local_Get{index = thunk_local}, buf)
						emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

						// scope_id from enclosing handler (use 0 as default if no scope tracking)
						emit_instruction(Wasm_I32_Const{value = 0}, buf)

						emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_SPAWN])}, buf)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
				} else if op_str == "join!" {
					// camp_sched_join(handle_id) -> result_value
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_JOIN])}, buf)
				} else if op_str == "yield!" {
					// camp_sched_yield() -> void
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_YIELD])}, buf)
				} else if op_str == "cancel!" {
					// camp_sched_cancel(handle_id) -> void
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_CANCEL])}, buf)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else if effect_str == "Time!" {
				if op_str == "sleep!" {
					// camp_sched_timer_insert(ms, task_ptr) -> void
					// For now, simplified: just call timer_insert with the duration
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					// task_ptr placeholder (would need current task context)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_TIMER_INSERT])}, buf)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else if effect_str == "File!" || effect_str == "Console!" {
				// I/O effects use camp_sched_block_io for suspension
				// Full implementation deferred to I/O bridge (Group 6)
				if op_str == "read!" || op_str == "readln!" {
					// Simplified: call block_io with placeholder pollable
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(Wasm_I32_Const{value = 0}, buf) // task_ptr placeholder
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_SCHED_BLOCK_IO])}, buf)
				} else if op_str == "write!" {
					if len(e.args) >= 2 {
						emit_expr(e.args[0], buf, env, runtime_indices)
						emit_expr(e.args[1], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					// Use fd_write for actual write, then block_io if needed
					emit_instruction(Wasm_Call{index = u32(1)}, buf) // fd_write import
					emit_instruction(Wasm_Drop{}, buf)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else if effect_str == "Parallel!" {
				// Parallel! operations delegate to runtime functions
				if op_str == "map!" && len(e.args) >= 2 {
					// map!(fn, items) -> camp_parallel_map(fn_idx, fn_env, items_ptr, items_len, chunk_size)
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_MAP])}, buf)
				} else if op_str == "reduce!" && len(e.args) >= 3 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_expr(e.args[2], buf, env, runtime_indices)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_REDUCE])}, buf)
				} else if op_str == "any!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_ANY])}, buf)
				} else if op_str == "all!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_ALL])}, buf)
				} else if op_str == "filter!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_FILTER])}, buf)
				} else if op_str == "for_each!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_PARALLEL_FOR_EACH])}, buf)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else {
				emit_instruction(Wasm_Unreachable{}, buf)
			}
		} else {
			emit_instruction(Wasm_Unreachable{}, buf)
		}
	case ^IR_Resume:
		resume_local := env.tmp_local_base + 3
		fn_idx_local := env.tmp_local_base + 2

		if idx, ok := env.local_map[e.resume_id]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
		emit_instruction(Wasm_Local_Set{index = resume_local}, buf)

		// Load fn_idx once into a tmp local for both null check and call
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_Local_Tee{index = fn_idx_local}, buf)

		// One-shot check: fn_idx == 0 means already resumed
		emit_instruction(Wasm_I32_Const{value = 0}, buf)
		emit_instruction(Wasm_I32_Eq{}, buf)
		emit_instruction(Wasm_If{block_type = .Void}, buf)
		emit_instruction(Wasm_Unreachable{}, buf)
		emit_instruction(Wasm_End{}, buf)

		// Zero fn_idx to enforce one-shot
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Const{value = 0}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

		// Load env pointer
		emit_instruction(Wasm_Local_Get{index = resume_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

		// Emit value FIRST, then ev (matching continuation function param order: env, value, ev)
		emit_expr(e.value, buf, env, runtime_indices)

		if e.ev != nil {
			emit_expr(e.ev, buf, env, runtime_indices)
		}

		// Use saved fn_idx for the call
		emit_instruction(Wasm_Local_Get{index = fn_idx_local}, buf)

		resume_params := make([dynamic]Wasm_Value_Type, 0, 4)
		append(&resume_params, Wasm_Value_Type.I32)
		append(&resume_params, ir_wasm_type_to_value_type(e.type.wasm_type))
		if e.ev != nil {
			append(&resume_params, Wasm_Value_Type.I32)
		}
		resume_results := make([dynamic]Wasm_Value_Type, 0, 1)
		append(&resume_results, ir_wasm_type_to_value_type(e.type.wasm_type))
		resume_type_idx := get_or_create_type(env, resume_params[:], resume_results[:])
		delete(resume_params)
		delete(resume_results)

		emit_instruction(Wasm_Call_Indirect{type_idx = u32(resume_type_idx), table_idx = u32(env.table_idx)}, buf)
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
	case ^IR_I32_Load:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(e.offset)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
	case ^IR_I32_Store:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(e.offset)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
	case ^IR_Atomic_Load:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_atomic_load(e.width, u32(e.offset), buf)
	case ^IR_Atomic_Store:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_store(e.width, u32(e.offset), buf)
	case ^IR_Atomic_RMW:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_rmw(e.op, e.width, u32(e.offset), buf)
	case ^IR_Atomic_Fence:
		emit_instruction(Wasm_Atomic_Fence{}, buf)
	case ^IR_Wait:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.expected, buf, env, runtime_indices)
		emit_expr(e.timeout, buf, env, runtime_indices)
		if e.width == .B8 {
			emit_instruction(Wasm_Memory_Atomic_Wait64{align = 3, offset = u32(e.offset)}, buf)
		} else {
			emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = u32(e.offset)}, buf)
		}
	case ^IR_Notify:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.count, buf, env, runtime_indices)
		emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = u32(e.offset)}, buf)
	case:
		emit_instruction(Wasm_Unreachable{}, buf)
	}
}

emit_binop :: proc(op: IR_BinOp_Kind, operand_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Add:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Add{}, buf)
		} else {
			emit_instruction(Wasm_I64_Add{}, buf)
		}
	case .Sub:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Sub{}, buf)
		} else {
			emit_instruction(Wasm_I64_Sub{}, buf)
		}
	case .Mul:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Mul{}, buf)
		} else {
			emit_instruction(Wasm_I64_Mul{}, buf)
		}
	case .Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Eq{}, buf)
		} else {
			emit_instruction(Wasm_I32_Eq{}, buf)
		}
	case .Ne:
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
	case .Le:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Le_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Le_S{}, buf)
		}
	case .Ge:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ge_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ge_S{}, buf)
		}
	case .And:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_And{}, buf)
		} else {
			emit_instruction(Wasm_I32_And{}, buf)
		}
	case .Or:
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
	case ^IR_Resume: return e.type.wasm_type
	case ^IR_Field_Access: return e.type.wasm_type
	case ^IR_Construct_Tag: return .I32
	case ^IR_Construct_Record: return .I32
	case ^IR_Closure: return .I32
	case ^IR_Atomic_Load: return .I32
	case ^IR_Atomic_RMW: return .I32
	case ^IR_Wait: return .I32
	case ^IR_Notify: return .I32
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
	case ^IR_Atomic_Load: return .I32
	case ^IR_Atomic_RMW: return .I32
	case ^IR_Atomic_Fence: return .Void
	case ^IR_Wait: return .I32
	case ^IR_Notify: return .I32
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

emit_handler_into_evidence :: proc(buf: ^[dynamic]u8, env: ^Codegen_Env, ev_local_idx: int, slot_offset: int, fn_idx: int, runtime_indices: []int) {
	// Save the evidence record pointer first
	emit_instruction(Wasm_Local_Get{index = u32(ev_local_idx)}, buf)

	// Allocate closure: size = CAMP_TAG_HEADER_SIZE(8) + 2*8 = 24
	emit_instruction(Wasm_I32_Const{value = 24}, buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

	tmp := env.tmp_local_base + 3
	emit_instruction(Wasm_Local_Tee{index = u32(tmp)}, buf)

	// Set refcount = 1
	emit_instruction(Wasm_I32_Const{value = 1}, buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

	// Set tag = closure tag (0xFE)
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0xFE}, buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

	// Set scan_size = 2 fields
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf)
	emit_instruction(Wasm_I32_Const{value = 2}, buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

	// Store function index
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
	emit_instruction(Wasm_I32_Add{}, buf)
	emit_instruction(Wasm_I32_Const{value = i32(fn_idx)}, buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

	// Store env = null
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
	emit_instruction(Wasm_I32_Add{}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

	// Store closure pointer into evidence record at slot_offset
	// Stack: [ev_ptr], closure_ptr is saved in local tmp
	emit_instruction(Wasm_I32_Const{value = i32(slot_offset)}, buf)
	emit_instruction(Wasm_I32_Add{}, buf)                   // address = ev_ptr + slot_offset
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf) // value = closure_ptr
	emit_store_for_type(.I32, buf)                           // store closure_ptr at [ev_ptr + slot_offset]
}

emit_throw_handler_fn :: proc(env: ^Codegen_Env, mod: ^Wasm_Module, runtime_indices: []int) -> int {
	// Handler type: (i32=env, i32=err_arg, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I64})
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	// Call camp_exit(1)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_EXIT])}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	append(&mod.codes, Wasm_Code{locals = locals, body = copy_dynamic_bytes(buf)})
	delete(buf)

	return handler_fn_idx
}

emit_console_println_handler_fn :: proc(env: ^Codegen_Env, mod: ^Wasm_Module, cont_fn_idx: int) -> int {
	// Handler type: (i32=env, i32=str_arg, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I64})
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	// Ignore the string arg for now — call continuation with Unit
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)  // env = null
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)  // result = Unit
	emit_instruction(Wasm_Call{index = u32(cont_fn_idx)}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)           // continuation never returns
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	append(&mod.codes, Wasm_Code{locals = locals, body = copy_dynamic_bytes(buf)})
	delete(buf)

	return handler_fn_idx
}

emit_console_readln_handler_fn :: proc(env: ^Codegen_Env, mod: ^Wasm_Module) -> int {
	// Handler type: (i32=env, i32=resume, i32=ev) -> i32 (Str)
	handler_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32}, []Wasm_Value_Type{.I32})
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)

	// readln! not supported — unreachable
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	append(&mod.codes, Wasm_Code{locals = locals, body = copy_dynamic_bytes(buf)})
	delete(buf)

	return handler_fn_idx
}

emit_unhandled_effect_handler_fn :: proc(env: ^Codegen_Env, mod: ^Wasm_Module, eff_name: string, runtime_indices: []int) -> int {
	// Generic handler for unhandled effects: exit(1)
	// Handler type: (i32=env, i32..=op_args, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(env, []Wasm_Value_Type{.I32, .I32, .I32, .I32}, []Wasm_Value_Type{.I64})
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	// Call camp_exit(1) — unhandled effect
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_EXIT])}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	append(&mod.codes, Wasm_Code{locals = locals, body = copy_dynamic_bytes(buf)})
	delete(buf)

	return handler_fn_idx
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

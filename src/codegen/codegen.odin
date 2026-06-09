package codegen

import "camp:base"
import "camp:ir"

WASI_MODULE :: "wasi_snapshot_preview1"

CAMP_TAG_HEADER_SIZE :: 8
CAMP_TAG_REFCOUNT_OFFSET :: 0
CAMP_TAG_TAG_OFFSET :: 4
CAMP_TAG_SCAN_SIZE_OFFSET :: 5
// Bit i set => payload field i is a scalar (inline i64/f64), not a heap pointer, so
// camp_drop must not recurse into it. Defaults to 0 (all fields treated as heap
// pointers) so runtime-constructed cells, which store only pointers, need no change.
// 8 bits cover the first 8 fields; scalars beyond field 7 fall back to legacy scanning.
CAMP_TAG_SCALAR_MASK_OFFSET :: 6
CAMP_TAG_FIELDS_OFFSET :: 8
MAP_HEADER_TAG :: 0x10
MAP_NODE_TAG :: 0x11
MAP_HEADER_SIZE :: 16
MAP_NODE_SIZE :: 24
MAP_HEADER_ROOT_OFFSET :: 8
MAP_HEADER_SIZE_FIELD_OFFSET :: 12
MAP_NODE_KEY_OFFSET :: 8
MAP_NODE_VALUE_OFFSET :: 12
MAP_NODE_NEXT_OFFSET :: 16

CAMP_EXIT_MASK :: 127

CODE_BUF_SMALL :: 8
CODE_BUF_TINY :: 16
CODE_BUF_MINOR :: 32
CODE_BUF_DEFAULT :: 64
CODE_BUF_MEDIUM :: 96
CODE_BUF_MODERATE :: 128
CODE_BUF_LARGE :: 192
CODE_BUF_MAJOR :: 256
CODE_BUF_XL :: 512
CODE_BUF_XXL :: 1024
CODE_BUF_SECTION :: 4096

Match_Kind :: enum {
	Tag_Union,
	Bool,
	Int,
	String,
	Record,
}

determine_match_kind :: proc(arms: []ir.IR_Match_Arm, scrutinee: ir.IR_Expr) -> Match_Kind {
	for arm in arms {
		#partial switch p in arm.pattern {
		case ^ir.IR_Pat_Tag:
			return .Tag_Union
		case ^ir.IR_Pat_Bool:
			return .Bool
		case ^ir.IR_Pat_Int:
			return .Int
		case ^ir.IR_Pat_String:
			return .String
		case ^ir.IR_Pat_Record:
			return .Record
		case ^ir.IR_Pat_Var, ^ir.IR_Pat_Wildcard:
		}
	}
	// All arms are catch-alls (var/wildcard). Pick a kind based on the
	// scrutinee's wasm type so the dispatch path matches the value layout.
	#partial switch ir.ir_expr_wasm_type(scrutinee) {
	case .I64:
		return .Int
	case .I32:
		return .Bool
	}
	return .Tag_Union
}

Const_Global_Info :: struct {
	global_idx: u32,
	wasm_type:  base.IR_Wasm_Type,
}

Codegen_Env :: struct {
	mod:                     ^Wasm_Module,
	interner:                ^base.Intern_Table,
	type_map:                map[int]int,
	func_map:                map[u64]int,
	next_type_idx:           int,
	next_func_idx:           int,
	import_count:            int,
	data_offset:             u32,
	locals:                  [dynamic]Wasm_Local_Decl,
	local_map:               map[base.Intern_ID]u32,
	local_types:             map[base.Intern_ID]base.IR_Type,
	next_local:              u32,
	tmp_local_base:          u32,
	tmp_count:               u32,
	table_idx:               int,
	func_type_indices:       [dynamic]u32,
	next_scope_id:           int,
	async_id:                base.Intern_ID,
	spawn_id:                base.Intern_ID,
	parallel_id:             base.Intern_ID,
	file_id:                 base.Intern_ID,
	console_id:              base.Intern_ID,
	time_id:                 base.Intern_ID,
	decl_to_wasm_fn_idx:     map[int]int,
	const_globals:           map[base.Intern_ID]Const_Global_Info,
	string_offsets:          map[base.Intern_ID]u32,
	throw_err_msg_offset:    u32,
	throw_err_suffix_offset: u32,
	unit_value_offset:       u32,
	release_mode:            bool,
	i64_trampoline_cache:    map[int]int,
	debug_str_offsets:       map[string]u32,
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

get_or_create_type :: proc(
	env: ^Codegen_Env,
	params: []Wasm_Value_Type,
	results: []Wasm_Value_Type,
) -> int {
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

add_import :: proc(
	env: ^Codegen_Env,
	module: string,
	field: string,
	kind: Wasm_External_Kind,
	type_idx: int,
) -> int {
	idx := env.next_func_idx
	env.next_func_idx += 1
	env.import_count += 1
	append(
		&env.mod.imports,
		Wasm_Import{module = module, field = field, kind = kind, index = type_idx},
	)
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

	fd_write_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "fd_write", .Func, fd_write_type)

	args_get_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "args_get", .Func, args_get_type)

	args_sizes_get_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "args_sizes_get", .Func, args_sizes_get_type)

	// WASI I/O imports for scheduler (Preview 1 style)
	// poll_oneoff(in, out, nsubs, nevents) -> errno
	poll_oneoff_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "poll_oneoff", .Func, poll_oneoff_type)

	// fd_read(fd, iovs, iovs_len, nread) -> errno
	fd_read_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "fd_read", .Func, fd_read_type)

	// fd_close(fd) -> errno
	fd_close_type := get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "fd_close", .Func, fd_close_type)

	// clock_time_get(clock_id, precision, time_ptr) -> errno
	clock_time_get_type := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I64, .I32},
		[]Wasm_Value_Type{.I32},
	)
	add_import(env, WASI_MODULE, "clock_time_get", .Func, clock_time_get_type)

	// sched_yield() -> errno
	sched_yield_type := get_or_create_type(env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	add_import(env, WASI_MODULE, "sched_yield", .Func, sched_yield_type)
}

// WASI import function indices (offset from import_count base)
WASI_IMPORT_POLL_ONEOFF :: 4
WASI_IMPORT_FD_READ :: 5
WASI_IMPORT_FD_CLOSE :: 6
WASI_IMPORT_CLOCK_TIME_GET :: 7
WASI_IMPORT_SCHED_YIELD :: 8

emit_runtime_types :: proc(env: ^Codegen_Env) {
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	get_or_create_type(env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	get_or_create_type(env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{.I32})
}

codegen :: proc(
	ir_mod: ir.IR_Module,
	interner: ^base.Intern_Table,
	thread_count: int,
	release_mode: bool = false,
) -> Wasm_Module {
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
	env.interner = interner
	env.type_map = make(map[int]int, 64)
	env.func_map = make(map[u64]int, 64)
	env.next_type_idx = 0
	env.next_func_idx = 0
	env.import_count = 0
	env.data_offset = 0
	env.locals = make([dynamic]Wasm_Local_Decl, 0, 32)
	env.local_map = make(map[base.Intern_ID]u32, 32)
	env.local_types = make(map[base.Intern_ID]base.IR_Type, 32)
	env.string_offsets = make(map[base.Intern_ID]u32, 16)
	env.const_globals = make(map[base.Intern_ID]Const_Global_Info, 8)
	env.table_idx = -1
	env.func_type_indices = make([dynamic]u32, 0, 64)
	env.next_scope_id = 1
	env.async_id = base.intern(interner, "Async!")
	env.spawn_id = base.intern(interner, "Spawn!")
	env.parallel_id = base.intern(interner, "Parallel!")
	env.file_id = base.intern(interner, "File!")
	env.console_id = base.intern(interner, "Console!")
	env.time_id = base.intern(interner, "Time!")
	env.release_mode = release_mode

	emit_wasi_imports(&env)
	emit_runtime_types(&env)

	// Memory: shared when multi-threaded — runtime uses atomic instructions for Perceus RC
	append(
		&mod.memories,
		Wasm_Memory{min = 20, max = 256, has_max = true, shared = thread_count > 1},
	)

	env.table_idx = len(mod.tables)
	append(&mod.tables, Wasm_Table{elem_type = .Funcref, min = 1, max = 1, has_max = true})
	for entry in ir_mod.string_table {
		offset := env.data_offset
		env.string_offsets[entry.id] = offset
		// Runtime strings are length-prefixed: [i32 len][utf8 bytes].
		env.data_offset += u32(4 + len(entry.value))
	}

	// Error message for camp_report_drop_overflow — stored after string data
	drop_overflow_msg := "camp_drop: recursion overflow\n"
	drop_overflow_msg_offset := env.data_offset
	env.data_offset += u32(len(drop_overflow_msg))

	// Error message for default Throw handler
	throw_err_msg := "Error: unhandled exception (tag="
	throw_err_msg_offset := env.data_offset
	env.data_offset += u32(len(throw_err_msg))
	env.throw_err_msg_offset = throw_err_msg_offset

	throw_err_suffix := ")\n"
	throw_err_suffix_offset := env.data_offset
	env.data_offset += u32(len(throw_err_suffix))
	env.throw_err_suffix_offset = throw_err_suffix_offset

	unit_value_offset := env.data_offset
	env.data_offset += 8
	env.unit_value_offset = unit_value_offset

	// Debug string constants for container debug functions (length-prefixed)
	debug_strs := [][2]string {
		{"[", "["},
		{"]", "]"},
		{", ", ", "},
		{"(", "("},
		{"Ok(", "Ok("},
		{"Err(", "Err("},
		{"Map{", "Map{"},
		{"}", "}"},
		{": ", ": "},
		{"Set{", "Set{"},
	}
	debug_str_offsets: map[string]u32
	debug_str_offsets = make(map[string]u32, len(debug_strs))
	for ds in debug_strs {
		offset := env.data_offset
		env.data_offset += u32(4 + len(ds[1])) // len prefix + utf8 bytes
		debug_str_offsets[ds[0]] = offset
	}
	env.debug_str_offsets = debug_str_offsets

	heap_ptr_global_idx := len(mod.globals)
	heap_ptr_init: [dynamic]u8
	heap_ptr_init = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(Wasm_I32_Const{value = i32(env.data_offset)}, &heap_ptr_init)
	append(
		&mod.globals,
		Wasm_Global{type = .I32, mutable = true, init = copy_dynamic_bytes(heap_ptr_init)},
	)
	delete(heap_ptr_init)

	alloc_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	dup_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	drop_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32, .I32}, []Wasm_Value_Type{})
	print_str_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{},
	)
	exit_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	dealloc_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{},
	)

	print_err_type_idx := print_str_type_idx
	list_alloc_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	list_push_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	list_len_type_idx := alloc_type_idx
	list_get_type_idx := list_push_type_idx
	list_grow_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{.I32},
	)
	str_len_type_idx := alloc_type_idx
	str_eq_type_idx := list_push_type_idx
	str_concat_type_idx := list_push_type_idx
	str_slice_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	i64_to_str_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I64},
		[]Wasm_Value_Type{.I32},
	)
	i32_to_str_type_idx := alloc_type_idx
	f64_to_str_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.F64},
		[]Wasm_Value_Type{.I32},
	)
	bool_to_str_type_idx := alloc_type_idx
	report_drop_overflow_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{},
	)

	runtime_func_indices: [RUNTIME_FUNC_COUNT]int
	alloc_func_idx := add_function(&env, alloc_type_idx)
	runtime_func_indices[Runtime_Func.Alloc] = alloc_func_idx
	dup_func_idx := add_function(&env, dup_type_idx)
	runtime_func_indices[Runtime_Func.Dup] = dup_func_idx
	drop_func_idx := add_function(&env, drop_type_idx)
	runtime_func_indices[Runtime_Func.Drop] = drop_func_idx
	print_str_func_idx := add_function(&env, print_str_type_idx)
	runtime_func_indices[Runtime_Func.Print_Str] = print_str_func_idx
	exit_func_idx := add_function(&env, exit_type_idx)
	runtime_func_indices[Runtime_Func.Exit] = exit_func_idx
	dealloc_func_idx := add_function(&env, dealloc_type_idx)
	runtime_func_indices[Runtime_Func.Dealloc] = dealloc_func_idx

	print_err_func_idx := add_function(&env, print_err_type_idx)
	runtime_func_indices[Runtime_Func.Print_Err] = print_err_func_idx
	list_alloc_func_idx := add_function(&env, list_alloc_type_idx)
	runtime_func_indices[Runtime_Func.List_Alloc] = list_alloc_func_idx
	list_push_func_idx := add_function(&env, list_push_type_idx)
	runtime_func_indices[Runtime_Func.List_Push] = list_push_func_idx
	list_len_func_idx := add_function(&env, list_len_type_idx)
	runtime_func_indices[Runtime_Func.List_Len] = list_len_func_idx
	list_get_func_idx := add_function(&env, list_get_type_idx)
	runtime_func_indices[Runtime_Func.List_Get] = list_get_func_idx
	list_grow_func_idx := add_function(&env, list_grow_type_idx)
	runtime_func_indices[Runtime_Func.List_Grow] = list_grow_func_idx
	str_len_func_idx := add_function(&env, str_len_type_idx)
	runtime_func_indices[Runtime_Func.Str_Len] = str_len_func_idx
	str_eq_func_idx := add_function(&env, str_eq_type_idx)
	runtime_func_indices[Runtime_Func.Str_Eq] = str_eq_func_idx
	str_concat_func_idx := add_function(&env, str_concat_type_idx)
	runtime_func_indices[Runtime_Func.Str_Concat] = str_concat_func_idx
	str_slice_func_idx := add_function(&env, str_slice_type_idx)
	runtime_func_indices[Runtime_Func.Str_Slice] = str_slice_func_idx
	i64_to_str_func_idx := add_function(&env, i64_to_str_type_idx)
	runtime_func_indices[Runtime_Func.I64_To_Str] = i64_to_str_func_idx
	i32_to_str_func_idx := add_function(&env, i32_to_str_type_idx)
	runtime_func_indices[Runtime_Func.I32_To_Str] = i32_to_str_func_idx
	f64_to_str_func_idx := add_function(&env, f64_to_str_type_idx)
	runtime_func_indices[Runtime_Func.F64_To_Str] = f64_to_str_func_idx
	bool_to_str_func_idx := add_function(&env, bool_to_str_type_idx)
	runtime_func_indices[Runtime_Func.Bool_To_Str] = bool_to_str_func_idx

	report_drop_overflow_func_idx := add_function(&env, report_drop_overflow_type_idx)
	runtime_func_indices[Runtime_Func.Report_Drop_Overflow] = report_drop_overflow_func_idx


	// Scheduler runtime function types
	sched_init_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	sched_spawn_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	sched_join_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{.I32},
	)
	sched_cancel_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{})
	sched_complete_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{},
	)
	sched_yield_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_block_io_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{},
	)
	sched_timer_insert_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{},
	)
	sched_timer_cancel_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{},
	)
	sched_notify_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_park_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_worker_loop_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{},
	)

	sched_init_func_idx := add_function(&env, sched_init_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Init] = sched_init_func_idx
	sched_spawn_func_idx := add_function(&env, sched_spawn_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Spawn] = sched_spawn_func_idx
	sched_join_func_idx := add_function(&env, sched_join_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Join] = sched_join_func_idx
	sched_cancel_func_idx := add_function(&env, sched_cancel_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Cancel] = sched_cancel_func_idx
	sched_complete_func_idx := add_function(&env, sched_complete_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Complete] = sched_complete_func_idx
	sched_yield_func_idx := add_function(&env, sched_yield_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Yield] = sched_yield_func_idx
	sched_block_io_func_idx := add_function(&env, sched_block_io_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Block_IO] = sched_block_io_func_idx
	sched_timer_insert_func_idx := add_function(&env, sched_timer_insert_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Timer_Insert] = sched_timer_insert_func_idx
	sched_timer_cancel_func_idx := add_function(&env, sched_timer_cancel_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Timer_Cancel] = sched_timer_cancel_func_idx
	sched_notify_func_idx := add_function(&env, sched_notify_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Notify] = sched_notify_func_idx
	sched_park_func_idx := add_function(&env, sched_park_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Park] = sched_park_func_idx
	sched_worker_loop_func_idx := add_function(&env, sched_worker_loop_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Worker_Loop] = sched_worker_loop_func_idx
	sched_current_task_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{},
		[]Wasm_Value_Type{.I32},
	)
	sched_run_single_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_poll_and_dispatch_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{},
		[]Wasm_Value_Type{},
	)
	sched_timer_tick_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
	sched_timer_process_expired_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{},
		[]Wasm_Value_Type{},
	)

	sched_current_task_func_idx := add_function(&env, sched_current_task_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Current_Task] = sched_current_task_func_idx
	sched_run_single_func_idx := add_function(&env, sched_run_single_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Run_Single] = sched_run_single_func_idx
	sched_poll_and_dispatch_func_idx := add_function(&env, sched_poll_and_dispatch_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Poll_And_Dispatch] = sched_poll_and_dispatch_func_idx
	sched_timer_tick_func_idx := add_function(&env, sched_timer_tick_type_idx)
	runtime_func_indices[Runtime_Func.Sched_Timer_Tick] = sched_timer_tick_func_idx
	sched_timer_process_expired_func_idx := add_function(
		&env,
		sched_timer_process_expired_type_idx,
	)
	runtime_func_indices[Runtime_Func.Sched_Timer_Process_Expired] =
		sched_timer_process_expired_func_idx

	// Parallel! runtime function types
	// camp_parallel_map(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_map_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	// camp_parallel_reduce(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, init: i32, chunk_size: i32) -> i32
	parallel_reduce_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	// camp_parallel_any(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32) -> i32
	parallel_any_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	// camp_parallel_all(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_all_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	// camp_parallel_filter(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	parallel_filter_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	// camp_parallel_for_each(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> void
	parallel_for_each_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{},
	)

	parallel_map_func_idx := add_function(&env, parallel_map_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_Map] = parallel_map_func_idx
	parallel_reduce_func_idx := add_function(&env, parallel_reduce_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_Reduce] = parallel_reduce_func_idx
	parallel_any_func_idx := add_function(&env, parallel_any_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_Any] = parallel_any_func_idx
	parallel_all_func_idx := add_function(&env, parallel_all_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_All] = parallel_all_func_idx
	parallel_filter_func_idx := add_function(&env, parallel_filter_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_Filter] = parallel_filter_func_idx
	parallel_for_each_func_idx := add_function(&env, parallel_for_each_type_idx)
	runtime_func_indices[Runtime_Func.Parallel_For_Each] = parallel_for_each_func_idx

	// Map runtime function types
	map_new_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	map_insert_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	map_get_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	map_contains_type_idx := map_get_type_idx
	map_remove_type_idx := map_get_type_idx
	map_size_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
	map_singleton_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	map_keys_type_idx := map_size_type_idx
	map_values_type_idx := map_size_type_idx
	map_min_type_idx := map_size_type_idx
	map_max_type_idx := map_size_type_idx
	compare_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)

	map_new_func_idx := add_function(&env, map_new_type_idx)
	runtime_func_indices[Runtime_Func.Map_New] = map_new_func_idx
	map_insert_func_idx := add_function(&env, map_insert_type_idx)
	runtime_func_indices[Runtime_Func.Map_Insert] = map_insert_func_idx
	map_get_func_idx := add_function(&env, map_get_type_idx)
	runtime_func_indices[Runtime_Func.Map_Get] = map_get_func_idx
	map_contains_func_idx := add_function(&env, map_contains_type_idx)
	runtime_func_indices[Runtime_Func.Map_Contains] = map_contains_func_idx
	map_remove_func_idx := add_function(&env, map_remove_type_idx)
	runtime_func_indices[Runtime_Func.Map_Remove] = map_remove_func_idx
	map_size_func_idx := add_function(&env, map_size_type_idx)
	runtime_func_indices[Runtime_Func.Map_Size] = map_size_func_idx
	map_singleton_func_idx := add_function(&env, map_singleton_type_idx)
	runtime_func_indices[Runtime_Func.Map_Singleton] = map_singleton_func_idx
	map_keys_func_idx := add_function(&env, map_keys_type_idx)
	runtime_func_indices[Runtime_Func.Map_Keys] = map_keys_func_idx
	map_values_func_idx := add_function(&env, map_values_type_idx)
	runtime_func_indices[Runtime_Func.Map_Values] = map_values_func_idx
	map_min_func_idx := add_function(&env, map_min_type_idx)
	runtime_func_indices[Runtime_Func.Map_Min] = map_min_func_idx
	map_max_func_idx := add_function(&env, map_max_type_idx)
	runtime_func_indices[Runtime_Func.Map_Max] = map_max_func_idx
	set_min_func_idx := add_function(&env, map_min_type_idx)
	runtime_func_indices[Runtime_Func.Set_Min] = set_min_func_idx
	set_max_func_idx := add_function(&env, map_min_type_idx)
	runtime_func_indices[Runtime_Func.Set_Max] = set_max_func_idx

	// Map_Eq: (eq_fn: i32, cmp_fn: i32, map_a: i32, map_b: i32) -> i32
	map_eq_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	map_eq_func_idx := add_function(&env, map_eq_type_idx)
	runtime_func_indices[Runtime_Func.Map_Eq] = map_eq_func_idx
	// Set_Eq: (cmp_fn: i32, set_a: i32, set_b: i32) -> i32
	set_eq_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	set_eq_func_idx := add_function(&env, set_eq_type_idx)
	runtime_func_indices[Runtime_Func.Set_Eq] = set_eq_func_idx

	// Hash runtime function types
	hash_init_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{.I32})
	// (hasher: i32, val: i64) -> i32
	hash_write_i64_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I64},
		[]Wasm_Value_Type{.I32},
	)
	// (hasher: i32, val: i32) -> i32
	hash_write_i32_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	hash_write_i16_type_idx := hash_write_i32_type_idx
	hash_write_i8_type_idx := hash_write_i32_type_idx
	// (hasher: i32, val: f64) -> i32
	hash_write_f64_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .F64},
		[]Wasm_Value_Type{.I32},
	)
	// (hasher: i32, val: f32) -> i32
	hash_write_f32_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .F32},
		[]Wasm_Value_Type{.I32},
	)
	hash_write_str_type_idx := hash_write_i32_type_idx
	// (hasher: i32) -> i64
	hash_finish_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{.I64},
	)

	hash_init_func_idx := add_function(&env, hash_init_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Init] = hash_init_func_idx
	hash_write_i64_func_idx := add_function(&env, hash_write_i64_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_I64] = hash_write_i64_func_idx
	hash_write_i32_func_idx := add_function(&env, hash_write_i32_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_I32] = hash_write_i32_func_idx
	hash_write_i16_func_idx := add_function(&env, hash_write_i16_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_I16] = hash_write_i16_func_idx
	hash_write_i8_func_idx := add_function(&env, hash_write_i8_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_I8] = hash_write_i8_func_idx
	hash_write_f64_func_idx := add_function(&env, hash_write_f64_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_F64] = hash_write_f64_func_idx
	hash_write_f32_func_idx := add_function(&env, hash_write_f32_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_F32] = hash_write_f32_func_idx
	hash_write_str_func_idx := add_function(&env, hash_write_str_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Write_Str] = hash_write_str_func_idx
	hash_finish_func_idx := add_function(&env, hash_finish_type_idx)
	runtime_func_indices[Runtime_Func.Hash_Finish] = hash_finish_func_idx

	// I64_Compare: (i64, i64) -> i32 — built-in compare for I64 keys
	i64_compare_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I64, .I64},
		[]Wasm_Value_Type{.I32},
	)
	i64_compare_func_idx := add_function(&env, i64_compare_type_idx)
	runtime_func_indices[Runtime_Func.I64_Compare] = i64_compare_func_idx

	// I64_Trampoline: (i32, i32) -> i32 — unboxes two I64 keys and calls I64_Compare
	i64_trampoline_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	i64_trampoline_func_idx := add_function(&env, i64_trampoline_type_idx)
	runtime_func_indices[Runtime_Func.I64_Trampoline] = i64_trampoline_func_idx

	// I64_Debug_Trampoline: (i32) -> i32 — unboxes I64, calls I64_To_Str
	i64_debug_trampoline_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32},
		[]Wasm_Value_Type{.I32},
	)
	i64_debug_trampoline_func_idx := add_function(&env, i64_debug_trampoline_type_idx)
	runtime_func_indices[Runtime_Func.I64_Debug_Trampoline] = i64_debug_trampoline_func_idx

	// Container debug function types
	// List_Debug: (elem_debug_fn: i32, list: i32) -> i32
	list_debug_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	list_debug_func_idx := add_function(&env, list_debug_type_idx)
	runtime_func_indices[Runtime_Func.List_Debug] = list_debug_func_idx
	// Map_Debug: (key_debug_fn: i32, val_debug_fn: i32, map: i32) -> i32
	map_debug_type_idx := get_or_create_type(
		&env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	map_debug_func_idx := add_function(&env, map_debug_type_idx)
	runtime_func_indices[Runtime_Func.Map_Debug] = map_debug_func_idx
	// Set_Debug: (elem_debug_fn: i32, set: i32) -> i32
	set_debug_type_idx := list_debug_type_idx
	set_debug_func_idx := add_function(&env, set_debug_type_idx)
	runtime_func_indices[Runtime_Func.Set_Debug] = set_debug_func_idx
	// Result_Debug: (ok_debug_fn: i32, err_debug_fn: i32, result: i32) -> i32
	result_debug_type_idx := map_debug_type_idx
	result_debug_func_idx := add_function(&env, result_debug_type_idx)
	runtime_func_indices[Runtime_Func.Result_Debug] = result_debug_func_idx
	// Result_Debug_I64: (result: i32) -> i32 — hardcodes I64_To_Str direct calls
	// for when both Ok and Err payloads are I64 (stored unboxed in tag union)
	result_debug_i64_type_idx := i64_debug_trampoline_type_idx // (i32) -> i32
	result_debug_i64_func_idx := add_function(&env, result_debug_i64_type_idx)
	runtime_func_indices[Runtime_Func.Result_Debug_I64] = result_debug_i64_func_idx

	camp_alloc_code := emit_camp_alloc_body(heap_ptr_global_idx)
	append(&mod.codes, camp_alloc_code)

	camp_dup_code := emit_camp_dup_body()
	append(&mod.codes, camp_dup_code)

	camp_drop_code := emit_camp_drop_body(
		drop_func_idx,
		dealloc_func_idx,
		report_drop_overflow_func_idx,
	)
	append(&mod.codes, camp_drop_code)

	camp_print_str_code := emit_camp_print_str_body()
	append(&mod.codes, camp_print_str_code)

	camp_exit_code := emit_camp_exit_body()
	append(&mod.codes, camp_exit_code)

	camp_dealloc_code := emit_camp_dealloc_body()
	append(&mod.codes, camp_dealloc_code)

	camp_print_err_code := emit_camp_print_err_body()
	append(&mod.codes, camp_print_err_code)

	camp_list_alloc_code := emit_camp_list_alloc_body(alloc_func_idx)
	append(&mod.codes, camp_list_alloc_code)

	camp_list_push_code := emit_camp_list_push_body(list_grow_func_idx)
	append(&mod.codes, camp_list_push_code)

	camp_list_len_code := emit_camp_list_len_body()
	append(&mod.codes, camp_list_len_code)

	camp_list_get_code := emit_camp_list_get_body()
	append(&mod.codes, camp_list_get_code)

	camp_list_grow_code := emit_camp_list_grow_body(alloc_func_idx, dealloc_func_idx)
	append(&mod.codes, camp_list_grow_code)

	camp_str_len_code := emit_camp_str_len_body()
	append(&mod.codes, camp_str_len_code)

	camp_str_eq_code := emit_camp_str_eq_body()
	append(&mod.codes, camp_str_eq_code)

	camp_str_concat_code := emit_camp_str_concat_body(alloc_func_idx)
	append(&mod.codes, camp_str_concat_code)

	camp_str_slice_code := emit_camp_str_slice_body(alloc_func_idx)
	append(&mod.codes, camp_str_slice_code)

	camp_i64_to_str_code := emit_camp_i64_to_str_body(alloc_func_idx)
	append(&mod.codes, camp_i64_to_str_code)
	camp_i32_to_str_code := emit_camp_i32_to_str_body(alloc_func_idx)
	append(&mod.codes, camp_i32_to_str_code)
	camp_f64_to_str_code := emit_camp_f64_to_str_body(alloc_func_idx)
	append(&mod.codes, camp_f64_to_str_code)
	camp_bool_to_str_code := emit_camp_bool_to_str_body(alloc_func_idx)
	append(&mod.codes, camp_bool_to_str_code)

	camp_report_drop_overflow_code := emit_camp_report_drop_overflow_body(drop_overflow_msg_offset)
	append(&mod.codes, camp_report_drop_overflow_code)


	// Scheduler runtime function bodies
	shared := thread_count > 1
	append(&mod.codes, emit_camp_sched_init_body(shared))
	append(&mod.codes, emit_camp_sched_spawn_body(shared))
	append(&mod.codes, emit_camp_sched_join_body(shared))
	append(&mod.codes, emit_camp_sched_cancel_body(shared))
	append(&mod.codes, emit_camp_sched_complete_body(shared))
	append(&mod.codes, emit_camp_sched_yield_body(shared))
	append(&mod.codes, emit_camp_sched_block_io_body(shared))
	append(&mod.codes, emit_camp_sched_timer_insert_body(shared))
	append(&mod.codes, emit_camp_sched_timer_cancel_body(shared))
	append(&mod.codes, emit_camp_sched_notify_body(shared))
	append(&mod.codes, emit_camp_sched_park_body(shared))
	append(&mod.codes, emit_camp_sched_worker_loop_body(shared))
	append(&mod.codes, emit_camp_sched_current_task_body(shared))
	append(&mod.codes, emit_camp_sched_run_single_body(shared))
	append(&mod.codes, emit_camp_sched_poll_and_dispatch_body(shared))
	append(&mod.codes, emit_camp_sched_timer_tick_body(shared))
	append(&mod.codes, emit_camp_sched_timer_process_expired_body(shared))

	// Parallel! runtime function bodies
	append(&mod.codes, emit_camp_parallel_map_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_reduce_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_any_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_all_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_filter_body(runtime_func_indices))
	append(&mod.codes, emit_camp_parallel_for_each_body(runtime_func_indices))

	// Map runtime function bodies
	append(&mod.codes, emit_map_new_body(alloc_func_idx))
	append(&mod.codes, emit_map_insert_body(alloc_func_idx, compare_type_idx, env.table_idx))
	append(&mod.codes, emit_map_get_body(alloc_func_idx, compare_type_idx, env.table_idx))
	append(&mod.codes, emit_map_contains_body(compare_type_idx, env.table_idx))
	append(&mod.codes, emit_map_remove_body(compare_type_idx, env.table_idx))
	append(&mod.codes, emit_map_size_body())
	append(&mod.codes, emit_map_singleton_body(alloc_func_idx, compare_type_idx, env.table_idx))
	append(&mod.codes, emit_map_keys_body(alloc_func_idx, list_alloc_func_idx, list_push_func_idx))
	append(
		&mod.codes,
		emit_map_values_body(alloc_func_idx, list_alloc_func_idx, list_push_func_idx),
	)
	append(&mod.codes, emit_map_min_body(alloc_func_idx))
	append(&mod.codes, emit_map_max_body(alloc_func_idx))
	append(&mod.codes, emit_set_min_body(alloc_func_idx))
	append(&mod.codes, emit_set_max_body(alloc_func_idx))

	// Map_Eq and Set_Eq runtime function bodies
	append(&mod.codes, emit_map_eq_body(compare_type_idx, env.table_idx))
	append(&mod.codes, emit_set_eq_body(compare_type_idx, env.table_idx))

	// Hash runtime function bodies (SipHash-1-3)
	append(&mod.codes, emit_hash_init_body(alloc_func_idx))
	append(&mod.codes, emit_hash_write_i64_body())
	append(&mod.codes, emit_hash_write_i32_body())
	append(&mod.codes, emit_hash_write_i16_body())
	append(&mod.codes, emit_hash_write_i8_body())
	append(&mod.codes, emit_hash_write_f64_body())
	append(&mod.codes, emit_hash_write_f32_body())
	append(&mod.codes, emit_hash_write_str_body())
	append(&mod.codes, emit_hash_finish_body())

	// I64 compare function body
	append(&mod.codes, emit_i64_compare_body())
	// I64 trampoline function body (unboxes two I64 keys, calls I64_Compare)
	append(&mod.codes, emit_i64_trampoline_body(i64_compare_func_idx))
	// Register I64_compare in func_map so emit_expr can find it
	i64_compare_name := base.intern(interner, "I64_compare")
	env.func_map[u64(i64_compare_name)] = i64_compare_func_idx
	// Map I64_Compare -> I64_Trampoline in the trampoline cache
	env.i64_trampoline_cache[i64_compare_func_idx] = i64_trampoline_func_idx
	// I64 debug trampoline function body (unboxes I64, calls I64_To_Str)
	append(&mod.codes, emit_i64_debug_trampoline_body(i64_to_str_func_idx))
	// Register I64_debug_trampoline in func_map so resolve_debug_func can find it
	i64_dbg_trampoline_name := base.intern(interner, "I64_debug_trampoline")
	env.func_map[u64(i64_dbg_trampoline_name)] = i64_debug_trampoline_func_idx
	// Also register I64_debug itself to point to the trampoline, so that
	// if resolve_debug_func returns the raw I64_debug name, the lookup succeeds
	i64_debug_name := base.intern(interner, "I64_debug")
	env.func_map[u64(i64_debug_name)] = i64_debug_trampoline_func_idx

	// Debug callback type: (i32) -> i32 (takes value, returns Str pointer)
	debug_cb_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})

	// Container debug function bodies
	append(
		&mod.codes,
		emit_list_debug_body(
			str_concat_func_idx,
			debug_cb_type_idx,
			env.table_idx,
			env.debug_str_offsets["["],
			env.debug_str_offsets["]"],
			env.debug_str_offsets[", "],
		),
	)
	// Map.debug and Set.debug bodies
	append(
		&mod.codes,
		emit_map_debug_body(
			str_concat_func_idx,
			debug_cb_type_idx,
			env.table_idx,
			env.debug_str_offsets["Map{"],
			env.debug_str_offsets["}"],
			env.debug_str_offsets[", "],
			env.debug_str_offsets[": "],
		),
	)
	append(
		&mod.codes,
		emit_set_debug_body(
			str_concat_func_idx,
			debug_cb_type_idx,
			env.table_idx,
			env.debug_str_offsets["Set{"],
			env.debug_str_offsets["}"],
			env.debug_str_offsets[", "],
		),
	)
	append(
		&mod.codes,
		emit_result_debug_body(
			str_concat_func_idx,
			debug_cb_type_idx,
			env.table_idx,
			env.debug_str_offsets["Ok("],
			env.debug_str_offsets["Err("],
			env.debug_str_offsets[")"],
		),
	)
	// Result_Debug_I64 body: calls I64_To_Str directly for both Ok and Err
	append(
		&mod.codes,
		emit_result_debug_i64_body(
			str_concat_func_idx,
			i64_to_str_func_idx,
			env.debug_str_offsets["Ok("],
			env.debug_str_offsets["Err("],
			env.debug_str_offsets[")"],
		),
	)

	camp_alloc_name := base.intern(interner, "camp_alloc")
	env.func_map[u64(camp_alloc_name)] = alloc_func_idx
	camp_dealloc_name := base.intern(interner, "camp_dealloc")
	env.func_map[u64(camp_dealloc_name)] = dealloc_func_idx

	// Register top-level const decls as WASM globals so user code can
	// reference them via global.get. Only literal-valued consts are handled
	// here; computed initializers would need a _start prelude pass.
	for decl in ir_mod.decls {
		c, is_const := decl.(^ir.IR_Decl_Const)
		if !is_const {continue}

		init_buf: [dynamic]u8
		init_buf = make([dynamic]u8, 0, 8)
		valtype: Wasm_Value_Type = .I32
		is_mutable: bool = false

		#partial switch v in c.value {
		case ^ir.IR_Literal_Int:
			if v.type.wasm_type == .I32 {
				emit_instruction(Wasm_I32_Const{value = i32(v.value)}, &init_buf)
				valtype = .I32
			} else {
				emit_instruction(Wasm_I64_Const{value = v.value}, &init_buf)
				valtype = .I64
			}
		case ^ir.IR_Literal_Bool:
			emit_instruction(Wasm_I32_Const{value = v.value ? 1 : 0}, &init_buf)
			valtype = .I32
		case ^ir.IR_Literal_Float:
			emit_instruction(Wasm_F64_Const{value = v.value}, &init_buf)
			valtype = .F64
		case:
			// Non-literal const: emit as mutable global with zero initializer.
			// Actual value will be computed at _start time (future work).
			// Use the const's declared WASM type so the global type matches
			// references to it.
			switch c.type.wasm_type {
			case .I32:
				emit_instruction(Wasm_I32_Const{value = 0}, &init_buf)
				valtype = .I32
			case .I64:
				emit_instruction(Wasm_I64_Const{value = 0}, &init_buf)
				valtype = .I64
			case .F32:
				emit_instruction(Wasm_F32_Const{value = 0.0}, &init_buf)
				valtype = .F32
			case .F64:
				emit_instruction(Wasm_F64_Const{value = 0.0}, &init_buf)
				valtype = .F64
			case .Funcref, .Void:
				emit_instruction(Wasm_I32_Const{value = 0}, &init_buf)
				valtype = .I32
			}
			is_mutable = true
		}

		gidx := u32(len(mod.globals))
		append(
			&mod.globals,
			Wasm_Global{type = valtype, mutable = is_mutable, init = copy_dynamic_bytes(init_buf)},
		)
		delete(init_buf)

		wt: base.IR_Wasm_Type = .I32
		switch valtype {
		case .I32:
			wt = .I32
		case .I64:
			wt = .I64
		case .F32:
			wt = .F32
		case .F64:
			wt = .F64
		case .Funcref:
			wt = .I32
		}
		env.const_globals[c.name.name] = Const_Global_Info {
			global_idx = gidx,
			wasm_type  = wt,
		}
	}

	main_fn_idx := -1
	main_decl: ^ir.IR_Decl_Fn = nil
	env.decl_to_wasm_fn_idx = make(map[int]int, len(ir_mod.decls))
	for decl, decl_idx in ir_mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(interner, d.name.name)
			is_main_fn := name_str == "main" || name_str == "main!"
			params: []Wasm_Value_Type
			if is_main_fn && d.is_effectful && len(d.effects) > 0 {
				// Prepend evidence params (i32 pointers) for effectful main
				params = make([]Wasm_Value_Type, len(d.params) + len(d.effects))
				for i in 0 ..< len(d.effects) {
					params[i] = .I32
				}
				for p, i in d.params {
					params[len(d.effects) + i] = ir_wasm_type_to_value_type(p.type.wasm_type)
				}
			} else {
				params = make([]Wasm_Value_Type, len(d.params))
				for p, i in d.params {
					params[i] = ir_wasm_type_to_value_type(p.type.wasm_type)
				}
			}
			results: []Wasm_Value_Type
			if d.return_type.wasm_type != .Void {
				results = make([]Wasm_Value_Type, 1)
				results[0] = ir_wasm_type_to_value_type(d.return_type.wasm_type)
			}

			type_idx := get_or_create_type(&env, params, results)
			func_idx := add_function(&env, type_idx)
			if d.name.module != base.NO_NAME {
				mangled := base.mangle_name(d.name.module, d.name.name, interner)
				env.func_map[base.hash_string(mangled)] = func_idx
			}
			env.func_map[u64(d.name.name)] = func_idx
			env.decl_to_wasm_fn_idx[decl_idx] = func_idx

			for len(env.func_type_indices) <= func_idx {
				append(&env.func_type_indices, 0)
			}
			env.func_type_indices[func_idx] = u32(type_idx)

			if name_str == "main" || name_str == "main!" {
				main_fn_idx = func_idx
				main_decl = d
			}
		case ^ir.IR_Decl_Const, ^ir.IR_Decl_Effect, ^ir.IR_Decl_Expect:
		}
	}

	cont_func_idx := -1
	main_entry_wrapper_fn_idx := -1
	main_entry_wrapper_code: ^Wasm_Code
	if main_fn_idx >= 0 &&
	   main_decl != nil &&
	   main_decl.is_effectful &&
	   len(main_decl.effects) > 0 {
		cont_type_idx := get_or_create_type(
			&env,
			[]Wasm_Value_Type{.I32, .I64},
			[]Wasm_Value_Type{},
		)
		cont_func_idx = add_function(&env, cont_type_idx)

		for len(env.func_type_indices) <= cont_func_idx {
			append(&env.func_type_indices, 0)
		}
		env.func_type_indices[cont_func_idx] = u32(cont_type_idx)

		// Main entry wrapper: (i32) -> () to match the scheduler's task ABI
		// (call_indirect uses type 0 = (i32)->()). Unpacks evidence pointers
		// from the env record and tail-calls the CPS-transformed main!.
		main_entry_wrapper_type_idx := get_or_create_type(
			&env,
			[]Wasm_Value_Type{.I32},
			[]Wasm_Value_Type{},
		)
		main_entry_wrapper_fn_idx = add_function(&env, main_entry_wrapper_type_idx)

		for len(env.func_type_indices) <= main_entry_wrapper_fn_idx {
			append(&env.func_type_indices, 0)
		}
		env.func_type_indices[main_entry_wrapper_fn_idx] = u32(main_entry_wrapper_type_idx)

		// Emit wrapper code body: reads evidence from env, calls main!, unreachable
		ev_param_count := len(main_decl.effects)
		wrapper_buf: [dynamic]u8
		wrapper_buf = make([dynamic]u8, 0, CODE_BUF_MINOR)
		for i in 0 ..< ev_param_count {
			emit_instruction(Wasm_Local_Get{index = 0}, &wrapper_buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = u32(i * 4)}, &wrapper_buf)
		}
		// Continuation closure at offset ev_param_count * 4
		emit_instruction(Wasm_Local_Get{index = 0}, &wrapper_buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = u32(ev_param_count * 4)}, &wrapper_buf)
		// Call main! — CPS-transformed, never returns
		emit_instruction(Wasm_Call{index = u32(main_fn_idx)}, &wrapper_buf)
		emit_instruction(Wasm_Unreachable{}, &wrapper_buf)
		emit_instruction(Wasm_End{}, &wrapper_buf)

		wrapper_locals := make([]Wasm_Local_Decl, 0)
		wrapper_code_val := Wasm_Code {
			locals = wrapper_locals,
			body   = copy_dynamic_bytes(wrapper_buf),
		}
		main_entry_wrapper_code = &wrapper_code_val
		delete(wrapper_buf)
	}

	start_func_idx := -1
	if main_fn_idx >= 0 && main_decl != nil {
		start_type_idx := get_or_create_type(&env, []Wasm_Value_Type{}, []Wasm_Value_Type{})
		start_func_idx = add_function(&env, start_type_idx)
	}

	append(&mod.exports, Wasm_Export{name = "memory", kind = .Memory, index = 0})

	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			is_main :=
				base.intern_get(interner, d.name.name) == "main" ||
				base.intern_get(interner, d.name.name) == "main!"

			ev_count := 0
			if is_main && d.is_effectful {
				ev_count = len(d.effects)
			}
			env.locals = make([dynamic]Wasm_Local_Decl, 0, 32)
			env.local_map = make(map[base.Intern_ID]u32, 32)
			env.local_types = make(map[base.Intern_ID]base.IR_Type, 32)
			env.next_local = u32(len(d.params) + ev_count)

			for p, i in d.params {
				env.local_map[p.name] = u32(ev_count + i)
				env.local_types[p.name] = p.type
			}

			collected_locals: map[base.Intern_ID]base.IR_Type
			collected_locals = make(map[base.Intern_ID]base.IR_Type, 32)
			collect_locals(d.body, &collected_locals)

			local_groups: map[Wasm_Value_Type][dynamic]base.Intern_ID
			local_groups = make(map[Wasm_Value_Type][dynamic]base.Intern_ID, 8)

			for name, typ in collected_locals {
				vt := ir_wasm_type_to_value_type(typ.wasm_type)
				env.local_types[name] = typ
				if vt in local_groups {
					append(&local_groups[vt], name)
				} else {
					list: [dynamic]base.Intern_ID
					list = make([dynamic]base.Intern_ID, 0, 8)
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
			tmp_decl_idx := len(env.locals)
			append(&env.locals, Wasm_Local_Decl{count = 4, type = .I32})
			env.next_local += 4

			body_buf: [dynamic]u8
			body_buf = make([dynamic]u8, 0, CODE_BUF_XL)
			emit_expr(d.body, &body_buf, &env, runtime_func_indices[:])
			emit_instruction(Wasm_End{}, &body_buf)

			// Reserve enough tmp i32 locals for every unique slot the body
			// consumed (each nested IR_Construct_Tag/Record takes one). The
			// initial 4 is a floor for paths that use fixed tmp slots without
			// bumping tmp_count (e.g. list ops at tmp_local_base+0/+1).
			if env.tmp_count > 4 {
				env.locals[tmp_decl_idx].count = env.tmp_count
			}

			locals_copy := make([]Wasm_Local_Decl, len(env.locals))
			for l, i in env.locals {
				locals_copy[i] = l
			}

			append(
				&mod.codes,
				Wasm_Code{locals = locals_copy, body = copy_dynamic_bytes(body_buf)},
			)
			delete(body_buf)
			delete(env.locals)
			delete(env.local_map)
			delete(env.local_types)

			if is_main && d.is_effectful {
				continue
			}
		case ^ir.IR_Decl_Expect:
			if env.release_mode {
				// Release mode: skip expect check entirely — zero code emitted
				break
			}
			body_buf: [dynamic]u8
			body_buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
			emit_expect(d, &body_buf, &env, runtime_func_indices[:])
			emit_instruction(Wasm_End{}, &body_buf)
			append(&mod.codes, Wasm_Code{body = copy_dynamic_bytes(body_buf)})
			delete(body_buf)
			break
		case ^ir.IR_Decl_Const, ^ir.IR_Decl_Effect:
		}
	}
	worker_func_idx := -1
	if start_func_idx >= 0 {
		worker_type_idx := get_or_create_type(
			&env,
			[]Wasm_Value_Type{.I32},
			[]Wasm_Value_Type{.I32},
		)
		worker_func_idx = add_function(&env, worker_type_idx)
	}

	deferred_handler_codes: [dynamic]Wasm_Code
	deferred_handler_codes = make([dynamic]Wasm_Code, 0, 8)

	emit_start_function(
		&env,
		main_decl,
		main_fn_idx,
		cont_func_idx,
		start_func_idx,
		worker_func_idx,
		runtime_func_indices[:],
		ir_mod,
		thread_count,
		&deferred_handler_codes,
		main_entry_wrapper_fn_idx,
		main_entry_wrapper_code,
	)

	// Append deferred handler code bodies after _start and worker,
	// preserving the invariant that codes[k] maps to function index import_count + k
	for code in deferred_handler_codes {
		append(&mod.codes, code)
	}
	delete(deferred_handler_codes)

	// Build the funcref table AFTER all functions (including deferred effect
	// handlers allocated inside emit_start_function) have been assigned indices,
	// so handlers stored in evidence records are reachable via call_indirect.
	if env.table_idx >= 0 && env.next_func_idx > 0 {
		total_funcs := env.next_func_idx

		mod.tables[env.table_idx].min = u32(total_funcs)
		mod.tables[env.table_idx].max = u32(total_funcs)

		elem_offset_buf: [dynamic]u8
		elem_offset_buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
		emit_instruction(Wasm_I32_Const{value = 0}, &elem_offset_buf)

		func_idxs := make([]int, total_funcs)
		for i in 0 ..< total_funcs {
			func_idxs[i] = i
		}

		append(
			&mod.elements,
			Wasm_Element {
				table_idx = env.table_idx,
				offset = copy_dynamic_bytes(elem_offset_buf),
				func_idxs = func_idxs,
			},
		)
		delete(elem_offset_buf)
	}

	env.data_offset = 0
	for entry in ir_mod.string_table {
		offset := env.data_offset
		env.string_offsets[entry.id] = offset
		content := transmute([]u8)entry.value
		n := u32(len(content))
		// Length-prefixed layout: [i32 len little-endian][utf8 bytes].
		seg := make([]u8, 4 + len(content))
		seg[0] = u8(n)
		seg[1] = u8(n >> 8)
		seg[2] = u8(n >> 16)
		seg[3] = u8(n >> 24)
		copy(seg[4:], content)
		env.data_offset += 4 + n

		offset_buf: [dynamic]u8
		offset_buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
		emit_instruction(Wasm_I32_Const{value = i32(offset)}, &offset_buf)

		append(
			&mod.datas,
			Wasm_Data{mem_idx = 0, offset = copy_dynamic_bytes(offset_buf), bytes = seg},
		)
		delete(offset_buf)
	}

	// Data segment for camp_report_drop_overflow error message
	drop_overflow_msg_offset_data := drop_overflow_msg_offset
	drop_overflow_msg_bytes := transmute([]u8)drop_overflow_msg
	offset_buf_msg: [dynamic]u8
	offset_buf_msg = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(Wasm_I32_Const{value = i32(drop_overflow_msg_offset_data)}, &offset_buf_msg)
	append(
		&mod.datas,
		Wasm_Data {
			mem_idx = 0,
			offset = copy_dynamic_bytes(offset_buf_msg),
			bytes = drop_overflow_msg_bytes,
		},
	)
	delete(offset_buf_msg)

	// Data segment for throw handler error message prefix
	throw_err_msg_bytes := transmute([]u8)throw_err_msg
	offset_buf_throw: [dynamic]u8
	offset_buf_throw = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(Wasm_I32_Const{value = i32(throw_err_msg_offset)}, &offset_buf_throw)
	append(
		&mod.datas,
		Wasm_Data {
			mem_idx = 0,
			offset = copy_dynamic_bytes(offset_buf_throw),
			bytes = throw_err_msg_bytes,
		},
	)
	delete(offset_buf_throw)

	// Data segment for throw handler error message suffix
	throw_err_suffix_bytes := transmute([]u8)throw_err_suffix
	offset_buf_throw_suffix: [dynamic]u8
	offset_buf_throw_suffix = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(
		Wasm_I32_Const{value = i32(throw_err_suffix_offset)},
		&offset_buf_throw_suffix,
	)
	append(
		&mod.datas,
		Wasm_Data {
			mem_idx = 0,
			offset = copy_dynamic_bytes(offset_buf_throw_suffix),
			bytes = throw_err_suffix_bytes,
		},
	)
	delete(offset_buf_throw_suffix)

	// Data segments for debug string constants (length-prefixed)
	debug_str_names := [][2]string {
		{"[", "["},
		{"]", "]"},
		{", ", ", "},
		{"(", "("},
		{"Ok(", "Ok("},
		{"Err(", "Err("},
		{"Map{", "Map{"},
		{"}", "}"},
		{": ", ": "},
		{"Set{", "Set{"},
	}
	for ds in debug_str_names {
		if off, ok := env.debug_str_offsets[ds[0]]; ok {
			content := ds[1]
			n := u32(len(content))
			seg := make([]u8, 4 + len(content))
			seg[0] = u8(n)
			seg[1] = u8(n >> 8)
			seg[2] = u8(n >> 16)
			seg[3] = u8(n >> 24)
			copy(seg[4:], content)
			ds_offset_buf: [dynamic]u8
			ds_offset_buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
			emit_instruction(Wasm_I32_Const{value = i32(off)}, &ds_offset_buf)
			append(
				&mod.datas,
				Wasm_Data{mem_idx = 0, offset = copy_dynamic_bytes(ds_offset_buf), bytes = seg},
			)
			delete(ds_offset_buf)
		}
	}

	delete(env.type_map)
	delete(env.func_map)
	delete(env.func_type_indices)
	delete(env.decl_to_wasm_fn_idx)
	delete(env.string_offsets)
	delete(env.debug_str_offsets)
	delete(env.i64_trampoline_cache)
	return mod
}

emit_expect :: proc(
	d: ^ir.IR_Decl_Expect,
	buf: ^[dynamic]u8,
	env: ^Codegen_Env,
	runtime_indices: []int,
) {
	// Emit the condition expression — leaves Bool (i32, 0 or 1) on stack
	emit_expr(d.condition, buf, env, runtime_indices)

	// Check if false: condition == 0 → branch to failure
	emit_instruction(Wasm_I32_Eqz{}, buf)
	emit_instruction(Wasm_If{block_type = .Void}, buf)

	// Emit the failure message via print_err(ptr, len)
	msg := base.intern_get(env.interner, d.message_id)
	offset, ok := env.string_offsets[d.message_id]
	if ok {
		// String data is length-prefixed; the bytes start 4 bytes in.
		emit_instruction(Wasm_I32_Const{value = i32(offset + 4)}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(len(msg))}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
	}

	// Try to emit rich debug info for comparison operands
	if binop, is_binop := d.condition.(^ir.IR_BinOp); is_binop {
		if binop.op == .Eq || binop.op == .Ne {
			emit_operand_debug(binop.left, buf, env, runtime_indices)
			emit_operand_debug(binop.right, buf, env, runtime_indices)
		}
	}

	// Trap
	emit_instruction(Wasm_Unreachable{}, buf)
	emit_instruction(Wasm_End{}, buf) // end if
}

emit_operand_debug :: proc(
	operand: ir.IR_Expr,
	buf: ^[dynamic]u8,
	env: ^Codegen_Env,
	runtime_indices: []int,
) {
	#partial switch e in operand {
	case ^ir.IR_Var:
		local_idx, has_local := env.local_map[e.name]
		typ, has_type := env.local_types[e.name]
		if !has_local || !has_type {
			return
		}

		// Emit newline + space separator before operand value
		newline_id := base.intern(env.interner, "\n  ")
		if nl_off, nl_ok := env.string_offsets[newline_id]; nl_ok {
			emit_instruction(Wasm_I32_Const{value = i32(nl_off)}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(2)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = i32(10)}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(1)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(32)}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(1)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(32)}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(1)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
		}

		// Dispatch based on WASM type
		#partial switch typ.wasm_type {
		case .I64:
			emit_instruction(Wasm_Local_Get{index = local_idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])}, buf)
			emit_instruction(Wasm_Local_Tee{index = env.tmp_local_base}, buf) // save result
			emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf) // len = result[0:4]
			emit_instruction(Wasm_Local_Set{index = env.tmp_local_base + 1}, buf) // save len
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base}, buf)
			emit_instruction(Wasm_I32_Const{value = 4}, buf)
			emit_instruction(Wasm_I32_Add{}, buf) // data = result + 4
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base + 1}, buf) // restore len
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
		case .I32:
			emit_instruction(Wasm_Local_Get{index = local_idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.I32_To_Str])}, buf)
			emit_instruction(Wasm_Local_Tee{index = env.tmp_local_base}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
			emit_instruction(Wasm_Local_Set{index = env.tmp_local_base + 1}, buf)
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base}, buf)
			emit_instruction(Wasm_I32_Const{value = 4}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base + 1}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
		case .F64:
			emit_instruction(Wasm_Local_Get{index = local_idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.F64_To_Str])}, buf)
			emit_instruction(Wasm_Local_Tee{index = env.tmp_local_base}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
			emit_instruction(Wasm_Local_Set{index = env.tmp_local_base + 1}, buf)
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base}, buf)
			emit_instruction(Wasm_I32_Const{value = 4}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_instruction(Wasm_Local_Get{index = env.tmp_local_base + 1}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
		case .Funcref, .Void:
		// Skip
		}
	case ^ir.IR_Literal_Int:
		emit_instruction(Wasm_I64_Const{value = e.value}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])}, buf)
		emit_instruction(Wasm_Local_Tee{index = env.tmp_local_base}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
		emit_instruction(Wasm_Local_Set{index = env.tmp_local_base + 1}, buf)
		emit_instruction(Wasm_Local_Get{index = env.tmp_local_base}, buf)
		emit_instruction(Wasm_I32_Const{value = 4}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_Local_Get{index = env.tmp_local_base + 1}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, buf)
	}
}


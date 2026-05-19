package camp

WASI_MODULE :: "wasi_snapshot_preview1"

RUNTIME_FUNC_COUNT :: 5

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

	emit_wasi_imports(&env)
	emit_runtime_types(&env)

	append(&mod.memories, Wasm_Memory{min = 1})

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
			if d.is_effectful {
			} else if d.return_type.wasm_type != .Void {
				results = make([]Wasm_Value_Type, 1)
				results[0] = ir_wasm_type_to_value_type(d.return_type.wasm_type)
			}

			type_idx := get_or_create_type(&env, params, results)
			func_idx := add_function(&env, type_idx)
			env.func_map[int(d.name.name)] = func_idx

			if name_str == "main" {
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
			is_main := intern_get(&ctx.interner, d.name.name) == "main"

			if is_main && d.is_effectful {
				placeholder: [dynamic]u8
				placeholder = make([dynamic]u8, 0, 4)
				emit_instruction(Wasm_Unreachable{}, &placeholder)
				emit_instruction(Wasm_End{}, &placeholder)
				append(&mod.codes, Wasm_Code{locals = []Wasm_Local_Decl{}, body = copy_dynamic_bytes(placeholder)})
				delete(placeholder)
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

	if start_func_idx >= 0 && main_decl != nil {
		code_buf: [dynamic]u8
		code_buf = make([dynamic]u8, 0, 256)

		main_body := extract_effectful_body(main_decl.body)
		emit_expr(main_body, &code_buf, &env, runtime_func_indices[:])

		main_ret_type := get_main_return_type(ir_mod, &ctx.interner)
		if main_ret_type == .I64 {
			emit_instruction(Wasm_I32_Wrap_I64{}, &code_buf)
		}

		emit_instruction(Wasm_Call{index = 0}, &code_buf)
		emit_instruction(Wasm_End{}, &code_buf)

		append(&mod.codes, Wasm_Code{locals = []Wasm_Local_Decl{}, body = copy_dynamic_bytes(code_buf)})
		delete(code_buf)

		append(&mod.exports, Wasm_Export{name = "_start", kind = .Func, index = start_func_idx})
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
	return mod
}

get_main_return_type :: proc(ir_mod: IR_Module, interner: ^Intern_Table) -> IR_Wasm_Type {
	for decl in ir_mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			name_str := intern_get(interner, d.name.name)
			if name_str == "main" {
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
	case:
	}
}

RUNTIME_ALLOC :: 0
RUNTIME_DUP :: 1
RUNTIME_DROP :: 2
RUNTIME_PRINT_STR :: 3
RUNTIME_EXIT :: 4

extract_effectful_body :: proc(expr: IR_Expr) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Let:
		if inner := extract_effectful_body(e.body); inner != nil {
			return e.value
		}
		return expr
	case:
		return expr
	}
}

emit_expr :: proc(expr: IR_Expr, buf: ^[dynamic]u8, env: ^Codegen_Env, runtime_indices: []int) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Literal_Int:
		emit_instruction(Wasm_I64_Const{value = e.value}, buf)
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
		if idx, ok := env.func_map[int(e.callee.name)]; ok {
			emit_instruction(Wasm_Call{index = u32(idx)}, buf)
		} else {
			emit_instruction(Wasm_Call{index = 0}, buf)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		if idx, ok := env.func_map[int(e.callee.name)]; ok {
			emit_instruction(Wasm_Return_Call{index = u32(idx)}, buf)
		} else {
			emit_instruction(Wasm_Return_Call{index = 0}, buf)
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
		emit_binop(e.op, e.type.wasm_type, buf)
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
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Construct_Tag:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Construct_Record:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Field_Access:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Method_Call:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Handle:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Perform:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Closure:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Closure_Call:
		emit_expr(e.callee, buf, env, runtime_indices)
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Drop_Reuse:
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Alloc_At:
		emit_instruction(Wasm_Unreachable{}, buf)
	case:
		emit_instruction(Wasm_Unreachable{}, buf)
	}
}

emit_binop :: proc(op: Token_Kind, wasm_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Plus:
		if wasm_type == .I32 {
			emit_instruction(Wasm_I32_Add{}, buf)
		} else {
			emit_instruction(Wasm_I64_Add{}, buf)
		}
	case .Minus:
		if wasm_type == .I32 {
			emit_instruction(Wasm_I32_Sub{}, buf)
		} else {
			emit_instruction(Wasm_I64_Sub{}, buf)
		}
	case .Star:
		if wasm_type == .I32 {
			emit_instruction(Wasm_I32_Mul{}, buf)
		} else {
			emit_instruction(Wasm_I64_Mul{}, buf)
		}
	case:
		emit_instruction(Wasm_I64_Add{}, buf)
	}
}

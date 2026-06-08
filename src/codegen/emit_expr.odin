package codegen

import "camp:base"
import "camp:ir"

coerce_arg_to :: proc(
	buf: ^[dynamic]u8,
	src: base.IR_Wasm_Type,
	func_type_idx: int,
	func_arg_idx: int,
	env: ^Codegen_Env,
) {
	if func_type_idx < 0 || func_type_idx >= len(env.mod.types) do return
	func_type := env.mod.types[func_type_idx]
	if func_arg_idx < 0 || func_arg_idx >= len(func_type.params) do return
	dst := value_type_to_ir_wasm_type(func_type.params[func_arg_idx])
	if src == dst do return
	if src == .I32 && dst == .I64 {
		emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
	} else if src == .I64 && dst == .I32 {
		emit_instruction(Wasm_I32_Wrap_I64{}, buf)
	}
}

coerce_ret_to :: proc(
	buf: ^[dynamic]u8,
	func_type_idx: int,
	expected: base.IR_Wasm_Type,
	env: ^Codegen_Env,
) {
	if func_type_idx < 0 || func_type_idx >= len(env.mod.types) do return
	func_type := env.mod.types[func_type_idx]
	if len(func_type.results) != 1 do return
	src := value_type_to_ir_wasm_type(func_type.results[0])
	if src == expected do return
	if src == .I32 && expected == .I64 {
		emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
	} else if src == .I64 && expected == .I32 {
		emit_instruction(Wasm_I32_Wrap_I64{}, buf)
	}
}

collect_locals :: proc(expr: ir.IR_Expr, locals: ^map[base.Intern_ID]base.IR_Type) {
	if expr == nil do return

	#partial switch e in expr {
	case ^ir.IR_Let:
		if e.type.wasm_type != .Void {
			locals^[e.binding] = e.type
		}
		collect_locals(e.value, locals)
		collect_locals(e.body, locals)
	case ^ir.IR_Call:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^ir.IR_Closure_Call:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^ir.IR_Tail_Call:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^ir.IR_If:
		collect_locals(e.condition, locals)
		collect_locals(e.then_branch, locals)
		collect_locals(e.else_branch, locals)
	case ^ir.IR_Match:
		collect_locals(e.scrutinee, locals)
		scrut_type := ir.ir_expr_wasm_type(e.scrutinee)
		for arm in e.arms {
			collect_pattern_locals(arm.pattern, locals, scrut_type)
			if arm.guard != nil do collect_locals(arm.guard, locals)
			collect_locals(arm.body, locals)
		}
	case ^ir.IR_BinOp:
		collect_locals(e.left, locals)
		collect_locals(e.right, locals)
	case ^ir.IR_Return:
		collect_locals(e.value, locals)
	case ^ir.IR_Block:
		for stmt in e.statements {
			collect_locals(stmt, locals)
		}
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			collect_locals(p, locals)
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			collect_locals(f.value, locals)
		}
		collect_locals(e.rest, locals)
	case ^ir.IR_Construct_Tuple:
		for el in e.elements {
			collect_locals(el, locals)
		}
	case ^ir.IR_Field_Access:
		collect_locals(e.record, locals)
	case ^ir.IR_Method_Call:
		collect_locals(e.receiver, locals)
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^ir.IR_Handle:
		collect_locals(e.body, locals)
		for arm in e.arms {
			collect_locals(arm.body, locals)
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			collect_locals(arg, locals)
		}
	case ^ir.IR_Closure:
		collect_locals(e.env, locals)
		collect_locals(e.body, locals)
	case ^ir.IR_Crash:
		collect_locals(e.message, locals)
	case ^ir.IR_Resume:
		collect_locals(e.value, locals)
		if e.ev != nil {
			collect_locals(e.ev, locals)
		}
	case ^ir.IR_I32_Load:
		collect_locals(e.base, locals)
	case ^ir.IR_I32_Store:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^ir.IR_Atomic_Load:
		collect_locals(e.base, locals)
	case ^ir.IR_Atomic_Store:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^ir.IR_Atomic_RMW:
		collect_locals(e.base, locals)
		collect_locals(e.value, locals)
	case ^ir.IR_Atomic_Fence:
	case ^ir.IR_Wait:
		collect_locals(e.base, locals)
		collect_locals(e.expected, locals)
		collect_locals(e.timeout, locals)
	case ^ir.IR_Notify:
		collect_locals(e.base, locals)
		collect_locals(e.count, locals)
	case ^ir.IR_Assign:
		if e.type.wasm_type != .Void {
			locals^[e.binding] = e.type
		}
		collect_locals(e.value, locals)
	case ^ir.IR_Loop:
		if e.type.wasm_type != .Void {
			locals^[e.var] = e.type
		}
		collect_locals(e.iterable, locals)
		collect_locals(e.body, locals)
	case ^ir.IR_Literal_Int,
	     ^ir.IR_Literal_Float,
	     ^ir.IR_Literal_String,
	     ^ir.IR_Literal_Bool,
	     ^ir.IR_Var,
	     ^ir.IR_Dup,
	     ^ir.IR_Drop,
	     ^ir.IR_Expr_Nominal_Construct:
	}
}

collect_pattern_locals :: proc(
	pattern: ir.IR_Pattern,
	locals: ^map[base.Intern_ID]base.IR_Type,
	scrut_type: base.IR_Wasm_Type = .I32,
) {
	if pattern == nil do return

	#partial switch p in pattern {
	case ^ir.IR_Pat_Tag:
		for name, j in p.payload {
			wt: base.IR_Wasm_Type = .I32
			if j < len(p.payload_wasm_types) {
				wt = p.payload_wasm_types[j]
			}
			locals^[name] = base.IR_Type {
				wasm_type = wt,
				type_id   = base.Type_Var_ID(0),
			}
		}
	case ^ir.IR_Pat_Var:
		// A var pattern binds the scrutinee directly, so the binding's
		// wasm type matches the scrutinee's. Defaulting to i32 was wrong
		// for any non-i32 scrutinee (notably i64 integer matches with
		// guards).
		locals^[p.name] = base.IR_Type {
			wasm_type = scrut_type,
			type_id   = base.Type_Var_ID(0),
		}
	case ^ir.IR_Pat_Record:
		for f in p.fields {
			locals^[f.binding] = base.IR_Type {
				wasm_type = f.wasm_type,
				type_id   = base.Type_Var_ID(0),
			}
		}
	case ^ir.IR_Pat_Wildcard:
	case ^ir.IR_Pat_Tuple:
		for el in p.elements {
			locals^[el.binding] = base.IR_Type {
				wasm_type = el.wasm_type,
				type_id   = base.Type_Var_ID(0),
			}
		}
	case ^ir.IR_Pat_Bool:
	case ^ir.IR_Pat_Int:
	case ^ir.IR_Pat_String:
	}
}

Runtime_Func :: enum {
	Alloc,
	Dup,
	Drop,
	Print_Str,
	Exit,
	Dealloc,
	Print_Err,
	List_Alloc,
	List_Push,
	List_Len,
	List_Get,
	List_Grow,
	Str_Len,
	Str_Eq,
	Sched_Init,
	Sched_Spawn,
	Sched_Join,
	Sched_Cancel,
	Sched_Complete,
	Sched_Yield,
	Sched_Block_IO,
	Sched_Timer_Insert,
	Sched_Timer_Cancel,
	Sched_Notify,
	Sched_Park,
	Sched_Worker_Loop,
	Sched_Current_Task,
	Sched_Run_Single,
	Sched_Poll_And_Dispatch,
	Sched_Timer_Tick,
	Sched_Timer_Process_Expired,
	Parallel_Map,
	Parallel_Reduce,
	Parallel_Any,
	Parallel_All,
	Parallel_Filter,
	Parallel_For_Each,
	Str_Concat,
	Str_Slice,
	I64_To_Str,
	I32_To_Str,
	F64_To_Str,
	Bool_To_Str,
	Report_Drop_Overflow,
	Map_New,
	Map_Insert,
	Map_Get,
	Map_Contains,
	Map_Remove,
	Map_Size,
	Map_Singleton,
	Map_Keys,
	Map_Values,
	Map_Min,
	Map_Max,
	Set_Min,
	Set_Max,
	Map_Eq,
	Set_Eq,
	Hash_Init,
	Hash_Write_I64,
	Hash_Write_I32,
	Hash_Write_I16,
	Hash_Write_I8,
	Hash_Write_F64,
	Hash_Write_F32,
	Hash_Write_Str,
	Hash_Finish,
	List_Debug,
	Map_Debug,
	Set_Debug,
	Result_Debug,
	I64_Compare,
	I64_Trampoline,
}

RUNTIME_FUNC_COUNT :: int(len(Runtime_Func))

extract_effectful_body :: proc(expr: ir.IR_Expr) -> ir.IR_Expr {
	#partial switch e in expr {
	case ^ir.IR_Let:
		#partial switch b in e.body {
		case ^ir.IR_Tail_Call, ^ir.IR_Closure_Call:
			return e.value
		case ^ir.IR_Literal_Int,
		     ^ir.IR_Literal_Float,
		     ^ir.IR_Literal_String,
		     ^ir.IR_Literal_Bool,
		     ^ir.IR_Var,
		     ^ir.IR_Let,
		     ^ir.IR_Call,
		     ^ir.IR_If,
		     ^ir.IR_Match,
		     ^ir.IR_Construct_Tag,
		     ^ir.IR_Expr_Nominal_Construct,
		     ^ir.IR_Construct_Record,
		     ^ir.IR_Construct_Tuple,
		     ^ir.IR_Field_Access,
		     ^ir.IR_Method_Call,
		     ^ir.IR_Handle,
		     ^ir.IR_Perform,
		     ^ir.IR_Resume,
		     ^ir.IR_Closure,
		     ^ir.IR_Return,
		     ^ir.IR_Block,
		     ^ir.IR_BinOp,
		     ^ir.IR_Dup,
		     ^ir.IR_Drop,
		     ^ir.IR_Crash,
		     ^ir.IR_I32_Load,
		     ^ir.IR_I32_Store,
		     ^ir.IR_Atomic_Load,
		     ^ir.IR_Atomic_Store,
		     ^ir.IR_Atomic_RMW,
		     ^ir.IR_Atomic_Fence,
		     ^ir.IR_Wait,
		     ^ir.IR_Notify,
		     ^ir.IR_Assign,
		     ^ir.IR_Loop:
			return expr
		}
	case ^ir.IR_Literal_Int,
	     ^ir.IR_Literal_Float,
	     ^ir.IR_Literal_String,
	     ^ir.IR_Literal_Bool,
	     ^ir.IR_Var,
	     ^ir.IR_Call,
	     ^ir.IR_Tail_Call,
	     ^ir.IR_Closure_Call,
	     ^ir.IR_If,
	     ^ir.IR_Match,
	     ^ir.IR_Construct_Tag,
	     ^ir.IR_Expr_Nominal_Construct,
	     ^ir.IR_Construct_Record,
	     ^ir.IR_Construct_Tuple,
	     ^ir.IR_Field_Access,
	     ^ir.IR_Method_Call,
	     ^ir.IR_Handle,
	     ^ir.IR_Perform,
	     ^ir.IR_Resume,
	     ^ir.IR_Closure,
	     ^ir.IR_Return,
	     ^ir.IR_Block,
	     ^ir.IR_BinOp,
	     ^ir.IR_Dup,
	     ^ir.IR_Drop,
	     ^ir.IR_Crash,
	     ^ir.IR_I32_Load,
	     ^ir.IR_I32_Store,
	     ^ir.IR_Atomic_Load,
	     ^ir.IR_Atomic_Store,
	     ^ir.IR_Atomic_RMW,
	     ^ir.IR_Atomic_Fence,
	     ^ir.IR_Wait,
	     ^ir.IR_Notify,
	     ^ir.IR_Assign,
	     ^ir.IR_Loop:
		return expr
	}
	return expr
}

emit_expr :: proc(expr: ir.IR_Expr, buf: ^[dynamic]u8, env: ^Codegen_Env, runtime_indices: []int) {
	if expr == nil do return

	#partial switch e in expr {
	case ^ir.IR_Literal_Int:
		if e.type.wasm_type == .I32 {
			emit_instruction(Wasm_I32_Const{value = i32(e.value)}, buf)
		} else {
			emit_instruction(Wasm_I64_Const{value = e.value}, buf)
		}
	case ^ir.IR_Literal_Float:
		emit_instruction(Wasm_F64_Const{value = e.value}, buf)
	case ^ir.IR_Literal_Bool:
		if e.value {
			emit_instruction(Wasm_I32_Const{value = 1}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
	case ^ir.IR_Literal_String:
		offset, ok := env.string_offsets[e.id]
		if !ok {
			offset = 0
		}
		emit_instruction(Wasm_I32_Const{value = i32(offset)}, buf)
	case ^ir.IR_Var:
		if idx, ok := env.local_map[e.name]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
		} else if g, ok := env.const_globals[e.name]; ok {
			emit_instruction(Wasm_Global_Get{index = g.global_idx}, buf)
		} else if idx, ok := env.func_map[u64(e.name)]; ok {
			emit_instruction(Wasm_I32_Const{value = i32(idx)}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
	case ^ir.IR_Let:
		emit_expr(e.value, buf, env, runtime_indices)
		if e.type.wasm_type == .Void {
			// Void-typed let: value is for side effects only, drop if non-void
			value_type := ir_operand_wasm_type(e.value)
			if value_type != .Void {
				emit_instruction(Wasm_Drop{}, buf)
			}
		} else if idx, ok := env.local_map[e.binding]; ok {
			emit_instruction(Wasm_Local_Set{index = idx}, buf)
		} else {
			emit_instruction(Wasm_Drop{}, buf)
		}
		emit_expr(e.body, buf, env, runtime_indices)
	case ^ir.IR_Assign:
		emit_expr(e.value, buf, env, runtime_indices)
		if idx, ok := env.local_map[e.binding]; ok {
			emit_instruction(Wasm_Local_Set{index = idx}, buf)
		} else {
			emit_instruction(Wasm_Drop{}, buf)
		}
	case ^ir.IR_Loop:
		// Evaluate iterable, store in tmp local
		emit_expr(e.iterable, buf, env, runtime_indices)
		list_local := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1
		emit_instruction(Wasm_Local_Set{index = list_local}, buf)

		// block $break (label 1), loop $continue (label 0)
		emit_instruction(Wasm_Block{block_type = .Void}, buf)
		emit_instruction(Wasm_Loop{block_type = .Void}, buf)

		// Check if list is empty: tag byte == 0 (Nil)
		emit_instruction(Wasm_Local_Get{index = list_local}, buf)
		emit_instruction(Wasm_I32_Load8U{offset = CAMP_TAG_TAG_OFFSET}, buf)
		emit_instruction(Wasm_I32_Const{value = 0}, buf)
		emit_instruction(Wasm_I32_Eq{}, buf)
		emit_instruction(Wasm_Br_If{label = 1}, buf) // break if Nil

		// Get head (Cons payload[0] = head at CAMP_TAG_FIELDS_OFFSET)
		emit_instruction(Wasm_Local_Get{index = list_local}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
		if idx, ok := env.local_map[e.var]; ok {
			emit_instruction(Wasm_Local_Set{index = idx}, buf)
		} else {
			emit_instruction(Wasm_Drop{}, buf)
		}

		// Get tail (Cons payload[1] = tail at CAMP_TAG_FIELDS_OFFSET + 8)
		emit_instruction(Wasm_Local_Get{index = list_local}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
		emit_instruction(Wasm_Local_Set{index = list_local}, buf)

		// Emit body
		emit_expr(e.body, buf, env, runtime_indices)

		// Drop body result (loop returns Unit)
		emit_instruction(Wasm_Drop{}, buf)

		// Continue loop
		emit_instruction(Wasm_Br{label = 0}, buf)
		emit_instruction(Wasm_End{}, buf) // end loop
		emit_instruction(Wasm_End{}, buf) // end block
	case ^ir.IR_Call:
		// Check for intrinsic stdlib calls (recognized by module-qualified name)
		if e.callee.module != base.NO_NAME {
			module_str := base.intern_get(env.interner, e.callee.module)
			name_str := base.intern_get(env.interner, e.callee.name)

			if module_str == "Str" {
				if name_str == "length" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Str_Len])},
						buf,
					)
					// Str.length returns I64 in Camp but Runtime_Func.Str_Len returns i32
					emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
					break
				}
				if name_str == "eq" && len(e.args) == 2 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Str_Eq])},
						buf,
					)
					break
				}
				if name_str == "concat" && len(e.args) == 2 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Str_Concat])},
						buf,
					)
					break
				}
			}

			if module_str == "List" {
				if name_str == "length" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Len])},
						buf,
					)
					// List.length returns I64 in Camp but Runtime_Func.List_Len returns i32
					emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
					break
				}
				if name_str == "get" && len(e.args) == 2 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Get])},
						buf,
					)
					break
				}
				if name_str == "push" && len(e.args) == 2 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Push])},
						buf,
					)
					break
				}
				if name_str == "alloc" && len(e.args) == 0 {
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Alloc])},
						buf,
					)
					break
				}
				if name_str == "debug" && len(e.args) == 1 {
					// Resolve element debug function from debug_func
					debug_fn_idx := 0
					if e.debug_func.module != base.NO_NAME && e.debug_func.name != 0 {
						mangled := base.mangle_name(
							e.debug_func.module,
							e.debug_func.name,
							env.interner,
						)
						if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
							debug_fn_idx = idx
						}
					} else if e.debug_func.name != 0 {
						if idx, ok := env.func_map[u64(e.debug_func.name)]; ok {
							debug_fn_idx = idx
						}
					}
					emit_instruction(Wasm_I32_Const{value = i32(debug_fn_idx)}, buf)
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Debug])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
			}

			if module_str == "Map" {
				// Map intrinsics: the compare function index is passed as the first arg.
				// It comes from the ord_compare_func resolved during lowering.
				// Look up the compare function in func_map.
				cmp_fn_idx := 0
				if e.ord_compare_func.module != base.NO_NAME && e.ord_compare_func.name != 0 {
					mangled := base.mangle_name(
						e.ord_compare_func.module,
						e.ord_compare_func.name,
						env.interner,
					)
					if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
						cmp_fn_idx = idx
					}
				} else if e.ord_compare_func.name != 0 {
					if idx, ok := env.func_map[u64(e.ord_compare_func.name)]; ok {
						cmp_fn_idx = idx
					}
				}

				// Detect I64 key type for boxing/trampoline support.
				// Key expr position varies by operation.
				is_i64_key := false
				key_expr: ir.IR_Expr = nil
				if name_str == "singleton" && len(e.args) == 2 {
					key_expr = e.args[0]
				} else if name_str == "insert" && len(e.args) == 3 {
					key_expr = e.args[0]
				} else if (name_str == "get" || name_str == "contains" || name_str == "remove") &&
				   len(e.args) == 2 {
					key_expr = e.args[0]
				}
				if key_expr != nil && ir.ir_expr_wasm_type(key_expr) == .I64 {
					is_i64_key = true
					// If cmp_fn_idx is 0 (ord_compare_func not resolved),
					// try to find I64.compare directly in func_map.
					if cmp_fn_idx == 0 {
						i64_cmp_id := base.intern(env.interner, "I64_compare")
						if idx, ok := env.func_map[u64(i64_cmp_id)]; ok {
							cmp_fn_idx = idx
						}
					}
					if cmp_fn_idx == 0 {
						compare_id := base.intern(env.interner, "compare")
						if idx, ok := env.func_map[u64(compare_id)]; ok {
							cmp_fn_idx = idx
						}
					}
					if cmp_fn_idx != 0 {
						cmp_fn_idx = get_or_create_i64_trampoline(env, cmp_fn_idx)
					}
				}

				if name_str == "new" && len(e.args) == 0 {
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_New])},
						buf,
					)
					break
				}
				if name_str == "singleton" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
						if ir.ir_expr_wasm_type(e.args[0]) ==
						   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[1]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Singleton])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
				if name_str == "insert" && len(e.args) == 3 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					// args[0]=key, args[1]=value, args[2]=map
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
						if ir.ir_expr_wasm_type(e.args[0]) ==
						   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[1]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_expr(e.args[2], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[2]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Insert])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
				if name_str == "get" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
						if ir.ir_expr_wasm_type(e.args[0]) ==
						   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[1]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Get])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
				if name_str == "contains" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
						if ir.ir_expr_wasm_type(e.args[0]) ==
						   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[1]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Contains])},
						buf,
					)
					break
				}
				if name_str == "remove" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
						if ir.ir_expr_wasm_type(e.args[0]) ==
						   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[1]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Remove])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
				if name_str == "size" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					if ir.ir_expr_wasm_type(e.args[0]) ==
					   .I64 {emit_instruction(Wasm_I32_Wrap_I64{}, buf)}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Size])},
						buf,
					)
					emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
					break
				}
				if name_str == "keys" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Keys])},
						buf,
					)
					break
				}
				if name_str == "values" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Values])},
						buf,
					)
					break
				}
				if name_str == "min" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Min])},
						buf,
					)
					break
				}
				if name_str == "max" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Max])},
						buf,
					)
					break
				}
				if name_str == "eq" && len(e.args) == 2 {
					// Map.eq: resolve eq_func for value comparison and cmp_func for key comparison
					eq_fn_idx := 0
					if e.eq_func.module != base.NO_NAME && e.eq_func.name != 0 {
						mangled := base.mangle_name(e.eq_func.module, e.eq_func.name, env.interner)
						if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
							eq_fn_idx = idx
						}
					} else if e.eq_func.name != 0 {
						if idx, ok := env.func_map[u64(e.eq_func.name)]; ok {
							eq_fn_idx = idx
						}
					}
					cmp_fn_idx := 0
					if e.ord_compare_func.module != base.NO_NAME && e.ord_compare_func.name != 0 {
						mangled := base.mangle_name(
							e.ord_compare_func.module,
							e.ord_compare_func.name,
							env.interner,
						)
						if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
							cmp_fn_idx = idx
						}
					} else if e.ord_compare_func.name != 0 {
						if idx, ok := env.func_map[u64(e.ord_compare_func.name)]; ok {
							cmp_fn_idx = idx
						}
					}
					emit_instruction(Wasm_I32_Const{value = i32(eq_fn_idx)}, buf)
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Eq])},
						buf,
					)
					break
				}
			}

			if module_str == "Set" {
				// Set intrinsics: delegate to Map with unit value as the value arg.
				// The compare function index is resolved the same way as Map.
				cmp_fn_idx := 0
				if e.ord_compare_func.module != base.NO_NAME && e.ord_compare_func.name != 0 {
					mangled := base.mangle_name(
						e.ord_compare_func.module,
						e.ord_compare_func.name,
						env.interner,
					)
					if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
						cmp_fn_idx = idx
					}
				} else if e.ord_compare_func.name != 0 {
					if idx, ok := env.func_map[u64(e.ord_compare_func.name)]; ok {
						cmp_fn_idx = idx
					}
				}

				// Detect I64 key type for boxing/trampoline support.
				is_i64_key := false
				key_expr: ir.IR_Expr = nil
				if name_str == "singleton" && len(e.args) == 1 {
					key_expr = e.args[0]
				} else if name_str == "insert" && len(e.args) == 2 {
					key_expr = e.args[1]
				} else if (name_str == "contains" || name_str == "remove") && len(e.args) == 2 {
					key_expr = e.args[0]
				}
				if key_expr != nil && ir.ir_expr_wasm_type(key_expr) == .I64 {
					is_i64_key = true
					cmp_fn_idx = get_or_create_i64_trampoline(env, cmp_fn_idx)
				}

				// UNIT_VALUE: pointer to a zero-field record (tag=0, scan_size=0, no fields)
				// Allocated as a global constant in static memory.
				unit_value_ptr := env.unit_value_offset

				if name_str == "new" && len(e.args) == 0 {
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_New])},
						buf,
					)
					break
				}
				if name_str == "singleton" && len(e.args) == 1 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
					}
					emit_instruction(Wasm_I32_Const{value = i32(unit_value_ptr)}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Singleton])},
						buf,
					)
					break
				}
				if name_str == "insert" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_I32_Const{value = i32(unit_value_ptr)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[1], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[1], buf, env, runtime_indices)
					}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Insert])},
						buf,
					)
					break
				}
				if name_str == "contains" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Contains])},
						buf,
					)
					break
				}
				if name_str == "remove" && len(e.args) == 2 {
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					if is_i64_key {
						emit_box_i64_key(e.args[0], buf, env, runtime_indices)
					} else {
						emit_expr(e.args[0], buf, env, runtime_indices)
					}
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Remove])},
						buf,
					)
					break
				}
				if name_str == "size" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Map_Size])},
						buf,
					)
					emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
					break
				}
				if name_str == "min" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Set_Min])},
						buf,
					)
					break
				}
				if name_str == "max" && len(e.args) == 1 {
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Set_Max])},
						buf,
					)
					break
				}
				if name_str == "eq" && len(e.args) == 2 {
					// Set.eq: resolve cmp_func for key comparison only (no values in sets)
					cmp_fn_idx := 0
					if e.ord_compare_func.module != base.NO_NAME && e.ord_compare_func.name != 0 {
						mangled := base.mangle_name(
							e.ord_compare_func.module,
							e.ord_compare_func.name,
							env.interner,
						)
						if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
							cmp_fn_idx = idx
						}
					} else if e.ord_compare_func.name != 0 {
						if idx, ok := env.func_map[u64(e.ord_compare_func.name)]; ok {
							cmp_fn_idx = idx
						}
					}
					emit_instruction(Wasm_I32_Const{value = i32(cmp_fn_idx)}, buf)
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Set_Eq])},
						buf,
					)
					break
				}
			}

			if module_str == "Result" {
				if name_str == "debug" && len(e.args) == 1 {
					// Result.debug: resolve ok/err debug functions
					ok_debug_fn_idx := 0
					err_debug_fn_idx := 0
					// For now, use the same debug_func for both ok and err
					if e.debug_func.module != base.NO_NAME && e.debug_func.name != 0 {
						mangled := base.mangle_name(
							e.debug_func.module,
							e.debug_func.name,
							env.interner,
						)
						if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
							ok_debug_fn_idx = idx
							err_debug_fn_idx = idx
						}
					} else if e.debug_func.name != 0 {
						if idx, ok := env.func_map[u64(e.debug_func.name)]; ok {
							ok_debug_fn_idx = idx
							err_debug_fn_idx = idx
						}
					}
					emit_instruction(Wasm_I32_Const{value = i32(ok_debug_fn_idx)}, buf)
					emit_instruction(Wasm_I32_Const{value = i32(err_debug_fn_idx)}, buf)
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Result_Debug])},
						buf,
					)
					if ir.ir_expr_wasm_type(e) ==
					   .I64 {emit_instruction(Wasm_I64_Extend_I32_S{}, buf)}
					break
				}
			}

			// Hash trait method: hash(val, _ignored_hasher) -> hasher
			// Dispatches to the appropriate Hash_Write_* runtime function based on
			// the module name (which identifies the Self type).
			if name_str == "hash" && len(e.args) == 2 {
				// Always create a fresh hasher via Hash_Init
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.Hash_Init])},
					buf,
				)
				// Emit the value argument
				emit_expr(e.args[0], buf, env, runtime_indices)

				// Dispatch to appropriate Hash_Write_* based on the module (type)
				write_func: Runtime_Func = .Hash_Write_I64 // default
				if module_str == "Num.I64" ||
				   module_str == "Num.U64" ||
				   module_str == "I64" ||
				   module_str == "U64" {
					write_func = .Hash_Write_I64
				} else if module_str == "Num.I32" ||
				   module_str == "Num.U32" ||
				   module_str == "I32" ||
				   module_str == "U32" {
					write_func = .Hash_Write_I32
				} else if module_str == "Num.I16" ||
				   module_str == "Num.U16" ||
				   module_str == "I16" ||
				   module_str == "U16" {
					write_func = .Hash_Write_I16
				} else if module_str == "Num.I8" ||
				   module_str == "Num.U8" ||
				   module_str == "I8" ||
				   module_str == "U8" {
					write_func = .Hash_Write_I8
				} else if module_str == "Num.F64" || module_str == "F64" {
					write_func = .Hash_Write_F64
				} else if module_str == "Num.F32" || module_str == "F32" {
					// Promote f32 to f64 before hashing
					emit_instruction(Wasm_F64_Promote{}, buf)
					write_func = .Hash_Write_F64
				} else if module_str == "Bool" {
					write_func = .Hash_Write_I8
				} else if module_str == "Str" {
					write_func = .Hash_Write_Str
				} else if module_str == "Bytes" {
					write_func = .Hash_Write_Str
				} else if module_str == "Char" {
					write_func = .Hash_Write_I32
				}
				emit_instruction(Wasm_Call{index = u32(runtime_indices[write_func])}, buf)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				break
			}


		}

		// Check for Display.to_str intrinsic calls (unqualified name)
		if e.callee.module == base.NO_NAME {
			name_str := base.intern_get(env.interner, e.callee.name)
			if name_str == "I64_to_str" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "I32_to_str" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I32_To_Str])},
					buf,
				)
				break
			}
			if name_str == "F64_to_str" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.F64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "Bool_to_str" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.Bool_To_Str])},
					buf,
				)
				break
			}
			if name_str == "Str_to_str" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				break
			}
			if name_str == "I64_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "I32_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I32_To_Str])},
					buf,
				)
				break
			}
			if name_str == "F64_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.F64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "F32_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.F64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "Bool_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.Bool_To_Str])},
					buf,
				)
				break
			}
			if name_str == "Str_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				break
			}
			if name_str == "I8_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "I16_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "U8_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "U16_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "U32_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "U64_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}
			if name_str == "Char_debug" && len(e.args) == 1 {
				emit_expr(e.args[0], buf, env, runtime_indices)
				emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
					buf,
				)
				break
			}

			// Hash trait method: hash(val, _ignored_hasher, ...) -> hasher
			// When trait dispatch is used (e.g., I64.hash(42, Hasher{})),
			// the call is unqualified with name "hash" and extra dispatch args.
			// Creates a fresh hasher, writes the value, returns hasher pointer.
			if name_str == "hash" && len(e.args) >= 2 {
				// Determine the write function from the value's WASM type
				val_type := ir.ir_expr_wasm_type(e.args[1])
				write_func: Runtime_Func = .Hash_Write_I64
				if val_type == .I64 {
					write_func = .Hash_Write_I64
				} else if val_type == .F64 {
					write_func = .Hash_Write_F64
				} else if val_type == .F32 {
					write_func = .Hash_Write_F64
				} else {
					write_func = .Hash_Write_I32
				}

				// Create fresh hasher
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.Hash_Init])},
					buf,
				)
				// Emit the value argument — for trait dispatch, value is args[1]
				emit_expr(e.args[1], buf, env, runtime_indices)
				// Promote f32 to f64 if needed
				if val_type == .F32 {
					emit_instruction(Wasm_F64_Promote{}, buf)
				}
				// Call the appropriate hash write function
				emit_instruction(Wasm_Call{index = u32(runtime_indices[write_func])}, buf)
				// Finalize the hash to get the 64-bit hash value
				emit_instruction(
					Wasm_Call{index = u32(runtime_indices[Runtime_Func.Hash_Finish])},
					buf,
				)
				// Hash_Finish returns i64 directly — no extend needed
				break
			}
		}

		call_idx: int = 0
		if e.callee.module != base.NO_NAME {
			mangled := base.mangle_name(e.callee.module, e.callee.name, env.interner)
			if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
				call_idx = idx
			} else if idx, ok := env.func_map[u64(e.callee.name)]; ok {
				call_idx = idx
			}
		} else if idx, ok := env.func_map[u64(e.callee.name)]; ok {
			call_idx = idx
		}
		// Resolve function type index for polymorphic call coercion
		func_type_idx := -1
		if call_idx >= 0 && call_idx < len(env.func_type_indices) {
			func_type_idx = int(env.func_type_indices[call_idx])
		}
		// Emit args with interleaved coercion so wrap/extend applies to the
		// correct stack position (top of stack = just-emitted arg).
		for i in 0 ..< len(e.args) {
			emit_expr(e.args[i], buf, env, runtime_indices)
			if func_type_idx >= 0 &&
			   func_type_idx < len(env.mod.types) &&
			   i < len(env.mod.types[func_type_idx].params) {
				arg_type := ir.ir_expr_wasm_type(e.args[i])
				coerce_arg_to(buf, arg_type, func_type_idx, i, env)
			}
		}
		emit_instruction(Wasm_Call{index = u32(call_idx)}, buf)
		// Coerce return value to match expression's expected type
		if func_type_idx >= 0 && func_type_idx < len(env.mod.types) {
			expr_type := ir.ir_expr_wasm_type(e)
			coerce_ret_to(buf, func_type_idx, expr_type, env)
		}

	case ^ir.IR_Tail_Call:
		// Check if callee is a local variable (closure pointer) or a named function
		if local_idx, ok := env.local_map[e.callee.name]; ok {

			callee_local := env.tmp_local_base + env.tmp_count
			env.tmp_count += 1
			emit_instruction(Wasm_Local_Set{index = callee_local}, buf)

			// Load env from closure record
			emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
			emit_instruction(
				Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
				buf,
			)

			// Emit arguments after env
			for arg in e.args {
				emit_expr(arg, buf, env, runtime_indices)
			}

			// Load function index from closure record
			emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
			emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

			// Build closure call type: (env i32, args...) -> (result)
			// For tail calls to closures, the result type comes from the
			// continuation's return type, not from ir.IR_Tail_Call (which is Void).
			// Infer it from the argument types: the continuation takes (env, result)
			// and returns the result type.
			closure_params := make([]Wasm_Value_Type, 1 + len(e.args))
			closure_params[0] = .I32
			for idx := 0; idx < len(e.args); idx += 1 {
				closure_params[idx + 1] = ir_wasm_type_to_value_type(
					ir.ir_expr_wasm_type(e.args[idx]),
				)
			}
			// The continuation returns the same type as its result parameter
			has_return := false
			return_value_type := Wasm_Value_Type(.I32)
			if len(e.args) > 0 {
				last_arg_type := ir.ir_expr_wasm_type(e.args[len(e.args) - 1])
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

			emit_instruction(
				Wasm_Call_Indirect {
					type_idx = u32(closure_type_idx),
					table_idx = u32(env.table_idx),
				},
				buf,
			)

			// ir.IR_Tail_Call is in a void-returning context (effectful function),
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
			if e.callee.module != base.NO_NAME {
				mangled := base.mangle_name(e.callee.module, e.callee.name, env.interner)
				if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
					tail_idx = idx
				} else if idx, ok := env.func_map[u64(e.callee.name)]; ok {
					tail_idx = idx
				}
			} else if idx, ok := env.func_map[u64(e.callee.name)]; ok {
				tail_idx = idx
			}
			emit_instruction(Wasm_Return_Call{index = u32(tail_idx)}, buf)
		}
	case ^ir.IR_If:
		emit_expr(e.condition, buf, env, runtime_indices)
		block_type := ir_wasm_type_to_block_type(e.type.wasm_type)
		emit_instruction(Wasm_If{block_type = block_type}, buf)
		emit_expr(e.then_branch, buf, env, runtime_indices)
		emit_instruction(Wasm_Else{}, buf)
		emit_expr(e.else_branch, buf, env, runtime_indices)
		emit_instruction(Wasm_End{}, buf)
	case ^ir.IR_Return:
		emit_expr(e.value, buf, env, runtime_indices)
		emit_instruction(Wasm_Return{}, buf)
	case ^ir.IR_BinOp:
		emit_expr(e.left, buf, env, runtime_indices)
		emit_expr(e.right, buf, env, runtime_indices)
		operand_type := ir_operand_wasm_type(e.left)
		emit_binop(e.op, operand_type, buf)
	case ^ir.IR_Dup:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Dup])}, buf)
		}
	case ^ir.IR_Drop:
		if idx, ok := env.local_map[e.value]; ok {
			type_info, type_ok := env.local_types[e.value]
			if type_ok && type_info.is_heap {
				emit_instruction(Wasm_Local_Get{index = idx}, buf)
				emit_instruction(Wasm_I32_Const{value = 0}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Drop])}, buf)
			}
		}
	case ^ir.IR_Block:
		for stmt, idx in e.statements {
			emit_expr(stmt, buf, env, runtime_indices)
			if idx == len(e.statements) - 1 {continue}
			// Drop the stmt's value if it leaves one on the stack. IR_Assign /
			// IR_Drop net to zero (their emit consumes whatever they push), and
			// Void-typed exprs push nothing — so they need no drop.
			stmt_type := ir.ir_expr_wasm_type(stmt)
			if stmt_type == .Void {continue}
			#partial switch _ in stmt {
			case ^ir.IR_Assign, ^ir.IR_Drop:
				continue
			}
			emit_instruction(Wasm_Drop{}, buf)
		}
	case ^ir.IR_Match:
		match_kind := determine_match_kind(e.arms[:], e.scrutinee)
		block_type := ir_wasm_type_to_block_type(e.type.wasm_type)

		// Check if any arm has a guard — if so, Tag_Union matches can't use br_table
		has_guard := false
		for arm in e.arms {
			if arm.guard != nil {
				has_guard = true
				break
			}
		}

		switch match_kind {
		case .Tag_Union:
			if has_guard {
				// Sequential if-else: guards can fail and fall through,
				// so br_table dispatch is not usable.
				emit_instruction(Wasm_Block{block_type = block_type}, buf)

				emit_expr(e.scrutinee, buf, env, runtime_indices)
				scrutinee_local := env.tmp_local_base + env.tmp_count
				env.tmp_count += 1
				emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

				for arm_idx in 0 ..< len(e.arms) {
					arm := e.arms[arm_idx]
					is_last := arm_idx == len(e.arms) - 1

					if !is_last {
						#partial switch p in arm.pattern {
						case ^ir.IR_Pat_Tag:
							emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
							emit_instruction(Wasm_I32_Load8U{offset = CAMP_TAG_TAG_OFFSET}, buf)
							emit_instruction(Wasm_I32_Const{value = i32(p.tag_index)}, buf)
							emit_instruction(Wasm_I32_Eq{}, buf)
						case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
							emit_instruction(Wasm_I32_Const{value = 1}, buf)
						case ^ir.IR_Pat_Record,
						     ^ir.IR_Pat_Tuple,
						     ^ir.IR_Pat_Bool,
						     ^ir.IR_Pat_Int,
						     ^ir.IR_Pat_String:
							emit_instruction(Wasm_I32_Const{value = 1}, buf)
						}
						emit_instruction(Wasm_If{block_type = .Void}, buf)
					}

					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_Tag:
						for j in 0 ..< len(p.payload) {
							payload_name := p.payload[j]
							emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
							emit_instruction(
								Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + j * 8)},
								buf,
							)
							emit_instruction(Wasm_I32_Add{}, buf)
							wt: base.IR_Wasm_Type = .I32
							if j < len(p.payload_wasm_types) {
								wt = p.payload_wasm_types[j]
							}
							emit_load_for_type(wt, buf)
							if local_idx, ok := env.local_map[payload_name]; ok {
								emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
							} else {
								emit_instruction(Wasm_Drop{}, buf)
							}
						}
					case ^ir.IR_Pat_Var:
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						if local_idx, ok := env.local_map[p.name]; ok {
							emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
						} else {
							emit_instruction(Wasm_Drop{}, buf)
						}
					case ^ir.IR_Pat_Wildcard:
					case ^ir.IR_Pat_Record, ^ir.IR_Pat_Tuple:
					case ^ir.IR_Pat_Bool, ^ir.IR_Pat_Int, ^ir.IR_Pat_String:
					}

					// Guard check: if guard is present, wrap body in conditional
					if arm.guard != nil {
						emit_expr(arm.guard, buf, env, runtime_indices)
						emit_instruction(Wasm_If{block_type = .Void}, buf)
						emit_expr(arm.body, buf, env, runtime_indices)
						emit_instruction(Wasm_Br{label = 1}, buf)
						emit_instruction(Wasm_End{}, buf)
					} else {
						emit_expr(arm.body, buf, env, runtime_indices)
						emit_instruction(Wasm_Br{label = 1}, buf)
					}

					if !is_last {
						emit_instruction(Wasm_End{}, buf)
					}
				}

				emit_instruction(Wasm_Unreachable{}, buf)
				emit_instruction(Wasm_End{}, buf)
			} else {
				// No guards: use br_table for efficient dispatch
				// Standard nested-block dispatch:
				//   block $result(i64) {
				//     block $arm_n-1 { ... block $arm_0 {
				//       load tag; br_table [arm_for_tag_0, ..., arm_for_tag_max] default=catchall
				//     } end arm_0
				//     ;; arm 0's body, then br to $result
				//     end arm_1 ;; arm 1's body, br $result
				//     ...
				//   }
				// targets[tag_value] = arm-index that handles that tag.
				// catchall = wildcard/var arm (or num_arms if there is none).
				num_arms := len(e.arms)

				catchall_arm := -1
				max_tag := -1
				for i in 0 ..< num_arms {
					#partial switch p in e.arms[i].pattern {
					case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
						if catchall_arm < 0 do catchall_arm = i
					case ^ir.IR_Pat_Tag:
						if p.tag_index > max_tag do max_tag = p.tag_index
					case ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Bool,
					     ^ir.IR_Pat_Int,
					     ^ir.IR_Pat_String:
					}
				}

				default_label := u32(num_arms)
				if catchall_arm >= 0 {
					default_label = u32(catchall_arm)
				}

				targets := make([]u32, max_tag + 1)
				for i in 0 ..= max_tag {
					targets[i] = default_label
				}
				for i in 0 ..< num_arms {
					#partial switch p in e.arms[i].pattern {
					case ^ir.IR_Pat_Tag:
						targets[p.tag_index] = u32(i)
					case ^ir.IR_Pat_Wildcard,
					     ^ir.IR_Pat_Var,
					     ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Bool,
					     ^ir.IR_Pat_Int,
					     ^ir.IR_Pat_String:
					}
				}

				scrutinee_local := env.tmp_local_base + env.tmp_count
				env.tmp_count += 1

				// Outer result block (depth grows from here)
				emit_instruction(Wasm_Block{block_type = block_type}, buf)

				// If no catchall, add an extra block that traps when reached
				if catchall_arm < 0 {
					emit_instruction(Wasm_Block{block_type = .Void}, buf)
				}

				// Nested case blocks, outermost first (arm n-1 → arm 0)
				for _ in 0 ..< num_arms {
					emit_instruction(Wasm_Block{block_type = .Void}, buf)
				}

				// Innermost: load tag, dispatch
				emit_expr(e.scrutinee, buf, env, runtime_indices)
				emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)
				emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
				emit_instruction(Wasm_I32_Load8U{offset = CAMP_TAG_TAG_OFFSET}, buf)
				emit_instruction(Wasm_BrTable{targets = targets, default_idx = default_label}, buf)

				// For each arm (innermost first = arm 0), close its block and emit its body.
				// After closing arm_i's block, the br to $result is at label (num_arms - i).
				for arm_idx in 0 ..< num_arms {
					emit_instruction(Wasm_End{}, buf) // close case_arm_idx block

					arm := e.arms[arm_idx]
					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_Tag:
						for j in 0 ..< len(p.payload) {
							payload_name := p.payload[j]
							if local_idx, ok := env.local_map[payload_name]; ok {
								emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
								emit_instruction(
									Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + j * 8)},
									buf,
								)
								emit_instruction(Wasm_I32_Add{}, buf)
								wt: base.IR_Wasm_Type = .I32
								if j < len(p.payload_wasm_types) {
									wt = p.payload_wasm_types[j]
								}
								emit_load_for_type(wt, buf)
								emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
							}
						}
					case ^ir.IR_Pat_Var:
						if local_idx, ok := env.local_map[p.name]; ok {
							emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
							emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
						}
					case ^ir.IR_Pat_Wildcard,
					     ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Bool,
					     ^ir.IR_Pat_Int,
					     ^ir.IR_Pat_String:
					}

					emit_expr(arm.body, buf, env, runtime_indices)
					emit_instruction(Wasm_Br{label = u32(num_arms - arm_idx)}, buf)
				}

				// Optional trap block for non-exhaustive matches
				if catchall_arm < 0 {
					emit_instruction(Wasm_End{}, buf)
					emit_instruction(Wasm_Unreachable{}, buf)
				}

				emit_instruction(Wasm_End{}, buf) // close result block
			}
		case .Bool:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + env.tmp_count
			env.tmp_count += 1
			emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

			for arm_idx in 0 ..< len(e.arms) {
				arm := e.arms[arm_idx]
				is_last := arm_idx == len(e.arms) - 1

				if !is_last {
					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_Bool:
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						emit_instruction(Wasm_I32_Const{value = i32(p.value)}, buf)
						emit_instruction(Wasm_I32_Eq{}, buf)
					case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					case ^ir.IR_Pat_Tag,
					     ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Int,
					     ^ir.IR_Pat_String:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					}
					emit_instruction(Wasm_If{block_type = .Void}, buf)
				}

				#partial switch p in arm.pattern {
				case ^ir.IR_Pat_Var:
					emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
					if local_idx, ok := env.local_map[p.name]; ok {
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					} else {
						emit_instruction(Wasm_Drop{}, buf)
					}
				case ^ir.IR_Pat_Tag,
				     ^ir.IR_Pat_Record,
				     ^ir.IR_Pat_Tuple,
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				if arm.guard != nil {
					emit_expr(arm.guard, buf, env, runtime_indices)
					emit_instruction(Wasm_If{block_type = .Void}, buf)
					emit_expr(arm.body, buf, env, runtime_indices)
					emit_instruction(Wasm_Br{label = 1}, buf)
					emit_instruction(Wasm_End{}, buf)
				} else {
					emit_expr(arm.body, buf, env, runtime_indices)
					emit_instruction(Wasm_Br{label = 1}, buf)
				}

				if !is_last {
					emit_instruction(Wasm_End{}, buf)
				}
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)

		case .Int:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.next_local
			append(&env.locals, Wasm_Local_Decl{count = 1, type = .I64})
			env.next_local += 1
			emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

			for arm_idx in 0 ..< len(e.arms) {
				arm := e.arms[arm_idx]
				is_last := arm_idx == len(e.arms) - 1
				has_guard := arm.guard != nil

				is_catchall_pat := false
				#partial switch _ in arm.pattern {
				case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
					is_catchall_pat = true
				}

				// An arm is a hard catch-all only when its pattern matches
				// everything AND has no guard; a guarded var/wildcard arm
				// still needs an if-wrapper for the guard test.
				needs_pat_wrap := !is_last && !is_catchall_pat
				if needs_pat_wrap {
					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_Int:
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						emit_instruction(Wasm_I64_Const{value = p.value}, buf)
						emit_instruction(Wasm_I64_Eq{}, buf)
					case ^ir.IR_Pat_Tag,
					     ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Bool,
					     ^ir.IR_Pat_String:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					}
					emit_instruction(Wasm_If{block_type = .Void}, buf)
				}

				// Bind the pattern's variables BEFORE evaluating the guard so
				// the guard can reference them.
				#partial switch p in arm.pattern {
				case ^ir.IR_Pat_Var:
					if local_idx, ok := env.local_map[p.name]; ok {
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					}
				case ^ir.IR_Pat_Tag,
				     ^ir.IR_Pat_Record,
				     ^ir.IR_Pat_Tuple,
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				if has_guard {
					emit_expr(arm.guard, buf, env, runtime_indices)
					emit_instruction(Wasm_If{block_type = .Void}, buf)
				}

				// `br label` jumps to the end of the result block. The number
				// of enclosing if-wrappers determines the label depth from
				// the innermost block (the body).
				wrap_depth: u32 = 0
				if needs_pat_wrap do wrap_depth += 1
				if has_guard do wrap_depth += 1
				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = wrap_depth}, buf)

				if has_guard {
					emit_instruction(Wasm_End{}, buf)
				}
				if needs_pat_wrap {
					emit_instruction(Wasm_End{}, buf)
				}

				if is_catchall_pat && !has_guard {break}
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)

		case .String:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + env.tmp_count
			env.tmp_count += 1
			emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

			for arm_idx in 0 ..< len(e.arms) {
				arm := e.arms[arm_idx]
				is_last := arm_idx == len(e.arms) - 1

				if !is_last {
					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_String:
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						str_offset, ok := env.string_offsets[p.string_id]
						if !ok {
							str_offset = 0
						}
						emit_instruction(Wasm_I32_Const{value = i32(str_offset)}, buf)
						emit_instruction(
							Wasm_Call{index = u32(runtime_indices[Runtime_Func.Str_Eq])},
							buf,
						)
					case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					case ^ir.IR_Pat_Tag,
					     ^ir.IR_Pat_Record,
					     ^ir.IR_Pat_Tuple,
					     ^ir.IR_Pat_Bool,
					     ^ir.IR_Pat_Int:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					}
					emit_instruction(Wasm_If{block_type = .Void}, buf)
				}

				#partial switch p in arm.pattern {
				case ^ir.IR_Pat_Var:
					emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
					if local_idx, ok := env.local_map[p.name]; ok {
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					} else {
						emit_instruction(Wasm_Drop{}, buf)
					}
				case ^ir.IR_Pat_Tag,
				     ^ir.IR_Pat_Record,
				     ^ir.IR_Pat_Tuple,
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				if arm.guard != nil {
					emit_expr(arm.guard, buf, env, runtime_indices)
					emit_instruction(Wasm_If{block_type = .Void}, buf)
					emit_expr(arm.body, buf, env, runtime_indices)
					emit_instruction(Wasm_Br{label = 1}, buf)
					emit_instruction(Wasm_End{}, buf)
				} else {
					emit_expr(arm.body, buf, env, runtime_indices)
					emit_instruction(Wasm_Br{label = 1}, buf)
				}

				if !is_last {
					emit_instruction(Wasm_End{}, buf)
				}
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)

		case .Record:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + env.tmp_count
			env.tmp_count += 1
			emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

			for arm_idx in 0 ..< len(e.arms) {
				arm := e.arms[arm_idx]
				#partial switch p in arm.pattern {
				case ^ir.IR_Pat_Record:
					for f in p.fields {
						if local_idx, ok := env.local_map[f.binding]; ok {
							emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
							emit_instruction(
								Wasm_I32_Const {
									value = i32(CAMP_TAG_FIELDS_OFFSET + f.field_index * 8),
								},
								buf,
							)
							emit_instruction(Wasm_I32_Add{}, buf)
							emit_load_for_type(f.wasm_type, buf)
							emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
						}
					}
				case ^ir.IR_Pat_Tuple:
					for el in p.elements {
						if local_idx, ok := env.local_map[el.binding]; ok {
							emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
							emit_instruction(
								Wasm_I32_Const {
									value = i32(CAMP_TAG_FIELDS_OFFSET + el.field_index * 8),
								},
								buf,
							)
							emit_instruction(Wasm_I32_Add{}, buf)
							emit_load_for_type(el.wasm_type, buf)
							emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
						}
					}
				case ^ir.IR_Pat_Var:
					if local_idx, ok := env.local_map[p.name]; ok {
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					}
				case ^ir.IR_Pat_Tag,
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}
				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = 0}, buf)
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)
		}

	case ^ir.IR_Construct_Tag:
		num_fields := len(e.payload)
		// scan_size is the total field count (used for dealloc size and the drop
		// loop bound); scalar_mask marks which fields drop must NOT recurse into.
		// A field is a heap pointer only if it is an i32 that is_heap — i64/f64
		// scalars, bools, and function indices are i32-or-i64 but not pointers.
		scan_size := num_fields
		scalar_mask := 0
		for p, i in e.payload {
			heap_ptr := ir.ir_expr_wasm_type(p) == .I32 && ir.ir_expr_is_heap(p)
			if i < 8 && !heap_ptr {
				scalar_mask |= 1 << uint(i)
			}
		}
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
		// Use a unique tmp slot so a nested IR_Construct_Tag in a payload (e.g.
		// the Nil/Cons tail of a Cons cell) doesn't clobber this cell's pointer
		// between alloc and the field stores. IR_Construct_Record already does
		// this; tag construction had the same hazard.
		tmp_local_idx := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1

		if e.reuse_addr != ir.NO_REUSE_ADDR {
			// Perceus inline reuse: decrement reuse_addr refcount, reuse if zero + big enough
			reuse_local, reuse_ok := env.local_map[e.reuse_addr]
			if reuse_ok {
				rc_local := env.tmp_local_base + env.tmp_count
				env.tmp_count += 1

				// Load refcount, decrement, store back
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)
				emit_instruction(Wasm_I32_Const{value = 1}, buf)
				emit_instruction(Wasm_I32_Sub{}, buf)
				emit_instruction(Wasm_Local_Tee{index = rc_local}, buf)
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

				// if refcount == 0
				emit_instruction(Wasm_Local_Get{index = rc_local}, buf)
				emit_instruction(Wasm_I32_Const{value = 0}, buf)
				emit_instruction(Wasm_I32_Eq{}, buf)
				emit_instruction(Wasm_If{block_type = .I32}, buf)
				// Check scan_size >= num_fields for safe reuse
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(
					Wasm_I32_Load8U{align = 0, offset = CAMP_TAG_SCAN_SIZE_OFFSET},
					buf,
				)
				emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
				emit_instruction(Wasm_I32_Ge_S{}, buf)
				emit_instruction(Wasm_If{block_type = .I32}, buf)
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_Else{}, buf)
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_End{}, buf)
				emit_instruction(Wasm_Else{}, buf)
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_End{}, buf)

				emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
			} else {
				// Fallback: reuse_addr not in local_map, fresh alloc
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
			}
		} else {
			emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
			emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(e.tag_index)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(scan_size)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(scalar_mask)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCALAR_MASK_OFFSET}, buf)

		for i in 0 ..< len(e.payload) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(e.payload[i], buf, env, runtime_indices)
			emit_store_for_type(ir.ir_expr_wasm_type(e.payload[i]), buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^ir.IR_Construct_Record:
		num_fields := len(e.fields)
		// See IR_Construct_Tag: scan_size is the field count, scalar_mask marks the
		// fields drop must not dereference (everything that is not a heap pointer).
		scan_size := num_fields
		scalar_mask := 0
		for f, i in e.fields {
			heap_ptr := ir.ir_expr_wasm_type(f.value) == .I32 && ir.ir_expr_is_heap(f.value)
			if i < 8 && !heap_ptr {
				scalar_mask |= 1 << uint(i)
			}
		}
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
		// Use a unique tmp slot so nested IR_Construct_Record (e.g. closure
		// records containing env records) don't clobber the outer record's
		// pointer between alloc and field stores.
		tmp_local_idx := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1

		if e.reuse_addr != ir.NO_REUSE_ADDR {
			// Perceus inline reuse: decrement reuse_addr refcount, reuse if zero + big enough
			reuse_local, reuse_ok := env.local_map[e.reuse_addr]
			if reuse_ok {
				rc_local := env.tmp_local_base + env.tmp_count
				env.tmp_count += 1

				// Load refcount, decrement, store back
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)
				emit_instruction(Wasm_I32_Const{value = 1}, buf)
				emit_instruction(Wasm_I32_Sub{}, buf)
				emit_instruction(Wasm_Local_Tee{index = rc_local}, buf)
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

				// if refcount == 0
				emit_instruction(Wasm_Local_Get{index = rc_local}, buf)
				emit_instruction(Wasm_I32_Const{value = 0}, buf)
				emit_instruction(Wasm_I32_Eq{}, buf)
				emit_instruction(Wasm_If{block_type = .I32}, buf)
				// Check scan_size >= num_fields for safe reuse
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(
					Wasm_I32_Load8U{align = 0, offset = CAMP_TAG_SCAN_SIZE_OFFSET},
					buf,
				)
				emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
				emit_instruction(Wasm_I32_Ge_S{}, buf)
				emit_instruction(Wasm_If{block_type = .I32}, buf)
				emit_instruction(Wasm_Local_Get{index = reuse_local}, buf)
				emit_instruction(Wasm_Else{}, buf)
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_End{}, buf)
				emit_instruction(Wasm_Else{}, buf)
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_End{}, buf)

				emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
			} else {
				// Fallback: reuse_addr not in local_map, fresh alloc
				emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
				emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
			}
		} else {
			emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
			emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 0xFF}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(scan_size)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(scalar_mask)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCALAR_MASK_OFFSET}, buf)

		// Pre-compute interned "fn_idx" name for decl-to-wasm translation
		fn_idx_name := env.interner != nil ? base.intern(env.interner, "fn_idx") : 0
		for i in 0 ..< len(e.fields) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)

			// Translate "fn_idx" field from decls index to WASM function index
			if e.fields[i].name == fn_idx_name {
				if lit, ok := e.fields[i].value.(^ir.IR_Literal_Int); ok {
					if wasm_idx, found := env.decl_to_wasm_fn_idx[int(lit.value)]; found {
						emit_instruction(Wasm_I32_Const{value = i32(wasm_idx)}, buf)
						emit_store_for_type(ir.ir_expr_wasm_type(e.fields[i].value), buf)
						continue
					}
				}
			}
			emit_expr(e.fields[i].value, buf, env, runtime_indices)
			emit_store_for_type(ir.ir_expr_wasm_type(e.fields[i].value), buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^ir.IR_Construct_Tuple:
		num_fields := len(e.elements)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
		tmp_local_idx := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)
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

		for i in 0 ..< len(e.elements) {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 8)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(e.elements[i], buf, env, runtime_indices)
			emit_store_for_type(ir.ir_expr_wasm_type(e.elements[i]), buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
	case ^ir.IR_Field_Access:
		emit_expr(e.record, buf, env, runtime_indices)
		emit_instruction(
			Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + e.field_index * 8)},
			buf,
		)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_load_for_type(e.type.wasm_type, buf)
	case ^ir.IR_Method_Call:
		// Method calls should be resolved by monomorphization.
		// If one reaches codegen, it's a compiler bug — emit a runtime error.
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Exit])}, buf)
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^ir.IR_Handle:
		is_sched := false
		for eff in e.effects {
			if ir.is_scheduler_effect_by_ids(
				eff.name,
				env.async_id,
				env.spawn_id,
				env.parallel_id,
				env.file_id,
				env.console_id,
				env.time_id,
				env.interner,
			) {
				is_sched = true
				break
			}
		}
		if is_sched {
			// Allocate scope_id for structured concurrency cleanup
			scope_id := env.next_scope_id
			env.next_scope_id += 1

			// Emit body — ir.IR_Perform nodes inside will call scheduler functions
			emit_expr(e.body, buf, env, runtime_indices)

			// On handler exit: iterate handle table, cancel all Pending handles with this scope_id
			// This implements structured concurrency (D10 Phase 1)
			handle_table_base :=
				SCHED_BASE +
				SCHED_WORKER_COUNT_SIZE +
				SCHED_SPINNING_SIZE +
				SCHED_NOTIFICATION_SIZE
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
			emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, buf)
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
			// User-defined effect: just emit the body.
			// effect_lower transforms handle blocks into let/closure/store chains,
			// but in the rare case an ir.IR_Handle survives, emit the body.
			emit_expr(e.body, buf, env, runtime_indices)
		}
	case ^ir.IR_Perform:
		if ir.is_scheduler_effect_by_ids(
			e.effect.name,
			env.async_id,
			env.spawn_id,
			env.parallel_id,
			env.file_id,
			env.console_id,
			env.time_id,
			env.interner,
		) {
			effect_str := base.intern_get(env.interner, e.effect.name)
			op_str := base.intern_get(env.interner, e.op)

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
						emit_instruction(
							Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
							buf,
						)

						// env_ptr = closure[CAMP_TAG_FIELDS_OFFSET + 8]
						emit_instruction(Wasm_Local_Get{index = thunk_local}, buf)
						emit_instruction(
							Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
							buf,
						)

						// scope_id from enclosing handler (use 0 as default if no scope tracking)
						emit_instruction(Wasm_I32_Const{value = 0}, buf)

						emit_instruction(
							Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Spawn])},
							buf,
						)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
				} else if op_str == "join!" {
					// camp_sched_join(handle_id) -> result_value (i32)
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Join])},
						buf,
					)
					// camp_sched_join returns i32, but the perform type may be i64
					if e.type.wasm_type == .I64 {
						emit_instruction(Wasm_I64_Extend_I32_S{}, buf)
					}
				} else if op_str == "yield!" {
					// camp_sched_yield() -> void
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Yield])},
						buf,
					)
				} else if op_str == "cancel!" {
					// camp_sched_cancel(handle_id) -> void
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Cancel])},
						buf,
					)
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
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Current_Task])},
						buf,
					)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Timer_Insert])},
						buf,
					)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else if effect_str == "File!" ||
			   effect_str == "Console!" ||
			   effect_str == "File" ||
			   effect_str == "Console" {
				// I/O effects use camp_sched_block_io for suspension
				if op_str == "read!" || op_str == "readln!" {
					// Simplified: call block_io with placeholder pollable
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Current_Task])},
						buf,
					)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Block_IO])},
						buf,
					)
				} else if op_str == "println!" || op_str == "print!" {
					// println!/print! take a Str arg and write to stdout via fd_write.
					// If the argument is not already a Str (e.g. I64, F64), convert it.
					if len(e.args) >= 1 {
						emit_expr(e.args[0], buf, env, runtime_indices)
						arg_type := ir.ir_expr_wasm_type(e.args[0])
						if arg_type == .I64 {
							emit_instruction(
								Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])},
								buf,
							)
						} else if arg_type == .F64 {
							emit_instruction(
								Wasm_Call{index = u32(runtime_indices[Runtime_Func.F64_To_Str])},
								buf,
							)
						} else if arg_type == .I32 || arg_type == .Funcref {
							// Assume already a Str pointer; call I32_To_Str as a fallback
							// for non-string i32 values (Bool, etc.)
						}
					} else {
						emit_instruction(Wasm_I32_Const{value = 0}, buf)
					}
					// Build iovs at scratch 4096: [data_ptr, data_len]
					// str_ptr is on the stack; save to temp local
					emit_instruction(
						Wasm_Local_Set{index = u32(env.tmp_local_base + env.tmp_count)},
						buf,
					)
					env.tmp_count += 1
					str_local := env.tmp_local_base + env.tmp_count - 1

					emit_instruction(Wasm_I32_Const{value = 4096}, buf)
					emit_instruction(Wasm_Local_Get{index = str_local}, buf)
					emit_instruction(Wasm_I32_Const{value = 4}, buf)
					emit_instruction(Wasm_I32_Add{}, buf)
					emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

					emit_instruction(Wasm_I32_Const{value = 4100}, buf)
					emit_instruction(Wasm_Local_Get{index = str_local}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
					emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

					emit_instruction(Wasm_I32_Const{value = 1}, buf)
					emit_instruction(Wasm_I32_Const{value = 4096}, buf)
					emit_instruction(Wasm_I32_Const{value = 1}, buf)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(Wasm_Call{index = u32(1)}, buf) // fd_write import
					emit_instruction(Wasm_Drop{}, buf)
					if op_str == "println!" {
						// Append a trailing newline. Scratch: byte at 4104,
						// iovec {ptr=4104, len=1} at 4108/4112.
						emit_instruction(Wasm_I32_Const{value = 4104}, buf)
						emit_instruction(Wasm_I32_Const{value = 10}, buf) // '\n'
						emit_instruction(Wasm_I32_Store8{offset = 0}, buf)
						emit_instruction(Wasm_I32_Const{value = 4108}, buf)
						emit_instruction(Wasm_I32_Const{value = 4104}, buf)
						emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
						emit_instruction(Wasm_I32_Const{value = 4112}, buf)
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
						emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
						emit_instruction(Wasm_I32_Const{value = 1}, buf) // fd=stdout
						emit_instruction(Wasm_I32_Const{value = 4108}, buf) // iovs
						emit_instruction(Wasm_I32_Const{value = 1}, buf) // iovs_len
						emit_instruction(Wasm_I32_Const{value = 0}, buf) // nwritten
						emit_instruction(Wasm_Call{index = u32(1)}, buf) // fd_write
						emit_instruction(Wasm_Drop{}, buf)
					}
					// Push Unit return value so the enclosing Let can consume it
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
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
				if op_str == "map!" && len(e.args) >= 2 {
					// map!(fn, items) -> camp_parallel_map(fn_idx, fn_env, items_ptr, items_len, chunk_size)
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_Map])},
						buf,
					)
				} else if op_str == "reduce!" && len(e.args) >= 3 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_expr(e.args[2], buf, env, runtime_indices)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_Reduce])},
						buf,
					)
				} else if op_str == "any!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_Any])},
						buf,
					)
				} else if op_str == "all!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_All])},
						buf,
					)
				} else if op_str == "filter!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_Filter])},
						buf,
					)
				} else if op_str == "for_each!" && len(e.args) >= 2 {
					fn_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[0], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = fn_local}, buf)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = fn_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					items_local := env.tmp_local_base + env.tmp_count; env.tmp_count += 1
					emit_expr(e.args[1], buf, env, runtime_indices)
					emit_instruction(Wasm_Local_Set{index = items_local}, buf)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)},
						buf,
					)
					emit_instruction(Wasm_Local_Get{index = items_local}, buf)
					emit_instruction(
						Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)},
						buf,
					)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Parallel_For_Each])},
						buf,
					)
				} else {
					emit_instruction(Wasm_Unreachable{}, buf)
				}
			} else {
				emit_instruction(Wasm_Unreachable{}, buf)
			}
		} else {
			// User-defined effect perform: defensive fallback.
			// effect_lower transforms most performs into ir.IR_Closure_Call,
			// but if a perform survives, emit args and exit with unhandled effect.
			for arg in e.args {
				emit_expr(arg, buf, env, runtime_indices)
			}
			emit_instruction(Wasm_I32_Const{value = 1}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Exit])}, buf)
			emit_instruction(Wasm_Unreachable{}, buf)
		}
	case ^ir.IR_Resume:
		resume_local := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1
		fn_idx_local := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1

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

		emit_instruction(
			Wasm_Call_Indirect{type_idx = u32(resume_type_idx), table_idx = u32(env.table_idx)},
			buf,
		)
	case ^ir.IR_Closure:
		num_fields := len(e.params) + 2
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)

		tmp_local_idx := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1
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
		if e.is_self_referential {
			// Self-referential closure: store the closure pointer as its own env field.
			// This makes _cenv = closure_pointer, enabling recursive calls.
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		} else {
			emit_expr(e.env, buf, env, runtime_indices)
		}
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)

	case ^ir.IR_Closure_Call:
		emit_expr(e.callee, buf, env, runtime_indices)

		callee_local := env.tmp_local_base + env.tmp_count
		env.tmp_count += 1
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
			closure_params[idx + 1] = ir_wasm_type_to_value_type(ir.ir_expr_wasm_type(e.args[idx]))
		}
		closure_results: []Wasm_Value_Type
		if e.type.wasm_type != .Void {
			closure_results = make([]Wasm_Value_Type, 1)
			closure_results[0] = ir_wasm_type_to_value_type(e.type.wasm_type)
		} else {
			closure_results = make([]Wasm_Value_Type, 0)
		}
		closure_type_idx := get_or_create_type(env, closure_params, closure_results)
		delete(closure_params)
		delete(closure_results)

		emit_instruction(
			Wasm_Call_Indirect{type_idx = u32(closure_type_idx), table_idx = u32(env.table_idx)},
			buf,
		)

	case ^ir.IR_Crash:
		emit_expr(e.message, buf, env, runtime_indices)
		emit_instruction(Wasm_Drop{}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Exit])}, buf)
		// camp_exit never returns; mark the stack as polymorphic so the
		// validator accepts whatever shape the enclosing context expects.
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^ir.IR_I32_Load:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(e.offset)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
	case ^ir.IR_I32_Store:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(e.offset)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
	case ^ir.IR_Atomic_Load:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_atomic_load(e.width, u32(e.offset), buf)
	case ^ir.IR_Atomic_Store:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_store(e.width, u32(e.offset), buf)
	case ^ir.IR_Atomic_RMW:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.value, buf, env, runtime_indices)
		emit_atomic_rmw(e.op, e.width, u32(e.offset), buf)
	case ^ir.IR_Atomic_Fence:
		emit_instruction(Wasm_Atomic_Fence{}, buf)
	case ^ir.IR_Wait:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.expected, buf, env, runtime_indices)
		emit_expr(e.timeout, buf, env, runtime_indices)
		if e.width == .B8 {
			emit_instruction(
				Wasm_Atomic_Mem{op = .Wait64, width = .I64, align = 3, offset = u32(e.offset)},
				buf,
			)
		} else {
			emit_instruction(
				Wasm_Atomic_Mem{op = .Wait32, width = .I32, align = 2, offset = u32(e.offset)},
				buf,
			)
		}
	case ^ir.IR_Notify:
		emit_expr(e.base, buf, env, runtime_indices)
		emit_expr(e.count, buf, env, runtime_indices)
		emit_instruction(
			Wasm_Atomic_Mem{op = .Notify, width = .I32, align = 2, offset = u32(e.offset)},
			buf,
		)
	case ^ir.IR_Expr_Nominal_Construct:
		// Newtypes are erased at runtime — emit the payload value directly.
		// Simple wrap (variant == 0, single payload): just emit the payload.
		// Qualified variant or multi-payload: emit unreachable (not yet implemented).
		if e.variant == 0 && len(e.payload) == 1 {
			emit_expr(e.payload[0], buf, env, runtime_indices)
			return
		}
		emit_instruction(Wasm_Unreachable{}, buf)
	}
}

emit_binop :: proc(op: ir.IR_BinOp_Kind, operand_type: base.IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Add:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Add{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Add{}, buf)
		} else {
			emit_instruction(Wasm_I64_Add{}, buf)
		}
	case .Sub:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Sub{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Sub{}, buf)
		} else {
			emit_instruction(Wasm_I64_Sub{}, buf)
		}
	case .Mul:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Mul{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Mul{}, buf)
		} else {
			emit_instruction(Wasm_I64_Mul{}, buf)
		}
	case .Div:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Div_S{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Div{}, buf)
		} else {
			emit_instruction(Wasm_I64_Div_S{}, buf)
		}
	case .Mod:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Rem_S{}, buf)
		} else {
			emit_instruction(Wasm_I64_Rem_S{}, buf)
		}
	case .Exp:
		emit_instruction(Wasm_Unreachable{}, buf)
	case .Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Eq{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Eq{}, buf)
		} else {
			emit_instruction(Wasm_I32_Eq{}, buf)
		}
	case .Ne:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ne{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Ne{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ne{}, buf)
		}
	case .Lt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Lt_S{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Lt{}, buf)
		} else {
			emit_instruction(Wasm_I32_Lt_S{}, buf)
		}
	case .Gt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Gt_S{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Gt{}, buf)
		} else {
			emit_instruction(Wasm_I32_Gt_S{}, buf)
		}
	case .Le:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Le_S{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Le{}, buf)
		} else {
			emit_instruction(Wasm_I32_Le_S{}, buf)
		}
	case .Ge:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ge_S{}, buf)
		} else if operand_type == .F64 {
			emit_instruction(Wasm_F64_Ge{}, buf)
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
	case .Shl:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Shl{}, buf)
		} else {
			emit_instruction(Wasm_I64_Shl{}, buf)
		}
	case .Shr:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Shr_S{}, buf)
		} else {
			emit_instruction(Wasm_I64_Shr_S{}, buf)
		}
	}
}

ir_operand_wasm_type :: proc(expr: ir.IR_Expr) -> base.IR_Wasm_Type {
	if expr == nil do return .I32
	#partial switch e in expr {
	case ^ir.IR_Literal_Int:
		return e.type.wasm_type
	case ^ir.IR_Literal_Float:
		return e.type.wasm_type
	case ^ir.IR_Literal_Bool:
		return .I32
	case ^ir.IR_Literal_String:
		return .I32
	case ^ir.IR_Var:
		return e.type.wasm_type
	case ^ir.IR_BinOp:
		return e.type.wasm_type
	case ^ir.IR_Assign:
		return e.type.wasm_type
	case ^ir.IR_Loop:
		return e.type.wasm_type
	case ^ir.IR_Call:
		return e.type.wasm_type

	case ^ir.IR_If:
		return e.type.wasm_type
	case ^ir.IR_Closure_Call:
		return e.type.wasm_type
	case ^ir.IR_Resume:
		return e.type.wasm_type
	case ^ir.IR_Field_Access:
		return e.type.wasm_type
	case ^ir.IR_Construct_Tag:
		return .I32
	case ^ir.IR_Construct_Record:
		return .I32
	case ^ir.IR_Construct_Tuple:
		return .I32
	case ^ir.IR_Closure:
		return .I32
	case ^ir.IR_Atomic_Load:
		return .I32
	case ^ir.IR_Atomic_RMW:
		return .I32
	case ^ir.IR_Wait:
		return .I32
	case ^ir.IR_Notify:
		return .I32
	case ^ir.IR_Let:
		return ir_operand_wasm_type(e.body)
	case ^ir.IR_Tail_Call:
		return .Void
	case ^ir.IR_Match:
		return e.type.wasm_type
	case ^ir.IR_Method_Call:
		return e.type.wasm_type
	case ^ir.IR_Handle:
		return e.type.wasm_type
	case ^ir.IR_Perform:
		return e.type.wasm_type
	case ^ir.IR_Block:
		return e.type.wasm_type
	case ^ir.IR_Dup:
		return .I32
	case ^ir.IR_Drop,
	     ^ir.IR_Return,
	     ^ir.IR_Crash,
	     ^ir.IR_I32_Store,
	     ^ir.IR_Atomic_Store,
	     ^ir.IR_Atomic_Fence:
		return .Void
	case ^ir.IR_Expr_Nominal_Construct, ^ir.IR_I32_Load:
		return .I32
	}
	return .I32
}


emit_store_for_type :: proc(wasm_type: base.IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch wasm_type {
	case .I64:
		emit_instruction(Wasm_I64_Store{align = 3, offset = 0}, buf)
	case .F64:
		emit_instruction(Wasm_F64_Store{align = 3, offset = 0}, buf)
	case .I32, .F32, .Funcref, .Void:
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
	}
}

emit_load_for_type :: proc(wasm_type: base.IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch wasm_type {
	case .I64:
		emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, buf)
	case .F64:
		emit_instruction(Wasm_F64_Load{align = 3, offset = 0}, buf)
	case .I32, .F32, .Funcref, .Void:
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
	}
}

emit_handler_into_evidence :: proc(
	buf: ^[dynamic]u8,
	env: ^Codegen_Env,
	ev_local_idx: int,
	slot_offset: int,
	fn_idx: int,
	runtime_indices: []int,
) {
	// Save the evidence record pointer first
	emit_instruction(Wasm_Local_Get{index = u32(ev_local_idx)}, buf)

	// Allocate closure: size = CAMP_TAG_HEADER_SIZE(8) + 2*8 = 24
	emit_instruction(Wasm_I32_Const{value = 24}, buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)

	tmp := env.tmp_local_base + env.tmp_count
	env.tmp_count += 1
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
	emit_instruction(Wasm_I32_Add{}, buf) // address = ev_ptr + slot_offset
	emit_instruction(Wasm_Local_Get{index = u32(tmp)}, buf) // value = closure_ptr
	emit_store_for_type(.I32, buf) // store closure_ptr at [ev_ptr + slot_offset]
}

emit_throw_handler_fn :: proc(
	env: ^Codegen_Env,
	runtime_indices: []int,
	throw_err_msg_offset: u32,
	throw_err_suffix_offset: u32,
) -> (
	int,
	Wasm_Code,
) {
	// Handler type: (i32=env, i32=err_arg, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I64},
	)
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Allocate a local to hold the tag-as-string pointer
	// locals: 0=env, 1=err_arg, 2=resume, 3=ev, 4=tag_str_ptr
	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}

	// Write "Error: unhandled exception (tag=" to stderr
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(throw_err_msg_offset)}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(len("Error: unhandled exception (tag="))}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_I32_Const{value = 2}, &buf) // fd=2 (stderr)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf) // iovs
	emit_instruction(Wasm_I32_Const{value = 1}, &buf) // iovs_len
	emit_instruction(Wasm_I32_Const{value = 0}, &buf) // nwritten
	emit_instruction(Wasm_Call{index = 1}, &buf) // fd_write
	emit_instruction(Wasm_Drop{}, &buf)

	// Convert tag value (local 1 = err_arg) to string via I64_To_Str
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // err_arg (i32)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf) // sign-extend to i64
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.I64_To_Str])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // store tag_str_ptr in local 4

	// Print the tag string to stderr using Print_Err(str_ptr+4, len)
	// String layout: [len:4][data...], so data starts at ptr+4
	emit_instruction(Wasm_Local_Get{index = 4}, &buf) // tag_str_ptr
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // data_ptr = tag_str_ptr + 4
	emit_instruction(Wasm_Local_Get{index = 4}, &buf) // tag_str_ptr
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // len = [tag_str_ptr]
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Print_Err])}, &buf)

	// Write ")\n" to stderr
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(throw_err_suffix_offset)}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(len(")\n"))}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Call{index = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// proc_exit(1)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Exit])}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	code := Wasm_Code {
		locals = locals,
		body   = copy_dynamic_bytes(buf),
	}
	delete(buf)

	return handler_fn_idx, code
}

emit_console_println_handler_fn :: proc(env: ^Codegen_Env, cont_fn_idx: int) -> (int, Wasm_Code) {
	// Handler type: (i32=env, i32=str_arg, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I64},
	)
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MINOR)

	// Write string to stdout via fd_write(fd=1, ...)
	// str_arg (local 1) points to [len: i32][data: bytes]
	// Build iovs at scratch 4096: [data_ptr, data_len]
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // str_arg
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // data_ptr = str_arg + 4
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // str_arg
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // len
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// fd_write(fd=1, iovs=4096, iovs_len=1, nwritten=0)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Call{index = 1}, &buf) // fd_write import index 1
	emit_instruction(Wasm_Drop{}, &buf) // ignore errno

	// Call continuation with Unit
	emit_instruction(Wasm_I32_Const{value = 0}, &buf) // env = null
	emit_instruction(Wasm_I64_Const{value = 0}, &buf) // result = Unit
	emit_instruction(Wasm_Call{index = u32(cont_fn_idx)}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf) // continuation never returns
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	code := Wasm_Code {
		locals = locals,
		body   = copy_dynamic_bytes(buf),
	}
	delete(buf)

	return handler_fn_idx, code
}

SCAN_BUF_BASE :: 4200
SCAN_BUF_SIZE :: 1024

emit_console_readln_handler_fn :: proc(
	env: ^Codegen_Env,
	runtime_indices: []int,
) -> (
	int,
	Wasm_Code,
) {
	// Handler type: (i32=env, i32=resume, i32=ev) -> i32 (Str)
	handler_type_idx := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32},
		[]Wasm_Value_Type{.I32},
	)
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Read from stdin via fd_read(fd=0, ...)
	// Build iovs at scratch 4096: [buffer_ptr, buffer_len]
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = SCAN_BUF_BASE}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_I32_Const{value = SCAN_BUF_SIZE}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// fd_read(fd=0, iovs=4096, iovs_len=1, nread=4108)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf) // fd=0 (stdin)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf) // iovs
	emit_instruction(Wasm_I32_Const{value = 1}, &buf) // iovs_len
	emit_instruction(Wasm_I32_Const{value = 4108}, &buf) // nread ptr
	emit_instruction(Wasm_Call{index = WASI_IMPORT_FD_READ}, &buf)
	emit_instruction(Wasm_Drop{}, &buf) // ignore errno

	// Allocate Camp string: alloc(nread + 4)
	emit_instruction(Wasm_I32_Const{value = 4108}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // nread
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf) // save nread for later copy
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // size = nread + 4
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // str_ptr = alloc(nread + 4)

	// Store len at [str_ptr]
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf) // nread
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Memory copy data from SCAN_BUF to str_ptr + 4
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // dest = str_ptr + 4
	emit_instruction(Wasm_I32_Const{value = SCAN_BUF_BASE}, &buf) // src = SCAN_BUF
	emit_instruction(Wasm_Local_Get{index = 3}, &buf) // size = nread
	emit_instruction(Wasm_Memory_Copy{}, &buf)

	// Return str_ptr
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // local 3: nread
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // local 4: str_ptr
	code := Wasm_Code {
		locals = locals,
		body   = copy_dynamic_bytes(buf),
	}
	delete(buf)

	return handler_fn_idx, code
}

emit_unhandled_effect_handler_fn :: proc(
	env: ^Codegen_Env,
	eff_name: string,
	runtime_indices: []int,
) -> (
	int,
	Wasm_Code,
) {
	// Generic handler for unhandled effects: exit(1)
	// Handler type: (i32=env, i32..=op_args, i32=resume, i32=ev) -> i64
	handler_type_idx := get_or_create_type(
		env,
		[]Wasm_Value_Type{.I32, .I32, .I32, .I32},
		[]Wasm_Value_Type{.I64},
	)
	handler_fn_idx := add_function(env, handler_type_idx)

	for len(env.func_type_indices) <= handler_fn_idx {
		append(&env.func_type_indices, 0)
	}
	env.func_type_indices[handler_fn_idx] = u32(handler_type_idx)

	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MINOR)

	// Call camp_exit(1) — unhandled effect
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Exit])}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)
	code := Wasm_Code {
		locals = locals,
		body   = copy_dynamic_bytes(buf),
	}
	delete(buf)

	return handler_fn_idx, code
}

resolve_call_idx :: proc(callee: base.Canonical_Name, env: ^Codegen_Env) -> int {
	if callee.module != base.NO_NAME {
		mangled := base.mangle_name(callee.module, callee.name, env.interner)
		if idx, ok := env.func_map[base.hash_string(mangled)]; ok {
			return idx
		}
	}
	if idx, ok := env.func_map[u64(callee.name)]; ok {
		return idx
	}
	return 0
}

emit_atomic_load :: proc(width: ir.Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	#partial switch width {
	case .B1:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Load, width = .I32_8, align = 0, offset = offset},
			buf,
		)
	case .B2:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Load, width = .I32_16, align = 1, offset = offset},
			buf,
		)
	case .B4:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = offset},
			buf,
		)
	case .B8:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Load, width = .I64, align = 3, offset = offset},
			buf,
		)
	}
}

emit_atomic_store :: proc(width: ir.Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	#partial switch width {
	case .B1:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Store, width = .I32_8, align = 0, offset = offset},
			buf,
		)
	case .B2:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Store, width = .I32_16, align = 1, offset = offset},
			buf,
		)
	case .B4:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Store, width = .I32, align = 2, offset = offset},
			buf,
		)
	case .B8:
		emit_instruction(
			Wasm_Atomic_Mem{op = .Store, width = .I64, align = 3, offset = offset},
			buf,
		)
	}
}

emit_atomic_rmw :: proc(op: ir.Atomic_Op, width: ir.Atomic_Width, offset: u32, buf: ^[dynamic]u8) {
	wasm_op := Wasm_Atomic_Op(0)
	switch op {
	case .Add:
		wasm_op = .RMW_Add
	case .Sub:
		wasm_op = .RMW_Sub
	case .And:
		wasm_op = .RMW_And
	case .Or:
		wasm_op = .RMW_Or
	case .Xor:
		wasm_op = .RMW_Xor
	case .Xchg:
		wasm_op = .RMW_Xchg
	case .CmpXchg:
		wasm_op = .RMW_CmpXchg
	}
	wasm_width := Wasm_Atomic_Width(0)
	#partial switch width {
	case .B1:
		wasm_width = .I32_8
	case .B2:
		wasm_width = .I32_16
	case .B4:
		wasm_width = .I32
	case .B8:
		wasm_width = .I64
	}
	align := u32(0)
	#partial switch width {
	case .B1:
		align = 0
	case .B2:
		align = 1
	case .B4:
		align = 2
	case .B8:
		align = 3
	}
	emit_instruction(
		Wasm_Atomic_Mem{op = wasm_op, width = wasm_width, align = align, offset = offset},
		buf,
	)
}

// emit_box_i64_key boxes an I64 value into a 12-byte heap cell and leaves
// the i32 pointer on the stack. The cell layout is:
//   offset 0: refcount (i32, value 1)
//   offset 4: i64 value
// The key expression is emitted inline between the alloc and the i64 store,
// so the caller passes a closure that emits the key.
emit_box_i64_key :: proc(
	key_expr: ir.IR_Expr,
	buf: ^[dynamic]u8,
	env: ^Codegen_Env,
	runtime_indices: []int,
) {
	alloc_idx := u32(runtime_indices[Runtime_Func.Alloc])
	tmp_local := env.tmp_local_base + env.tmp_count
	env.tmp_count += 1

	// Allocate 12-byte cell
	emit_instruction(Wasm_I32_Const{value = 12}, buf)
	emit_instruction(Wasm_Call{index = alloc_idx}, buf)
	emit_instruction(Wasm_Local_Tee{index = tmp_local}, buf)
	// Store refcount = 1 at offset 0
	emit_instruction(Wasm_I32_Const{value = 1}, buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
	// Push pointer, emit key, store i64 at offset 4
	emit_instruction(Wasm_Local_Get{index = tmp_local}, buf)
	emit_expr(key_expr, buf, env, runtime_indices)
	emit_instruction(Wasm_I64_Store{align = 2, offset = 4}, buf)
	// Push the i32 pointer result
	emit_instruction(Wasm_Local_Get{index = tmp_local}, buf)
}

// get_or_create_i64_trampoline returns the function index of a trampoline
// compare function for the given real I64 compare function. For I64 keys,
// this always returns the pre-registered I64_Trampoline runtime function.
get_or_create_i64_trampoline :: proc(env: ^Codegen_Env, real_cmp_fn_idx: int) -> int {
	// For the built-in I64_Compare, use the pre-registered I64_Trampoline
	return env.i64_trampoline_cache[real_cmp_fn_idx]
}


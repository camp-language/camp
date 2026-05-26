package codegen

import "camp:base"
import "camp:ir"

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
		for arm in e.arms {
			collect_pattern_locals(arm.pattern, locals)
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

collect_pattern_locals :: proc(pattern: ir.IR_Pattern, locals: ^map[base.Intern_ID]base.IR_Type) {
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
		locals^[p.name] = base.IR_Type {
			wasm_type = .I32,
			type_id   = base.Type_Var_ID(0),
		}
	case ^ir.IR_Pat_Record:
		for f in p.fields {
			locals^[f.binding] = base.IR_Type {
				wasm_type = .I32,
				type_id   = base.Type_Var_ID(0),
			}
		}
	case ^ir.IR_Pat_Wildcard:
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
	Async_Init,
	Async_Enqueue,
	Async_Dequeue,
	Async_Run,
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
		emit_instruction(Wasm_I32_Const{value = i32(env.data_offset)}, buf)
		env.data_offset += u32(len(e.value))
	case ^ir.IR_Var:
		if idx, ok := env.local_map[e.name]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
		} else if idx, ok := env.func_map[u64(e.name)]; ok {
			emit_instruction(Wasm_I32_Const{value = i32(idx)}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
	case ^ir.IR_Let:
		emit_expr(e.value, buf, env, runtime_indices)
		if e.type.wasm_type == .Void {
			// Void-typed let: value is for side effects only, no binding
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
		list_local := env.tmp_local_base
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
		}

		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
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
		emit_instruction(Wasm_Call{index = u32(call_idx)}, buf)
	case ^ir.IR_Tail_Call:
		// Check if callee is a local variable (closure pointer) or a named function
		if local_idx, ok := env.local_map[e.callee.name]; ok {
			// Callee is a closure pointer in a local variable — use call_indirect
			emit_instruction(Wasm_Local_Get{index = local_idx}, buf)

			callee_local := env.tmp_local_base + 2
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
			if idx < len(e.statements) - 1 && e.type.wasm_type != .Void {
				emit_instruction(Wasm_Drop{}, buf)
			}
		}
	case ^ir.IR_Match:
		match_kind := determine_match_kind(e.arms[:])
		block_type := ir_wasm_type_to_block_type(e.type.wasm_type)

		switch match_kind {
		case .Tag_Union:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + 2
			emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

			emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
			emit_instruction(Wasm_I32_Load8U{offset = CAMP_TAG_TAG_OFFSET}, buf)

			num_arms := len(e.arms)
			default_target := u32(num_arms - 1)
			targets := make([]u32, num_arms)
			for i in 0 ..< num_arms {
				targets[i] = u32(i)
				#partial switch p in e.arms[i].pattern {
				case ^ir.IR_Pat_Wildcard:
					default_target = u32(i)
				case ^ir.IR_Pat_Tag,
				     ^ir.IR_Pat_Record,
				     ^ir.IR_Pat_Var,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}
			}

			emit_instruction(Wasm_BrTable{targets = targets, default_idx = default_target}, buf)

			for arm_idx in 0 ..< len(e.arms) {
				arm := e.arms[arm_idx]
				emit_instruction(Wasm_Block{block_type = block_type}, buf)

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
				case ^ir.IR_Pat_Record:
				case ^ir.IR_Pat_Bool, ^ir.IR_Pat_Int, ^ir.IR_Pat_String:
				}

				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = 1}, buf)
				emit_instruction(Wasm_End{}, buf)
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)

		case .Bool:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + 2
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
					case ^ir.IR_Pat_Tag, ^ir.IR_Pat_Record, ^ir.IR_Pat_Int, ^ir.IR_Pat_String:
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
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = 1}, buf)

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

				if !is_last {
					#partial switch p in arm.pattern {
					case ^ir.IR_Pat_Int:
						emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
						emit_instruction(Wasm_I64_Const{value = p.value}, buf)
						emit_instruction(Wasm_I64_Eq{}, buf)
					case ^ir.IR_Pat_Wildcard, ^ir.IR_Pat_Var:
						emit_instruction(Wasm_I32_Const{value = 1}, buf)
					case ^ir.IR_Pat_Tag, ^ir.IR_Pat_Record, ^ir.IR_Pat_Bool, ^ir.IR_Pat_String:
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
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = 1}, buf)

				if !is_last {
					emit_instruction(Wasm_End{}, buf)
				}
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)

		case .String:
			emit_instruction(Wasm_Block{block_type = block_type}, buf)

			emit_expr(e.scrutinee, buf, env, runtime_indices)
			scrutinee_local := env.tmp_local_base + 2
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
					case ^ir.IR_Pat_Tag, ^ir.IR_Pat_Record, ^ir.IR_Pat_Bool, ^ir.IR_Pat_Int:
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
				     ^ir.IR_Pat_Wildcard,
				     ^ir.IR_Pat_Bool,
				     ^ir.IR_Pat_Int,
				     ^ir.IR_Pat_String:
				}

				emit_expr(arm.body, buf, env, runtime_indices)
				emit_instruction(Wasm_Br{label = 1}, buf)

				if !is_last {
					emit_instruction(Wasm_End{}, buf)
				}
			}

			emit_instruction(Wasm_Unreachable{}, buf)
			emit_instruction(Wasm_End{}, buf)
		}

	case ^ir.IR_Construct_Tag:
		num_fields := len(e.payload)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
		tmp_local_idx := env.tmp_local_base

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
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

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
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
		tmp_local_idx := env.tmp_local_base

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
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

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
					// task_ptr placeholder (would need current task context)
					emit_instruction(Wasm_I32_Const{value = 0}, buf)
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Timer_Insert])},
						buf,
					)
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
					emit_instruction(
						Wasm_Call{index = u32(runtime_indices[Runtime_Func.Sched_Block_IO])},
						buf,
					)
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

		emit_instruction(
			Wasm_Call_Indirect{type_idx = u32(resume_type_idx), table_idx = u32(env.table_idx)},
			buf,
		)
	case ^ir.IR_Closure:
		num_fields := len(e.params) + 2
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, buf)

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

	case ^ir.IR_Closure_Call:
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
		emit_instruction(Wasm_Unreachable{}, buf)
	}
}

emit_binop :: proc(op: ir.IR_BinOp_Kind, operand_type: base.IR_Wasm_Type, buf: ^[dynamic]u8) {
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
	case .Div, .Mod, .Exp:
		emit_instruction(Wasm_I64_Add{}, buf)
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
	case ^ir.IR_Let,
	     ^ir.IR_Tail_Call,
	     ^ir.IR_Match,
	     ^ir.IR_Expr_Nominal_Construct,
	     ^ir.IR_Method_Call,
	     ^ir.IR_Handle,
	     ^ir.IR_Perform,
	     ^ir.IR_Return,
	     ^ir.IR_Block,
	     ^ir.IR_Dup,
	     ^ir.IR_Drop,
	     ^ir.IR_Crash,
	     ^ir.IR_I32_Load,
	     ^ir.IR_I32_Store,
	     ^ir.IR_Atomic_Store,
	     ^ir.IR_Atomic_Fence:
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

	// Ignore the string arg for now — call continuation with Unit
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

emit_console_readln_handler_fn :: proc(env: ^Codegen_Env) -> (int, Wasm_Code) {
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
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)

	// readln! not supported — unreachable
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


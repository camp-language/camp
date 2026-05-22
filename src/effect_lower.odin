package camp

import "core:fmt"

Effect_Evidence :: struct {
	effect:    Canonical_Name,
	ev_var:    Intern_ID,
	arm_names: map[Intern_ID]Canonical_Name,
}

Effect_Lower_Env :: struct {
	module:         ^IR_Module,
	interner:       ^Intern_Table,
	collector:      ^Diagnostic_Collector,
	fresh:          int,
	evidence_stack: [dynamic]Effect_Evidence,
}

el_fresh :: proc(env: ^Effect_Lower_Env, prefix: string) -> Intern_ID {
	name := fmt.tprintf("{}_{}", prefix, env.fresh)
	env.fresh += 1
	return intern(env.interner, name)
}

effect_lower :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) -> IR_Module {
	result: IR_Module
	result.decls = make([dynamic]IR_Decl, 0, len(mod.decls) + 16)
	result.effect_defs = make([dynamic]IR_Effect_Def, 0, len(mod.effect_defs))
	for eff in mod.effect_defs {
		append(&result.effect_defs, eff)
	}
	result.string_table = make([dynamic]String_Table_Entry, 0, len(mod.string_table))
	for entry in mod.string_table {
		append(&result.string_table, entry)
	}

	env: Effect_Lower_Env
	env.module = &result
	env.interner = &ctx.interner
	env.fresh = 0
	env.evidence_stack = make([dynamic]Effect_Evidence, 0, 8)
	env.collector = &ctx.collector

	for decl in mod.decls {
		transformed := el_lower_decl(decl, &env)
		append(&result.decls, transformed)
	}

	delete(env.evidence_stack)
	return result
}

el_lower_decl :: proc(decl: IR_Decl, env: ^Effect_Lower_Env) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^
		new_fn.body = el_lower_expr(d.body, env)
		return IR_Decl(new_fn)
	case ^IR_Decl_Const:
		new_const := new(IR_Decl_Const)
		new_const^ = d^
		new_const.value = el_lower_expr(d.value, env)
		return IR_Decl(new_const)
	case:
		return decl
	}
}

el_find_effect_ops :: proc(effect: Canonical_Name, env: ^Effect_Lower_Env) -> []IR_Effect_Op {
	for &eff_def in env.module.effect_defs {
		if eff_def.name == effect {
			return eff_def.operations[:]
		}
	}
	return nil
}

el_replace_resume :: proc(expr: IR_Expr, resume_id: Intern_ID, resume_param: Intern_ID, env: ^Effect_Lower_Env) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Call:
		if e.callee.module == NO_NAME && e.callee.name == resume_id {
			resume_var := new(IR_Var)
			resume_var^ = IR_Var{name = resume_param, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

			new_args := make([dynamic]IR_Expr, 0, len(e.args))
			for arg in e.args {
				append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
			}

			cc := new(IR_Closure_Call)
			cc^ = IR_Closure_Call{
				callee = IR_Expr(resume_var),
				args = new_args,
				type = e.type,
				span = e.span,
			}
			return IR_Expr(cc)
		}
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = el_replace_resume(e.value, resume_id, resume_param, env),
			body = el_replace_resume(e.body, resume_id, resume_param, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = el_replace_resume(e.callee, resume_id, resume_param, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = el_replace_resume(e.condition, resume_id, resume_param, env),
			then_branch = el_replace_resume(e.then_branch, resume_id, resume_param, env),
			else_branch = el_replace_resume(e.else_branch, resume_id, resume_param, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = el_replace_resume(arm.body, resume_id, resume_param, env)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = el_replace_resume(e.scrutinee, resume_id, resume_param, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, el_replace_resume(stmt, resume_id, resume_param, env))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = el_replace_resume(e.left, resume_id, resume_param, env),
			right = el_replace_resume(e.right, resume_id, resume_param, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = el_replace_resume(e.value, resume_id, resume_param, env), span = e.span}
		return IR_Expr(new_ret)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_replace_resume(p, resume_id, resume_param, env))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, tag_index = e.tag_index, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = el_replace_resume(f.value, resume_id, resume_param, env)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = el_replace_resume(e.rest, resume_id, resume_param, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{
			record = el_replace_resume(e.record, resume_id, resume_param, env),
			field = e.field,
			field_index = e.field_index,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Handle:
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Handler_Arm{
				op = arm.op,
				resume_id = arm.resume_id,
				op_params = arm.op_params,
				body = el_replace_resume(arm.body, resume_id, resume_param, env),
			})
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = el_replace_resume(e.body, resume_id, resume_param, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform{effect = e.effect, op = e.op, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_perf)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{
			receiver = el_replace_resume(e.receiver, resume_id, resume_param, env),
			method = e.method,
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure{
			fn_name = e.fn_name,
			params = e.params,
			env = el_replace_resume(e.env, resume_id, resume_param, env),
			body = el_replace_resume(e.body, resume_id, resume_param, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_closure)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, env))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call{callee = e.callee, args = new_args, span = e.span}
		return IR_Expr(new_tc)

	case ^IR_Dup:
		return expr
	case ^IR_Drop:
		return expr
	case ^IR_Drop_Reuse:
		return expr
	case ^IR_Alloc_At:
		return expr
	case ^IR_Resume:
		return expr
	case ^IR_Atomic_Load:
		return expr
	case ^IR_Atomic_Store:
		return expr
	case ^IR_Atomic_RMW:
		return expr
	case ^IR_Atomic_Fence:
		return expr
	case ^IR_Wait:
		return expr
	case ^IR_Notify:
		return expr
	case ^IR_Literal_Int, ^IR_Literal_Float, ^IR_Literal_Bool, ^IR_Literal_String:
		return expr
	case ^IR_Var:
		return expr
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = el_replace_resume(e.message, resume_id, resume_param, env), span = e.span}
		return IR_Expr(new_crash)
	}

	return expr
}

el_lower_let_perform :: proc(let_expr: ^IR_Let, perform: ^IR_Perform, env: ^Effect_Lower_Env) -> IR_Expr {
	ev_var: Intern_ID = NO_NAME
	handler_name: Canonical_Name
	for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
		ev := env.evidence_stack[i]
		if ev.effect == perform.effect {
			ev_var = ev.ev_var
			if op_name, ok := ev.arm_names[perform.op]; ok {
				handler_name = op_name
			}
			break
		}
	}

	if ev_var == NO_NAME {
		collector_add_diag(env.collector, diag_internal("perform without handler evidence", perform.span))
		lit := new(IR_Literal_Int)
		lit^ = IR_Literal_Int{value = 0, type = let_expr.type, span = let_expr.span}
		return IR_Expr(lit)
	}

	cont_fn_name := Canonical_Name{
		module = NO_NAME,
		name = el_fresh(env, "_kc"),
		is_local = true,
	}
	cont_params := make([dynamic]IR_Param, 0, 1)
	append(&cont_params, IR_Param{name = let_expr.binding, type = let_expr.type})

	cont_closure := new(IR_Closure)
	cont_closure^ = IR_Closure{
		fn_name = cont_fn_name,
		params = cont_params,
		env = IR_Expr(nil),
		body = el_lower_expr(let_expr.body, env),
		type = let_expr.type,
		span = let_expr.span,
	}

	args := make([dynamic]IR_Expr, 0, len(perform.args) + 1)
	append(&args, IR_Expr(cont_closure))
	for arg in perform.args {
		append(&args, el_lower_expr(arg, env))
	}

	call := new(IR_Call)
	call^ = IR_Call{
		callee = handler_name,
		args = args,
		type = let_expr.type,
		span = let_expr.span,
	}
	return IR_Expr(call)
}

el_lower_expr :: proc(expr: IR_Expr, env: ^Effect_Lower_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Handle:
		ev_var := el_fresh(env, "_ev")

		effect_ops := el_find_effect_ops(e.effect, env)
		resume_param := el_fresh(env, "_resume")

		arm_fn_map: map[Intern_ID]Canonical_Name
		arm_fn_map = make(map[Intern_ID]Canonical_Name, len(e.arms))

		for arm in e.arms {
			handler_name_id := el_fresh(env, "handler")
			handler_name := Canonical_Name{
				module = NO_NAME,
				name = handler_name_id,
				is_local = true,
			}

			params := make([dynamic]IR_Param, 0, 4)
			append(&params, IR_Param{name = resume_param, type = IR_Type{.I32, Type_Var_ID(0)}})

			if effect_ops != nil {
				for op in effect_ops {
					if op.name == arm.op {
						for p in op.params {
							append(&params, p)
						}
						break
					}
				}
			}

			lowered_body := el_lower_expr(arm.body, env)
			transformed_body := el_replace_resume(lowered_body, arm.resume_id, resume_param, env)

			handler_fn := new(IR_Decl_Fn)
			handler_fn^ = IR_Decl_Fn{
				name = handler_name,
				is_effectful = false,
				params = params,
				return_type = e.type,
				effect_row = IR_Type{.Void, Type_Var_ID(0)},
				body = transformed_body,
				span = e.span,
			}
			append(&env.module.decls, IR_Decl(handler_fn))
			arm_fn_map[arm.op] = handler_name
		}

		append(&env.evidence_stack, Effect_Evidence{
			effect = e.effect,
			ev_var = ev_var,
			arm_names = arm_fn_map,
		})
		transformed_body := el_lower_expr(e.body, env)
		if len(env.evidence_stack) > 0 {
			pop(&env.evidence_stack)
		}

		zero_lit := new(IR_Literal_Int)
		zero_lit^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		let_expr := new(IR_Let)
		let_expr^ = IR_Let{
			binding = ev_var,
			type = IR_Type{.I32, Type_Var_ID(0)},
			value = IR_Expr(zero_lit),
			body = transformed_body,
			span = e.span,
		}
		return IR_Expr(let_expr)

	case ^IR_Let:
		#partial switch v in e.value {
		case ^IR_Perform:
			return el_lower_let_perform(e, v, env)
		case:
		}

		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = el_lower_expr(e.value, env),
			body = el_lower_expr(e.body, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Perform:
		ev_var: Intern_ID = NO_NAME
		handler_name: Canonical_Name
		for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
			ev := env.evidence_stack[i]
			if ev.effect == e.effect {
				ev_var = ev.ev_var
				if op_name, ok := ev.arm_names[e.op]; ok {
					handler_name = op_name
				}
				break
			}
		}

		if ev_var == NO_NAME {
			collector_add_diag(env.collector, diag_internal("perform without handler evidence", e.span))
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int{value = 0, type = e.type, span = e.span}
			return IR_Expr(lit)
		}
		if handler_name.name == NO_NAME {
			collector_add_diag(env.collector, diag_internal("perform without handler name for op", e.span))
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int{value = 0, type = e.type, span = e.span}
			return IR_Expr(lit)
		}

		cont_fn_name := Canonical_Name{
			module = NO_NAME,
			name = el_fresh(env, "_kc"),
			is_local = true,
		}
		cont_result := el_fresh(env, "_kr")
		cont_params := make([dynamic]IR_Param, 0, 1)
		append(&cont_params, IR_Param{name = cont_result, type = e.type})

		result_var := new(IR_Var)
		result_var^ = IR_Var{name = cont_result, type = e.type, span = e.span}

		cont_fn := new(IR_Decl_Fn)
		cont_fn^ = IR_Decl_Fn{
			name = cont_fn_name,
			is_effectful = false,
			params = cont_params,
			return_type = e.type,
			effect_row = IR_Type{.Void, Type_Var_ID(0)},
			body = IR_Expr(result_var),
			span = e.span,
		}
		append(&env.module.decls, IR_Decl(cont_fn))

		cont_closure := new(IR_Closure)
		cont_closure^ = IR_Closure{
			fn_name = cont_fn_name,
			params = cont_params,
			env = IR_Expr(nil),
			body = IR_Expr(result_var),
			type = e.type,
			span = e.span,
		}

		args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
		append(&args, IR_Expr(cont_closure))
		for arg in e.args {
			append(&args, el_lower_expr(arg, env))
		}

		call := new(IR_Call)
		call^ = IR_Call{
			callee = handler_name,
			args = args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(call)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = el_lower_expr(e.callee, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call{callee = e.callee, args = new_args, span = e.span}
		return IR_Expr(new_tc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = el_lower_expr(e.condition, env),
			then_branch = el_lower_expr(e.then_branch, env),
			else_branch = el_lower_expr(e.else_branch, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = el_lower_expr(arm.body, env)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = el_lower_expr(e.scrutinee, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_lower_expr(p, env))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, tag_index = e.tag_index, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = el_lower_expr(f.value, env)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = el_lower_expr(e.rest, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{record = el_lower_expr(e.record, env), field = e.field, field_index = e.field_index, type = e.type, span = e.span}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{receiver = el_lower_expr(e.receiver, env), method = e.method, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_mc)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = el_lower_expr(e.value, env), span = e.span}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, el_lower_expr(stmt, env))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = el_lower_expr(e.left, env),
			right = el_lower_expr(e.right, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure{
			fn_name = e.fn_name,
			params = e.params,
			env = el_lower_expr(e.env, env),
			body = el_lower_expr(e.body, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_closure)

	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = el_lower_expr(e.message, env), span = e.span}
		return IR_Expr(new_crash)
	case ^IR_Resume:
		return expr
	case ^IR_Atomic_Load:
		return expr
	case ^IR_Atomic_Store:
		return expr
	case ^IR_Atomic_RMW:
		return expr
	case ^IR_Atomic_Fence:
		return expr
	case ^IR_Wait:
		return expr
	case ^IR_Notify:
		return expr
	}

	return expr
}

package camp

import "core:fmt"

Effect_Evidence :: struct {
	effect:      Canonical_Name,
	ev_var:      Intern_ID,
	is_shallow:  bool,
	inactive:    bool,
	arm_indices: map[Intern_ID]int,
}

Effect_Lower_Env :: struct {
	module:         ^IR_Module,
	interner:       ^Intern_Table,
	collector:      ^Diagnostic_Collector,
	fresh:          int,
	evidence_stack: [dynamic]Effect_Evidence,
	fn_effects:     map[Canonical_Name][dynamic]Canonical_Name,
	camp_alloc_id:  Intern_ID,
	camp_dealloc_id: Intern_ID,
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
	env.fn_effects = make(map[Canonical_Name][dynamic]Canonical_Name, 16)
	env.camp_alloc_id = intern(&ctx.interner, "camp_alloc")
	env.camp_dealloc_id = intern(&ctx.interner, "camp_dealloc")

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			if len(d.effects) > 0 {
				env.fn_effects[d.name] = d.effects
			}
		case:
		}
	}

	for decl in mod.decls {
		transformed := el_lower_decl(decl, &env)
		append(&result.decls, transformed)
	}

	delete(env.evidence_stack)
	delete(env.fn_effects)
	return result
}

el_lower_decl :: proc(decl: IR_Decl, env: ^Effect_Lower_Env) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^

		if len(d.effects) > 0 {
			ev_params := make([dynamic]IR_Param, 0, len(d.effects))
			for eff in d.effects {
				eff_name_str := intern_get(env.interner, eff.name)
				param_name := intern(env.interner, fmt.tprintf("_ev_{}", eff_name_str))
				append(&ev_params, IR_Param{name = param_name, type = IR_Type{.I32, Type_Var_ID(0)}})
			}
			prepend_params := make([dynamic]IR_Param, 0, len(ev_params) + len(d.params))
			for p in ev_params {
				append(&prepend_params, p)
			}
			for p in d.params {
				append(&prepend_params, p)
			}
			new_fn.params = prepend_params
		}

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

el_find_arm_index :: proc(effect: Canonical_Name, op: Intern_ID, env: ^Effect_Lower_Env) -> int {
	ops := el_find_effect_ops(effect, env)
	if ops == nil {
		return 0
	}
	for op_def, i in ops {
		if op_def.name == op {
			return i
		}
	}
	return 0
}

el_find_evidence :: proc(effect: Canonical_Name, env: ^Effect_Lower_Env) -> Intern_ID {
	for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
		ev := env.evidence_stack[i]
		if ev.effect == effect && !ev.inactive {
			return ev.ev_var
		}
	}
	return NO_NAME
}

el_replace_resume :: proc(expr: IR_Expr, resume_id: Intern_ID, resume_param: Intern_ID, ev_param: Intern_ID, is_shallow: bool, env: ^Effect_Lower_Env) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Call:
		if e.callee.module == NO_NAME && e.callee.name == resume_id {
			resume_val: IR_Expr
			if len(e.args) > 0 {
				resume_val = el_replace_resume(e.args[0], resume_id, resume_param, ev_param, is_shallow, env)
			} else {
				lit := new(IR_Literal_Int)
				lit^ = IR_Literal_Int{value = 0, type = IR_Type{.Void, Type_Var_ID(0)}, span = e.span}
				resume_val = IR_Expr(lit)
			}

			ev_expr: IR_Expr = nil
			if !is_shallow && ev_param != NO_NAME {
				ev_var := new(IR_Var)
				ev_var^ = IR_Var{name = ev_param, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
				ev_expr = IR_Expr(ev_var)
			}

			resume := new(IR_Resume)
			resume^ = IR_Resume{
				resume_id = resume_param,
				value = resume_val,
				ev = ev_expr,
				type = e.type,
				span = e.span,
			}
			return IR_Expr(resume)
		}
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = el_replace_resume(e.value, resume_id, resume_param, ev_param, is_shallow, env),
			body = el_replace_resume(e.body, resume_id, resume_param, ev_param, is_shallow, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = el_replace_resume(e.callee, resume_id, resume_param, ev_param, is_shallow, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = el_replace_resume(e.condition, resume_id, resume_param, ev_param, is_shallow, env),
			then_branch = el_replace_resume(e.then_branch, resume_id, resume_param, ev_param, is_shallow, env),
			else_branch = el_replace_resume(e.else_branch, resume_id, resume_param, ev_param, is_shallow, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = el_replace_resume(arm.body, resume_id, resume_param, ev_param, is_shallow, env)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = el_replace_resume(e.scrutinee, resume_id, resume_param, ev_param, is_shallow, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, el_replace_resume(stmt, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = el_replace_resume(e.left, resume_id, resume_param, ev_param, is_shallow, env),
			right = el_replace_resume(e.right, resume_id, resume_param, ev_param, is_shallow, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = el_replace_resume(e.value, resume_id, resume_param, ev_param, is_shallow, env), span = e.span}
		return IR_Expr(new_ret)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_replace_resume(p, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, tag_index = e.tag_index, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = el_replace_resume(f.value, resume_id, resume_param, ev_param, is_shallow, env)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = el_replace_resume(e.rest, resume_id, resume_param, ev_param, is_shallow, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{
			record = el_replace_resume(e.record, resume_id, resume_param, ev_param, is_shallow, env),
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
				params = arm.params,
				body = el_replace_resume(arm.body, resume_id, resume_param, ev_param, is_shallow, env),
			})
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = el_replace_resume(e.body, resume_id, resume_param, ev_param, is_shallow, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform{effect = e.effect, op = e.op, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_perf)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, is_shallow, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{
			receiver = el_replace_resume(e.receiver, resume_id, resume_param, ev_param, is_shallow, env),
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
			env = el_replace_resume(e.env, resume_id, resume_param, ev_param, is_shallow, env),
			body = el_replace_resume(e.body, resume_id, resume_param, ev_param, is_shallow, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_closure)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, is_shallow, env))
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
	case ^IR_Literal_Int, ^IR_Literal_Float, ^IR_Literal_Bool, ^IR_Literal_String:
		return expr
	case ^IR_Var:
		return expr
		case ^IR_Resume:
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = el_replace_resume(e.ev, resume_id, resume_param, ev_param, is_shallow, env)
		}
		new_resume^ = IR_Resume{
			resume_id = e.resume_id,
			value = el_replace_resume(e.value, resume_id, resume_param, ev_param, is_shallow, env),
			ev = ev_val,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_resume)
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = el_replace_resume(e.message, resume_id, resume_param, ev_param, is_shallow, env), span = e.span}
		return IR_Expr(new_crash)
	case ^IR_I32_Load:
		new_load := new(IR_I32_Load)
		new_load^ = IR_I32_Load{
			base = el_replace_resume(e.base, resume_id, resume_param, ev_param, is_shallow, env),
			offset = e.offset,
			span = e.span,
		}
		return IR_Expr(new_load)
	case ^IR_I32_Store:
		new_store := new(IR_I32_Store)
		new_store^ = IR_I32_Store{
			base = el_replace_resume(e.base, resume_id, resume_param, ev_param, is_shallow, env),
			offset = e.offset,
			value = el_replace_resume(e.value, resume_id, resume_param, ev_param, is_shallow, env),
			span = e.span,
		}
		return IR_Expr(new_store)
	}

	return expr
}

el_make_camp_alloc_call :: proc(size: int, span: Source_Span, env: ^Effect_Lower_Env) -> IR_Expr {
	size_lit := new(IR_Literal_Int)
	size_lit^ = IR_Literal_Int{value = i64(size), type = IR_Type{.I32, Type_Var_ID(0)}, span = span}

	callee := Canonical_Name{
		module = NO_NAME,
		name = env.camp_alloc_id,
		is_local = false,
	}

	args := make([dynamic]IR_Expr, 0, 1)
	append(&args, IR_Expr(size_lit))

	call := new(IR_Call)
	call^ = IR_Call{
		callee = callee,
		args = args,
		type = IR_Type{.I32, Type_Var_ID(0)},
		span = span,
	}
	return IR_Expr(call)
}

el_make_camp_dealloc_call :: proc(ev_var: Intern_ID, size: int, span: Source_Span, env: ^Effect_Lower_Env) -> IR_Expr {
	ev_var_expr := new(IR_Var)
	ev_var_expr^ = IR_Var{name = ev_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = span}

	size_lit := new(IR_Literal_Int)
	size_lit^ = IR_Literal_Int{value = i64(size), type = IR_Type{.I32, Type_Var_ID(0)}, span = span}

	callee := Canonical_Name{
		module = NO_NAME,
		name = env.camp_dealloc_id,
		is_local = false,
	}

	args := make([dynamic]IR_Expr, 0, 2)
	append(&args, IR_Expr(ev_var_expr))
	append(&args, IR_Expr(size_lit))

	call := new(IR_Call)
	call^ = IR_Call{
		callee = callee,
		args = args,
		type = IR_Type{.Void, Type_Var_ID(0)},
		span = span,
	}
	return IR_Expr(call)
}

el_make_i32_store :: proc(base_var: Intern_ID, offset: int, value: IR_Expr, span: Source_Span) -> IR_Expr {
	base := new(IR_Var)
	base^ = IR_Var{name = base_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = span}

	store := new(IR_I32_Store)
	store^ = IR_I32_Store{
		base = IR_Expr(base),
		offset = offset,
		value = value,
		span = span,
	}
	return IR_Expr(store)
}

el_make_let_void :: proc(binding: Intern_ID, value: IR_Expr, body: IR_Expr, span: Source_Span) -> IR_Expr {
	let_expr := new(IR_Let)
	let_expr^ = IR_Let{
		binding = binding,
		type = IR_Type{.Void, Type_Var_ID(0)},
		value = value,
		body = body,
		span = span,
	}
	return IR_Expr(let_expr)
}

el_lower_let_perform :: proc(let_expr: ^IR_Let, perform: ^IR_Perform, env: ^Effect_Lower_Env) -> IR_Expr {
	ev_var := el_find_evidence(perform.effect, env)

	if ev_var == NO_NAME {
		collector_add_diag(env.collector, diag_internal("perform without handler evidence", perform.span))
		lit := new(IR_Literal_Int)
		lit^ = IR_Literal_Int{value = 0, type = let_expr.type, span = let_expr.span}
		return IR_Expr(lit)
	}

	is_shallow := false
	for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
		if env.evidence_stack[i].effect == perform.effect && !env.evidence_stack[i].inactive {
			is_shallow = env.evidence_stack[i].is_shallow
			break
		}
	}

	arm_index := el_find_arm_index(perform.effect, perform.op, env)

	cont_fn_name := Canonical_Name{
		module = NO_NAME,
		name = el_fresh(env, "_kc"),
		is_local = true,
	}
	cont_params := make([dynamic]IR_Param, 0, 2)
	append(&cont_params, IR_Param{name = let_expr.binding, type = let_expr.type})
	ev_param_for_cont: Intern_ID = NO_NAME
	if !is_shallow {
		ev_param_for_cont = el_fresh(env, "_ev")
		append(&cont_params, IR_Param{name = ev_param_for_cont, type = IR_Type{.I32, Type_Var_ID(0)}})
	}

	cont_fn_body: IR_Expr
	if is_shallow {
		ev_idx := -1
		for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
			if env.evidence_stack[i].effect == perform.effect && !env.evidence_stack[i].inactive {
				ev_idx = i
				break
			}
		}
		if ev_idx >= 0 {
			env.evidence_stack[ev_idx].inactive = true
			cont_fn_body = el_lower_expr(let_expr.body, env)
			env.evidence_stack[ev_idx].inactive = false
		} else {
			cont_fn_body = el_lower_expr(let_expr.body, env)
		}
	} else {
		cont_fn_body = el_lower_expr(let_expr.body, env)
	}

	cont_closure := new(IR_Closure)
	cont_closure^ = IR_Closure{
		fn_name = cont_fn_name,
		params = cont_params,
		env = IR_Expr(nil),
		body = cont_fn_body,
		type = let_expr.type,
		span = let_expr.span,
	}

	cont_fn := new(IR_Decl_Fn)
	cont_fn^ = IR_Decl_Fn{
		name = cont_fn_name,
		is_effectful = false,
		params = cont_params,
		return_type = let_expr.type,
		effect_row = IR_Type{.Void, Type_Var_ID(0)},
		effects = make([dynamic]Canonical_Name, 0),
		body = cont_fn_body,
		span = let_expr.span,
	}
	append(&env.module.decls, IR_Decl(cont_fn))

	ev_var_expr := new(IR_Var)
	ev_var_expr^ = IR_Var{name = ev_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = perform.span}

	closure_load := new(IR_I32_Load)
	closure_load^ = IR_I32_Load{
		base = IR_Expr(ev_var_expr),
		offset = arm_index * 4,
		span = perform.span,
	}

	args := make([dynamic]IR_Expr, 0, len(perform.args) + 2)
	for arg in perform.args {
		append(&args, el_lower_expr(arg, env))
	}
	append(&args, IR_Expr(cont_closure))

	ev_arg := new(IR_Var)
	ev_arg^ = IR_Var{name = ev_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = perform.span}
	append(&args, IR_Expr(ev_arg))

	cc := new(IR_Closure_Call)
	cc^ = IR_Closure_Call{
		callee = IR_Expr(closure_load),
		args = args,
		type = let_expr.type,
		span = let_expr.span,
	}
	return IR_Expr(cc)
}

el_lower_expr :: proc(expr: IR_Expr, env: ^Effect_Lower_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Handle:
		ev_var := el_fresh(env, "_ev")

		effect_ops := el_find_effect_ops(e.effect, env)
		resume_param := el_fresh(env, "_resume")
		ev_param := el_fresh(env, "_ev_arm")
		env_param := el_fresh(env, "_env")

		num_arms := len(e.arms)

		arm_indices: map[Intern_ID]int
		arm_indices = make(map[Intern_ID]int, num_arms)

		for arm, arm_idx in e.arms {
			handler_name_id := el_fresh(env, "handler")
			handler_name := Canonical_Name{
				module = NO_NAME,
				name = handler_name_id,
				is_local = true,
			}

			params := make([dynamic]IR_Param, 0, 4 + len(arm.params))
			append(&params, IR_Param{name = env_param, type = IR_Type{.I32, Type_Var_ID(0)}})

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

			append(&params, IR_Param{name = resume_param, type = IR_Type{.I32, Type_Var_ID(0)}})
			append(&params, IR_Param{name = ev_param, type = IR_Type{.I32, Type_Var_ID(0)}})

			lowered_body := el_lower_expr(arm.body, env)
			transformed_body := el_replace_resume(lowered_body, arm.params[0], resume_param, ev_param, e.is_shallow, env)

			handler_fn := new(IR_Decl_Fn)
			handler_fn^ = IR_Decl_Fn{
				name = handler_name,
				is_effectful = false,
				params = params,
				return_type = e.type,
				effect_row = IR_Type{.Void, Type_Var_ID(0)},
				effects = make([dynamic]Canonical_Name, 0),
				body = transformed_body,
				span = e.span,
			}
			append(&env.module.decls, IR_Decl(handler_fn))
			arm_indices[arm.op] = arm_idx
		}

		append(&env.evidence_stack, Effect_Evidence{
			effect = e.effect,
			ev_var = ev_var,
			is_shallow = e.is_shallow,
			arm_indices = arm_indices,
		})
		transformed_body := el_lower_expr(e.body, env)
		if len(env.evidence_stack) > 0 {
			pop(&env.evidence_stack)
		}

		ev_record_size := num_arms * 4

		alloc_call := el_make_camp_alloc_call(ev_record_size, e.span, env)

		result: IR_Expr = transformed_body

		for arm, arm_idx in e.arms {
			handler_name_id_for_closure := el_fresh(env, "handler")
			handler_name_for_closure := Canonical_Name{
				module = NO_NAME,
				name = handler_name_id_for_closure,
				is_local = true,
			}

			closure_params := make([dynamic]IR_Param, 0, 2 + len(arm.params))
			append(&closure_params, IR_Param{name = env_param, type = IR_Type{.I32, Type_Var_ID(0)}})
			if effect_ops != nil {
				for op in effect_ops {
					if op.name == arm.op {
						for p in op.params {
							append(&closure_params, p)
						}
						break
					}
				}
			}
			append(&closure_params, IR_Param{name = resume_param, type = IR_Type{.I32, Type_Var_ID(0)}})
			append(&closure_params, IR_Param{name = ev_param, type = IR_Type{.I32, Type_Var_ID(0)}})

			zero_lit := new(IR_Literal_Int)
			zero_lit^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

			handler_closure := new(IR_Closure)
			handler_closure^ = IR_Closure{
				fn_name = handler_name_for_closure,
				params = closure_params,
				env = IR_Expr(zero_lit),
				body = IR_Expr(nil),
				type = IR_Type{.I32, Type_Var_ID(0)},
				span = e.span,
			}

			closure_binding := el_fresh(env, "_hcl")

			store_expr := el_make_i32_store(ev_var, arm_idx * 4, IR_Expr(handler_closure), e.span)
			store_binding := el_fresh(env, "_store")

			result = el_make_let_void(store_binding, store_expr, result, e.span)
			result = el_make_let_void(closure_binding, IR_Expr(handler_closure), result, e.span)
		}

		dealloc_call := el_make_camp_dealloc_call(ev_var, ev_record_size, e.span, env)
		dealloc_binding := el_fresh(env, "_dealloc")
		result = el_make_let_void(dealloc_binding, dealloc_call, result, e.span)

		let_expr := new(IR_Let)
		let_expr^ = IR_Let{
			binding = ev_var,
			type = IR_Type{.I32, Type_Var_ID(0)},
			value = alloc_call,
			body = result,
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
		ev_var := el_find_evidence(e.effect, env)

		if ev_var == NO_NAME {
			collector_add_diag(env.collector, diag_internal("perform without handler evidence", e.span))
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int{value = 0, type = e.type, span = e.span}
			return IR_Expr(lit)
		}

		is_shallow := false
		for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
			if env.evidence_stack[i].effect == e.effect && !env.evidence_stack[i].inactive {
				is_shallow = env.evidence_stack[i].is_shallow
				break
			}
		}

		arm_index := el_find_arm_index(e.effect, e.op, env)

		cont_fn_name := Canonical_Name{
			module = NO_NAME,
			name = el_fresh(env, "_kc"),
			is_local = true,
		}
		cont_result := el_fresh(env, "_kr")
		cont_params := make([dynamic]IR_Param, 0, 2)
		append(&cont_params, IR_Param{name = cont_result, type = e.type})
		if !is_shallow {
			ev_param_for_cont := el_fresh(env, "_ev")
			append(&cont_params, IR_Param{name = ev_param_for_cont, type = IR_Type{.I32, Type_Var_ID(0)}})
		}

		result_var := new(IR_Var)
		result_var^ = IR_Var{name = cont_result, type = e.type, span = e.span}

		cont_fn := new(IR_Decl_Fn)
		cont_fn^ = IR_Decl_Fn{
			name = cont_fn_name,
			is_effectful = false,
			params = cont_params,
			return_type = e.type,
			effect_row = IR_Type{.Void, Type_Var_ID(0)},
			effects = make([dynamic]Canonical_Name, 0),
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

		ev_var_expr := new(IR_Var)
		ev_var_expr^ = IR_Var{name = ev_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		closure_load := new(IR_I32_Load)
		closure_load^ = IR_I32_Load{
			base = IR_Expr(ev_var_expr),
			offset = arm_index * 4,
			span = e.span,
		}

		args := make([dynamic]IR_Expr, 0, len(e.args) + 2)
		for arg in e.args {
			append(&args, el_lower_expr(arg, env))
		}
		append(&args, IR_Expr(cont_closure))

		ev_arg := new(IR_Var)
		ev_arg^ = IR_Var{name = ev_var, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
		append(&args, IR_Expr(ev_arg))

		cc := new(IR_Closure_Call)
		cc^ = IR_Closure_Call{
			callee = IR_Expr(closure_load),
			args = args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(cc)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}

		if callee_effects, ok := env.fn_effects[e.callee]; ok {
			for eff in callee_effects {
				ev_arg_id := el_find_evidence(eff, env)
				if ev_arg_id != NO_NAME {
					ev_arg := new(IR_Var)
					ev_arg^ = IR_Var{name = ev_arg_id, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
					append(&new_args, IR_Expr(ev_arg))
				} else {
					zero_lit := new(IR_Literal_Int)
					zero_lit^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
					append(&new_args, IR_Expr(zero_lit))
				}
			}
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

		if callee_effects, ok := env.fn_effects[e.callee]; ok {
			for eff in callee_effects {
				ev_arg_id := el_find_evidence(eff, env)
				if ev_arg_id != NO_NAME {
					ev_arg := new(IR_Var)
					ev_arg^ = IR_Var{name = ev_arg_id, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
					append(&new_args, IR_Expr(ev_arg))
				} else {
					zero_lit := new(IR_Literal_Int)
					zero_lit^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
					append(&new_args, IR_Expr(zero_lit))
				}
			}
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
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = el_lower_expr(e.ev, env)
		}
		new_resume^ = IR_Resume{
			resume_id = e.resume_id,
			value = el_lower_expr(e.value, env),
			ev = ev_val,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_I32_Load:
		new_load := new(IR_I32_Load)
		new_load^ = IR_I32_Load{
			base = el_lower_expr(e.base, env),
			offset = e.offset,
			span = e.span,
		}
		return IR_Expr(new_load)

	case ^IR_I32_Store:
		new_store := new(IR_I32_Store)
		new_store^ = IR_I32_Store{
			base = el_lower_expr(e.base, env),
			offset = e.offset,
			value = el_lower_expr(e.value, env),
			span = e.span,
		}
		return IR_Expr(new_store)
	}

	return expr
}

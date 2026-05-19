package camp

import "core:fmt"

Effect_Evidence :: struct {
	effect: Canonical_Name,
	ev_var: Intern_ID,
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

el_lower_expr :: proc(expr: IR_Expr, env: ^Effect_Lower_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Handle:
		ev_var := el_fresh(env, "_ev")

		for arm in e.arms {
			handler_name_id := el_fresh(env, "handler")
			handler_name := Canonical_Name{
				module = NO_NAME,
				name = handler_name_id,
				is_local = true,
			}

			params := make([dynamic]IR_Param, 0, 4)
			append(&params, IR_Param{name = ev_var, type = IR_Type{.I64, Type_Var_ID(0)}})
			append(&params, IR_Param{name = arm.resume_id, type = IR_Type{.Funcref, Type_Var_ID(0)}})

			handler_fn := new(IR_Decl_Fn)
			handler_fn^ = IR_Decl_Fn{
				name = handler_name,
				is_effectful = true,
				params = params,
				return_type = e.type,
				effect_row = IR_Type{.Void, Type_Var_ID(0)},
				body = el_lower_expr(arm.body, env),
				span = e.span,
			}
			append(&env.module.decls, IR_Decl(handler_fn))
		}

		append(&env.evidence_stack, Effect_Evidence{effect = e.effect, ev_var = ev_var})
		transformed_body := el_lower_expr(e.body, env)
		if len(env.evidence_stack) > 0 {
			pop(&env.evidence_stack)
		}

		make_handler_name := Canonical_Name{
			module = NO_NAME,
			name = intern(env.interner, "make_handler"),
			is_local = false,
		}
		make_handler_args := make([dynamic]IR_Expr, 0, 1)
		lit := new(IR_Literal_Int)
		lit^ = IR_Literal_Int{value = 0, type = IR_Type{.I64, Type_Var_ID(0)}, span = e.span}
		append(&make_handler_args, IR_Expr(lit))

		call := new(IR_Call)
		call^ = IR_Call{
			callee = make_handler_name,
			args = make_handler_args,
			type = e.type,
			span = e.span,
		}

		let_expr := new(IR_Let)
		let_expr^ = IR_Let{
			binding = ev_var,
			type = e.type,
			value = IR_Expr(call),
			body = transformed_body,
			span = e.span,
		}
		return IR_Expr(let_expr)

	case ^IR_Perform:
		ev_var: Intern_ID = NO_NAME
		for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
			if env.evidence_stack[i].effect == e.effect {
				ev_var = env.evidence_stack[i].ev_var
				break
			}
		}

		if ev_var == NO_NAME {
			collector_add_diag(env.collector, diag_internal("perform without handler evidence", e.span))
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int{value = 0, type = e.type, span = e.span}
			return IR_Expr(lit)
		}

		args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
		ev_ref := new(IR_Var)
		ev_ref^ = IR_Var{name = ev_var, type = IR_Type{.I64, Type_Var_ID(0)}, span = e.span}
		append(&args, IR_Expr(ev_ref))
		for arg in e.args {
			append(&args, el_lower_expr(arg, env))
		}

		handler_callee := Canonical_Name{
			module = e.effect.module,
			name = e.op,
			is_local = false,
		}

		call := new(IR_Call)
		call^ = IR_Call{
			callee = handler_callee,
			args = args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(call)

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = el_lower_expr(e.value, env),
			body = el_lower_expr(e.body, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

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
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, payload = new_payload, type = e.type, span = e.span}
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
		new_fa^ = IR_Field_Access{record = el_lower_expr(e.record, env), field = e.field, type = e.type, span = e.span}
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
	}

	return expr
}

package camp

import "core:fmt"

CPS_Env :: struct {
	interner:      ^Intern_Table,
	module:        ^IR_Module,
	effectful_fns: map[Canonical_Name]bool,
	fresh:         int,
}

cps_fresh :: proc(env: ^CPS_Env, prefix: string) -> Intern_ID {
	name := fmt.tprintf("{}_{}", prefix, env.fresh)
	env.fresh += 1
	return intern(env.interner, name)
}

cps_make_continuation :: proc(body: IR_Expr, param_name: Intern_ID, return_type: IR_Type, k_name: Intern_ID, env: ^CPS_Env) -> Canonical_Name {
	cont_name := Canonical_Name{
		module = NO_NAME,
		name = cps_fresh(env, "_kc"),
		is_local = true,
	}

	cont_params := make([dynamic]IR_Param, 0, 1)
	append(&cont_params, IR_Param{name = param_name, type = return_type})

	cont_fn := new(IR_Decl_Fn)
	cont_fn^ = IR_Decl_Fn{
		name = cont_name,
		is_effectful = false,
		params = cont_params,
		return_type = return_type,
		effect_row = IR_Type{.Void, Type_Var_ID(0)},
		body = cps_transform_expr(body, k_name, env),
		span = Source_Span_ZERO,
	}
	append(&env.module.decls, IR_Decl(cont_fn))
	return cont_name
}

cps_transform :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) -> IR_Module {
	result: IR_Module
	result.decls = make([dynamic]IR_Decl, 0, len(mod.decls))
	result.effect_defs = make([dynamic]IR_Effect_Def, 0, len(mod.effect_defs))
	for eff in mod.effect_defs {
		append(&result.effect_defs, eff)
	}
	result.string_table = make([dynamic]String_Table_Entry, 0, len(mod.string_table))
	for entry in mod.string_table {
		append(&result.string_table, entry)
	}

	env: CPS_Env
	env.interner = &ctx.interner
	env.module = &result
	env.fresh = 0

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			if d.is_effectful {
				env.effectful_fns[d.name] = true
			}
		case:
		}
	}

	for decl in mod.decls {
		transformed := cps_transform_decl(decl, &env)
		append(&result.decls, transformed)
	}

	return result
}

cps_transform_decl :: proc(decl: IR_Decl, env: ^CPS_Env) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		if !d.is_effectful {
			return decl
		}

		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^

		k_name := cps_fresh(env, "_k")
		append(&new_fn.params, IR_Param{name = k_name, type = IR_Type{.Funcref, Type_Var_ID(0)}})

		transformed_body := cps_transform_expr(d.body, k_name, env)

		result_name := cps_fresh(env, "_result")
		k_callee := Canonical_Name{
			module = NO_NAME,
			name = k_name,
			is_local = true,
		}
		k_args := make([dynamic]IR_Expr, 0, 1)
		result_var := new(IR_Var)
		result_var^ = IR_Var{name = result_name, type = d.return_type, span = d.span}
		append(&k_args, IR_Expr(result_var))

		tc := new(IR_Tail_Call)
		tc^ = IR_Tail_Call{callee = k_callee, args = k_args, span = d.span}

		let_expr := new(IR_Let)
		let_expr^ = IR_Let{
			binding = result_name,
			type = d.return_type,
			value = transformed_body,
			body = IR_Expr(tc),
			span = d.span,
		}
		new_fn.body = IR_Expr(let_expr)
		return IR_Decl(new_fn)
	case:
		return decl
	}
}

cps_transform_expr :: proc(expr: IR_Expr, k_name: Intern_ID, env: ^CPS_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Return:
		k_callee := Canonical_Name{
			module = NO_NAME,
			name = k_name,
			is_local = true,
		}

		args := make([dynamic]IR_Expr, 0, 1)
		append(&args, cps_transform_expr(e.value, k_name, env))

		tc := new(IR_Tail_Call)
		tc^ = IR_Tail_Call{callee = k_callee, args = args, span = e.span}
		return IR_Expr(tc)

	case ^IR_Let:
		#partial switch v in e.value {
		case ^IR_Call:
			if v.callee in env.effectful_fns {
				result_name := cps_fresh(env, "_r")
				result_type := v.type

				cont_name := cps_make_continuation(
					e.body,
					result_name,
					result_type,
					k_name,
					env,
				)

				new_args := make([dynamic]IR_Expr, 0, len(v.args) + 1)
				for arg in v.args {
					append(&new_args, cps_transform_expr(arg, k_name, env))
				}
				cont_var := new(IR_Var)
				cont_var^ = IR_Var{name = cont_name.name, type = IR_Type{.Funcref, Type_Var_ID(0)}, span = e.span}
				append(&new_args, IR_Expr(cont_var))

				tc := new(IR_Tail_Call)
				tc^ = IR_Tail_Call{callee = v.callee, args = new_args, span = e.span}
				return IR_Expr(tc)
			}
		case:

		}

		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = cps_transform_expr(e.value, k_name, env),
			body = cps_transform_expr(e.body, k_name, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = cps_transform_expr(e.callee, k_name, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call{callee = e.callee, args = new_args, span = e.span}
		return IR_Expr(new_tc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = cps_transform_expr(e.condition, k_name, env),
			then_branch = cps_transform_expr(e.then_branch, k_name, env),
			else_branch = cps_transform_expr(e.else_branch, k_name, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = cps_transform_expr(arm.body, k_name, env)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = cps_transform_expr(e.scrutinee, k_name, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, cps_transform_expr(p, k_name, env))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = cps_transform_expr(f.value, k_name, env)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = cps_transform_expr(e.rest, k_name, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{
			record = cps_transform_expr(e.record, k_name, env),
			field = e.field,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{
			receiver = cps_transform_expr(e.receiver, k_name, env),
			method = e.method,
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Handle:
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Handler_Arm{
				op = arm.op,
				resume_id = arm.resume_id,
				body = cps_transform_expr(arm.body, arm.resume_id, env),
			})
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = cps_transform_expr(e.body, k_name, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform{effect = e.effect, op = e.op, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_perf)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, cps_transform_expr(stmt, k_name, env))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = cps_transform_expr(e.left, k_name, env),
			right = cps_transform_expr(e.right, k_name, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)
	}

	return expr
}

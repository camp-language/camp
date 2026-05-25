package ir

import "camp:base"
import "core:fmt"

Closure_Convert_Env :: struct {
	module:     ^IR_Module,
	interner:   ^base.Intern_Table,
	fresh_state: base.Fresh_State,
}


cc_free_vars :: proc(expr: IR_Expr, bound: ^map[base.Intern_ID]bool) -> [dynamic]base.Intern_ID {
	result: [dynamic]base.Intern_ID
	result = make([dynamic]base.Intern_ID, 0, 8)

	#partial switch e in expr {
	case ^IR_Var:
		if _, ok := bound^[e.name]; !ok {
			already := false
			for v in result {
				if v == e.name {
					already = true
					break
				}
			}
			if !already {
				append(&result, e.name)
			}
		}
	case ^IR_Let:
		inner := cc_free_vars(e.value, bound)
		for v in inner {
			append(&result, v)
		}
		delete(inner)

		bound^[e.binding] = true
		body_free := cc_free_vars(e.body, bound)
		for v in body_free {
			append(&result, v)
		}
		delete(body_free)
	case ^IR_Call:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {
				append(&result, v)
			}
			delete(inner)
		}
	case ^IR_Closure_Call:
		callee := cc_free_vars(e.callee, bound)
		for v in callee { append(&result, v) }
		delete(callee)
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {
				append(&result, v)
			}
			delete(inner)
		}
	case ^IR_If:
		cond := cc_free_vars(e.condition, bound)
		then_br := cc_free_vars(e.then_branch, bound)
		else_br := cc_free_vars(e.else_branch, bound)
		for v in cond { append(&result, v) }
		for v in then_br { append(&result, v) }
		for v in else_br { append(&result, v) }
		delete(cond)
		delete(then_br)
		delete(else_br)
	case ^IR_BinOp:
		l := cc_free_vars(e.left, bound)
		r := cc_free_vars(e.right, bound)
		for v in l { append(&result, v) }
		for v in r { append(&result, v) }
		delete(l)
		delete(r)
	case ^IR_Crash:
		inner := cc_free_vars(e.message, bound)
		for v in inner { append(&result, v) }
		delete(inner)
	case ^IR_Return:
		inner := cc_free_vars(e.value, bound)
		for v in inner { append(&result, v) }
		delete(inner)
	case ^IR_Block:
		for stmt in e.statements {
			inner := cc_free_vars(stmt, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Construct_Tag:
		for p in e.payload {
			inner := cc_free_vars(p, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Construct_Record:
		for f in e.fields {
			inner := cc_free_vars(f.value, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
		rest := cc_free_vars(e.rest, bound)
		for v in rest { append(&result, v) }
		delete(rest)
	case ^IR_Field_Access:
		inner := cc_free_vars(e.record, bound)
		for v in inner { append(&result, v) }
		delete(inner)
	case ^IR_Method_Call:
		recv := cc_free_vars(e.receiver, bound)
		for v in recv { append(&result, v) }
		delete(recv)
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Handle:
		body := cc_free_vars(e.body, bound)
		for v in body { append(&result, v) }
		delete(body)
		for arm in e.arms {
			bound^[arm.params[0]] = true
			inner := cc_free_vars(arm.body, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Perform:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Resume:
		if _, ok := bound^[e.resume_id]; !ok {
			already := false
			for v in result {
				if v == e.resume_id {
					already = true
					break
				}
			}
			if !already {
				append(&result, e.resume_id)
			}
		}
		inner := cc_free_vars(e.value, bound)
		for v in inner { append(&result, v) }
		delete(inner)
		if e.ev != nil {
			ev_free := cc_free_vars(e.ev, bound)
			for v in ev_free { append(&result, v) }
			delete(ev_free)
		}
	case ^IR_Closure:
		inner := cc_free_vars(e.body, bound)
		for v in inner { append(&result, v) }
		delete(inner)
	case ^IR_Assign:
		inner := cc_free_vars(e.value, bound)
		for v in inner { append(&result, v) }
		delete(inner)
	case ^IR_Loop:
		iter := cc_free_vars(e.iterable, bound)
		for v in iter { append(&result, v) }
		delete(iter)
		body := cc_free_vars(e.body, bound)
		for v in body { append(&result, v) }
		delete(body)
	case ^IR_Match:
		scrut := cc_free_vars(e.scrutinee, bound)
		for v in scrut { append(&result, v) }
		delete(scrut)
		for arm in e.arms {
			cc_bind_pattern_vars(arm.pattern, bound)
			inner := cc_free_vars(arm.body, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Dup,
	     ^IR_Drop,
	     ^IR_Drop_Reuse,
	     ^IR_Alloc_At,
	     ^IR_I32_Load,
	     ^IR_I32_Store,
	     ^IR_Atomic_Load,
	     ^IR_Atomic_Store,
	     ^IR_Atomic_RMW,
	     ^IR_Atomic_Fence,
	     ^IR_Wait,
	     ^IR_Notify,
	     ^IR_Expr_Nominal_Construct:
	}

	return result
}

cc_bind_pattern_vars :: proc(pat: IR_Pattern, bound: ^map[base.Intern_ID]bool) {
	#partial switch p in pat {
	case ^IR_Pat_Var:
		bound^[p.name] = true
	case ^IR_Pat_Tag:
		for v in p.payload {
			bound^[v] = true
		}
	case ^IR_Pat_Record:
		for f in p.fields {
			bound^[f.binding] = true
		}
	case ^IR_Pat_Wildcard, ^IR_Pat_Bool, ^IR_Pat_Int, ^IR_Pat_String:
	}
}

closure_convert :: proc(mod: ^IR_Module, interner: ^base.Intern_Table) -> IR_Module {
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

	env: Closure_Convert_Env
	env.module = &result
	env.interner = interner
	env.fresh_state = base.Fresh_State{counter = 0, interner = interner}

	for decl in mod.decls {
		transformed := cc_convert_decl(decl, &env)
		append(&result.decls, transformed)
	}

	return result
}

cc_convert_decl :: proc(decl: IR_Decl, env: ^Closure_Convert_Env) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^
		new_fn.body = cc_convert_expr(d.body, env)
		return IR_Decl(new_fn)
	case ^IR_Decl_Const:
		new_const := new(IR_Decl_Const)
		new_const^ = d^
		new_const.value = cc_convert_expr(d.value, env)
		return IR_Decl(new_const)
	case ^IR_Decl_Effect:
		return decl
	}
	return decl
}

cc_convert_expr :: proc(expr: IR_Expr, env: ^Closure_Convert_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Closure:
		// If fn_name is set and body is nil, this is a reference closure
		// pointing to an already-created IR_Decl_Fn (e.g., from effect_lower)
		if e.body == nil && e.fn_name.name != base.NO_NAME {
			// Use IR_Var referencing the function by name — codegen resolves via func_map
			fields := make([dynamic]IR_Record_Field, 0, 2)
			fn_idx_id := base.intern(env.interner, "fn_idx")
			fn_idx_var := new(IR_Var)
			fn_idx_var^ = IR_Var{name = e.fn_name.name, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}
			append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_var)})

			// Add env as a field
			env_id := base.intern(env.interner, "env")
			append(&fields, IR_Record_Field{name = env_id, value = e.env})

			rest_nil := new(IR_Literal_Int)
			rest_nil^ = IR_Literal_Int{value = 0, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}

			rec := new(IR_Construct_Record)
			rec^ = IR_Construct_Record{
				fields = fields,
				rest = IR_Expr(rest_nil),
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			return IR_Expr(rec)
		}

		env_param_name := base.fresh_id(&env.fresh_state, "_cenv")

		bound: map[base.Intern_ID]bool
		bound = make(map[base.Intern_ID]bool, 8)
		bound[env_param_name] = true
		for p in e.params {
			bound[p.name] = true
		}

		free := cc_free_vars(e.body, &bound)

		params := make([dynamic]IR_Param, 0, len(e.params) + 1)
		append(&params, IR_Param{name = env_param_name, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}})
		for p in e.params {
			append(&params, p)
		}

		closed_fn_name := base.Canonical_Name{
			module = base.NO_NAME,
			name = base.fresh_id(&env.fresh_state, "closed"),
			is_local = true,
		}

		env_access_map: map[base.Intern_ID]IR_Expr
		env_access_map = make(map[base.Intern_ID]IR_Expr, len(free))
		field_offset: u32 = 8
		for fv in free {
			env_access_map[fv] = make_env_field_access(env_param_name, field_offset, e.span, env.interner)
			field_offset += 4
		}

		converted_body := cc_convert_expr(e.body, env)

		closed_fn := new(IR_Decl_Fn)
	closed_fn^ = IR_Decl_Fn{
		name = closed_fn_name,
		is_effectful = false,
		params = params,
		return_type = e.return_type,
		effect_row = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
		effects = make([dynamic]base.Canonical_Name, 0),
		body = rewrite_free_var_access(converted_body, &env_access_map),
		span = e.span,
	}
		append(&env.module.decls, IR_Decl(closed_fn))

		fn_idx_var := new(IR_Var)
		fn_idx_var^ = IR_Var{name = closed_fn_name.name, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}

		fields := make([dynamic]IR_Record_Field, 0, len(free) + 1)
		fn_idx_id := base.intern(env.interner, "fn_idx")
		append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_var)})

		for fv in free {
			fv_var := new(IR_Var)
			fv_var^ = IR_Var{name = fv, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}
			append(&fields, IR_Record_Field{name = fv, value = IR_Expr(fv_var)})
		}

		rest_nil := new(IR_Literal_Int)
		rest_nil^ = IR_Literal_Int{value = 0, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}

		rec := new(IR_Construct_Record)
		rec^ = IR_Construct_Record{
			fields = fields,
			rest = IR_Expr(rest_nil),
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
			span = e.span,
		}

		delete(env_access_map)
		delete(bound)
		delete(free)
		return IR_Expr(rec)

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = cc_convert_expr(e.value, env),
			body = cc_convert_expr(e.body, env),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = cc_convert_expr(e.callee, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call{callee = e.callee, args = new_args, span = e.span}
		return IR_Expr(new_tc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = cc_convert_expr(e.condition, env),
			then_branch = cc_convert_expr(e.then_branch, env),
			else_branch = cc_convert_expr(e.else_branch, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = cc_convert_expr(arm.body, env)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = cc_convert_expr(e.scrutinee, env),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, cc_convert_expr(p, env))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, tag_index = e.tag_index, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = cc_convert_expr(f.value, env)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = cc_convert_expr(e.rest, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{record = cc_convert_expr(e.record, env), field = e.field, field_index = e.field_index, type = e.type, span = e.span}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{
			receiver = cc_convert_expr(e.receiver, env),
			method = e.method,
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Handle:
		body := cc_convert_expr(e.body, env)
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Handler_Arm{op = arm.op, params = arm.params, body = cc_convert_expr(arm.body, env)})
		}
		effects := make([dynamic]base.Canonical_Name, 0, len(e.effects))
		for eff in e.effects {
			append(&effects, eff)
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle{
			effects = effects,
			body = body,
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform{effect = e.effect, op = e.op, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_perf)

	case ^IR_Resume:
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = cc_convert_expr(e.ev, env)
		}
		new_resume^ = IR_Resume{
			resume_id = e.resume_id,
			value = cc_convert_expr(e.value, env),
			ev = ev_val,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = cc_convert_expr(e.value, env), span = e.span}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, cc_convert_expr(stmt, env))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = cc_convert_expr(e.left, env),
			right = cc_convert_expr(e.right, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = cc_convert_expr(e.message, env), span = e.span}
		return IR_Expr(new_crash)

	case ^IR_Atomic_Load:
		return IR_Expr(e)
	case ^IR_Atomic_Store:
		return IR_Expr(e)
	case ^IR_Atomic_RMW:
		return IR_Expr(e)
	case ^IR_Atomic_Fence:
		return IR_Expr(e)
	case ^IR_Wait:
		return IR_Expr(e)
	case ^IR_Notify:
		return IR_Expr(e)
	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign{
			binding = e.binding,
			value   = cc_convert_expr(e.value, env),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop{
			var      = e.var,
			iterable = cc_convert_expr(e.iterable, env),
			body     = cc_convert_expr(e.body, env),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	}

	return expr
}

make_env_field_access :: proc(env_name: base.Intern_ID, offset: u32, span: base.Source_Span, interner: ^base.Intern_Table) -> IR_Expr {
	env_var := new(IR_Var)
	env_var^ = IR_Var{name = env_name, type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = span}

	field_access := new(IR_Field_Access)
	field_access^ = IR_Field_Access{
		record = IR_Expr(env_var),
		field = base.intern(interner, fmt.tprintf("env_{}", offset)),
		field_index = int((offset - 8) / 4),
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
		span = span,
	}
	return IR_Expr(field_access)
}

rewrite_free_var_access :: proc(expr: IR_Expr, env_map: ^map[base.Intern_ID]IR_Expr) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Var:
		if replacement, ok := env_map^[e.name]; ok {
			return replacement
		}
		return expr
	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = rewrite_free_var_access(e.value, env_map),
			body = rewrite_free_var_access(e.body, env_map),
			span = e.span,
		}
		return IR_Expr(new_let)
	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rewrite_free_var_access(arg, env_map))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)
	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rewrite_free_var_access(arg, env_map))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = rewrite_free_var_access(e.callee, env_map),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)
	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = rewrite_free_var_access(e.left, env_map),
			right = rewrite_free_var_access(e.right, env_map),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)
	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = rewrite_free_var_access(e.condition, env_map),
			then_branch = rewrite_free_var_access(e.then_branch, env_map),
			else_branch = rewrite_free_var_access(e.else_branch, env_map),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)
	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = rewrite_free_var_access(e.value, env_map), span = e.span}
		return IR_Expr(new_ret)
	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, rewrite_free_var_access(stmt, env_map))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)
	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = rewrite_free_var_access(arm.body, env_map)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = rewrite_free_var_access(e.scrutinee, env_map),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)
	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, rewrite_free_var_access(p, env_map))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, tag_index = e.tag_index, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)
	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = rewrite_free_var_access(f.value, env_map)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = rewrite_free_var_access(e.rest, env_map),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)
	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{
			record = rewrite_free_var_access(e.record, env_map),
			field = e.field,
			field_index = e.field_index,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_fa)
	case ^IR_Resume:
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = rewrite_free_var_access(e.ev, env_map)
		}
		new_resume^ = IR_Resume{
			resume_id = e.resume_id,
			value = rewrite_free_var_access(e.value, env_map),
			ev = ev_val,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_resume)
	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign{
			binding = e.binding,
			value   = rewrite_free_var_access(e.value, env_map),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop{
			var      = e.var,
			iterable = rewrite_free_var_access(e.iterable, env_map),
			body     = rewrite_free_var_access(e.body, env_map),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Tail_Call,
	     ^IR_Expr_Nominal_Construct,
	     ^IR_Method_Call,
	     ^IR_Handle,
	     ^IR_Perform,
	     ^IR_Closure,
	     ^IR_Dup,
	     ^IR_Drop,
	     ^IR_Drop_Reuse,
	     ^IR_Alloc_At,
	     ^IR_Crash,
	     ^IR_I32_Load,
	     ^IR_I32_Store,
	     ^IR_Atomic_Load,
	     ^IR_Atomic_Store,
	     ^IR_Atomic_RMW,
	     ^IR_Atomic_Fence,
	     ^IR_Wait,
	     ^IR_Notify:
		return expr
	}
	return expr
}

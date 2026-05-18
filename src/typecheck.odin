package camp

import "core:fmt"

Type_Env :: struct {
	bindings: map[Intern_ID]Type_Var_ID,
	parent:   ^Type_Env,
}

Type_Result :: struct {
	var_id:  Type_Var_ID,
	effects: Type_Var_ID,
}

typecheck_file :: proc(file: CFile, store: ^Type_Store) {
	env: Type_Env
	env.bindings = make(map[Intern_ID]Type_Var_ID, 64)
	env.parent = nil
	defer delete(env.bindings)

	for decl in file.decls {
		typecheck_decl(decl, &env, store)
	}
}

typecheck_decl :: proc(decl: CDecl, env: ^Type_Env, store: ^Type_Store) {
	switch d in decl {
	case ^CDecl_Const:
		enter_level(store)
		result := typecheck_synth(d.body, env, store)

		if d.type_ann != nil {
			ann_var := convert_type_to_var(d.type_ann, store)
			unify(store, result.var_id, ann_var)
		}

		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		env.bindings[d.name.name] = result.var_id

	case ^CDecl_Effect:
		for op in d.operations {
			for p in op.params {
				if p.type_ann != nil {
					convert_type_to_var(p.type_ann, store)
				}
			}
			if op.return_type != nil {
				convert_type_to_var(op.return_type, store)
			}
		}

	case ^CDecl_Trait:
		for m in d.methods {
			for p in m.params {
				if p.type_ann != nil {
					convert_type_to_var(p.type_ann, store)
				}
			}
			if m.return_type != nil {
				convert_type_to_var(m.return_type, store)
			}
		}

	case ^CDecl_Alias:
		convert_type_to_var(d.target, store)

	case ^CDecl_Test:
		typecheck_synth(d.body, env, store)

	case ^CDecl_Expect:
		result := typecheck_synth(d.condition, env, store)
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, Source_Span_ZERO)
		unify(store, result.var_id, bool_var)

	case ^CDecl_Import:
		return
	}
}

typecheck_synth :: proc(expr: CExpr, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	switch e in expr {
	case ^CExpr_Int:
		name := intern(store.interner, "I64")
		var_id := make_primitive_type(store, name, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_Float:
		name := intern(store.interner, "F64")
		var_id := make_primitive_type(store, name, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_String:
		name := intern(store.interner, "Str")
		var_id := make_primitive_type(store, name, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_Bool:
		name := intern(store.interner, "Bool")
		var_id := make_primitive_type(store, name, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_Name:
		if existing, ok := env.bindings[e.name.name]; ok {
			inst := instantiate(store, existing)
			return Type_Result{var_id = inst, effects = fresh_effect_row(store, e.span)}
		}
		var_id := fresh_value_var(store, e.span)
		collector_add(store.collector, .Error,
			fmt.tprintf("undefined name: {}", e.name.name),
			e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_Lambda:
		return typecheck_lambda(e, env, store)

	case ^CExpr_Call:
		return typecheck_call(e, env, store)

	case ^CExpr_If:
		return typecheck_if(e, env, store)

	case ^CExpr_Block:
		return typecheck_block(e, env, store)

	case ^CExpr_BinOp:
		return typecheck_binop(e, env, store)

	case ^CExpr_PrefixOp:
		return typecheck_prefixop(e, env, store)

	case ^CExpr_Tag:
		return typecheck_tag(e, env, store)

	case ^CExpr_Record:
		return typecheck_record(e, env, store)

	case ^CExpr_Field_Access:
		return typecheck_field_access(e, env, store)

	case ^CExpr_Match:
		return typecheck_match(e, env, store)

	case ^CExpr_List:
		return typecheck_list(e, env, store)

	case ^CExpr_Record_Update:
		return typecheck_record_update(e, env, store)

	case ^CExpr_Assign:
		result := typecheck_synth(e.value, env, store)
		return Type_Result{var_id = result.var_id, effects = result.effects}

	case ^CExpr_Return:
		result := typecheck_synth(e.value, env, store)
		return Type_Result{var_id = result.var_id, effects = result.effects}

	case ^CExpr_Crash:
		var_id := fresh_value_var(store, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}

	case ^CExpr_Interpolate:
		str_name := intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, e.span)
		eff := fresh_effect_row(store, e.span)
		for part in e.parts {
			part_result := typecheck_synth(part, env, store)
			unify(store, part_result.var_id, str_var)
			unify(store, eff, part_result.effects)
		}
		return Type_Result{var_id = str_var, effects = eff}

	case ^CExpr_Method_Call:
		return typecheck_method_call(e, env, store)
	}
	var_id := fresh_value_var(store, Source_Span_ZERO)
	return Type_Result{var_id = var_id, effects = fresh_effect_row(store, Source_Span_ZERO)}
}

typecheck_lambda :: proc(e: ^CExpr_Lambda, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	child_env: Type_Env
	child_env.bindings = make(map[Intern_ID]Type_Var_ID, len(e.params) + 4)
	child_env.parent = env
	defer delete(child_env.bindings)

	for param in e.params {
		param_var := fresh_value_var(store, param.span)
		if param.type_ann != nil {
			ann_var := convert_type_to_var(param.type_ann, store)
			unify(store, param_var, ann_var)
		}
		child_env.bindings[param.name] = param_var
	}

	body_result := typecheck_synth(e.body, &child_env, store)

	effect_row := fresh_effect_row(store, e.span)
	if e.effects != nil {
		ann_effects := convert_type_to_var(e.effects, store)
		unify(store, effect_row, ann_effects)
	} else {
		unify(store, effect_row, body_result.effects)
	}

	return_var := fresh_value_var(store, e.span)
	if e.return_type != nil {
		ann_return := convert_type_to_var(e.return_type, store)
		unify(store, return_var, ann_return)
		unify(store, body_result.var_id, ann_return)
	} else {
		unify(store, return_var, body_result.var_id)
	}

	return Type_Result{var_id = return_var, effects = fresh_effect_row(store, e.span)}
}

typecheck_call :: proc(e: ^CExpr_Call, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	callee_result := typecheck_synth(e.callee, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, callee_result.effects)

	for arg in e.args {
		arg_result := typecheck_synth(arg, env, store)
		unify(store, eff, arg_result.effects)
	}

	return_var := fresh_value_var(store, e.span)
	return Type_Result{var_id = return_var, effects = eff}
}

typecheck_if :: proc(e: ^CExpr_If, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	cond_result := typecheck_synth(e.condition, env, store)
	bool_name := intern(store.interner, "Bool")
	bool_var := make_primitive_type(store, bool_name, e.span)
	unify(store, cond_result.var_id, bool_var)

	then_result := typecheck_synth(e.then_branch, env, store)
	else_result := typecheck_synth(e.else_branch, env, store)

	unify(store, then_result.var_id, else_result.var_id)

	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, cond_result.effects)
	unify(store, effect_row, then_result.effects)
	unify(store, effect_row, else_result.effects)

	return Type_Result{var_id = then_result.var_id, effects = effect_row}
}

typecheck_block :: proc(e: ^CExpr_Block, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	if len(e.statements) == 0 {
		unit_name := intern(store.interner, "Unit")
		var_id := make_primitive_type(store, unit_name, e.span)
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}
	}

	last_result: Type_Result
	effect_row := fresh_effect_row(store, e.span)
	for stmt in e.statements {
		last_result = typecheck_synth(stmt, env, store)
		unify(store, effect_row, last_result.effects)
	}
	return Type_Result{var_id = last_result.var_id, effects = effect_row}
}

typecheck_binop :: proc(e: ^CExpr_BinOp, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	left_result := typecheck_synth(e.left, env, store)
	right_result := typecheck_synth(e.right, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, left_result.effects)
	unify(store, eff, right_result.effects)

	#partial switch e.op {
	case .Kw_And, .Kw_Or:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, left_result.var_id, bool_var)
		unify(store, right_result.var_id, bool_var)
		return Type_Result{var_id = bool_var, effects = eff}

	case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		unify(store, left_result.var_id, right_result.var_id)
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		return Type_Result{var_id = bool_var, effects = eff}

	case .Plus, .Minus, .Star, .Slash, .Percent, .Caret:
		unify(store, left_result.var_id, right_result.var_id)
		return Type_Result{var_id = left_result.var_id, effects = eff}

	case:
		return Type_Result{var_id = left_result.var_id, effects = eff}
	}
}

typecheck_prefixop :: proc(e: ^CExpr_PrefixOp, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	operand_result := typecheck_synth(e.operand, env, store)

	#partial switch e.op {
	case .Kw_Not:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, operand_result.var_id, bool_var)
		return Type_Result{var_id = bool_var, effects = operand_result.effects}
	case .Minus:
		return Type_Result{var_id = operand_result.var_id, effects = operand_result.effects}
	case:
		return Type_Result{var_id = operand_result.var_id, effects = operand_result.effects}
	}
}

typecheck_tag :: proc(e: ^CExpr_Tag, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, e.span)
	for p in e.payload {
		p_result := typecheck_synth(p, env, store)
		unify(store, eff, p_result.effects)
	}
	tag_var := fresh_value_var(store, e.span)
	return Type_Result{var_id = tag_var, effects = eff}
}

typecheck_record :: proc(e: ^CExpr_Record, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, e.span)
	for field in e.fields {
		field_result := typecheck_synth(field.value, env, store)
		unify(store, eff, field_result.effects)
	}
	_, has_rest := e.rest.(^CExpr_Record)
	if has_rest {
		rest_result := typecheck_synth(e.rest, env, store)
		unify(store, eff, rest_result.effects)
	}
	var_id := fresh_value_var(store, e.span)
	return Type_Result{var_id = var_id, effects = eff}
}

typecheck_field_access :: proc(e: ^CExpr_Field_Access, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	record_result := typecheck_synth(e.record, env, store)
	var_id := fresh_value_var(store, e.span)
	return Type_Result{var_id = var_id, effects = record_result.effects}
}

typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, e.span)
		return Type_Result{var_id = var_id, effects = scrutinee_result.effects}
	}

	first_result := typecheck_synth(e.arms[0].body, env, store)
	result_var := first_result.var_id
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)
	unify(store, effect_row, first_result.effects)

	for i := 1; i < len(e.arms); i += 1 {
		arm_result := typecheck_synth(e.arms[i].body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)
	}

	return Type_Result{var_id = result_var, effects = effect_row}
}

typecheck_list :: proc(e: ^CExpr_List, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	element_var := fresh_value_var(store, e.span)
	eff := fresh_effect_row(store, e.span)

	for el in e.elements {
		el_result := typecheck_synth(el, env, store)
		unify(store, element_var, el_result.var_id)
		unify(store, eff, el_result.effects)
	}

	var_id := fresh_value_var(store, e.span)
	return Type_Result{var_id = var_id, effects = eff}
}

typecheck_record_update :: proc(e: ^CExpr_Record_Update, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	rest_result := typecheck_synth(e.rest, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, rest_result.effects)

	for u in e.updates {
		u_result := typecheck_synth(u.value, env, store)
		unify(store, eff, u_result.effects)
	}

	return Type_Result{var_id = rest_result.var_id, effects = eff}
}

typecheck_method_call :: proc(e: ^CExpr_Method_Call, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	receiver_result := typecheck_synth(e.receiver, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, receiver_result.effects)

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
	}

	return_var := fresh_value_var(store, e.span)
	return Type_Result{var_id = return_var, effects = eff}
}

convert_type_to_var :: proc(t: ^CType, store: ^Type_Store) -> Type_Var_ID {
	return convert_type_to_var_val(t^, store)
}

convert_type_to_var_val :: proc(t: CType, store: ^Type_Store) -> Type_Var_ID {
	switch ty in t {
	case ^CType_Primitive:
		return make_primitive_type(store, ty.name, ty.span)

	case ^CType_Variable:
		return fresh_value_var(store, ty.span)

	case ^CType_Wildcard:
		return fresh_value_var(store, ty.span)

	case ^CType_Function:
		for p in ty.params {
			convert_type_to_var_val(p, store)
		}
		if ty.effects != nil {
			convert_type_to_var(ty.effects, store)
		}
		convert_type_to_var_val(ty.return_, store)
		return fresh_value_var(store, ty.span)

	case ^CType_Applied:
		for &a in ty.args {
			convert_type_to_var_val(a, store)
		}
		return fresh_value_var(store, ty.span)

	case ^CType_Record:
		for &f in ty.fields {
			convert_type_to_var_val(f.type, store)
		}
		return fresh_value_var(store, ty.span)

	case ^CType_Tag_Union:
		for &tg in ty.tags {
			for &p in tg.payload {
				convert_type_to_var_val(p, store)
			}
		}
		return fresh_value_var(store, ty.span)

	case ^CType_Effect_Row:
		return fresh_effect_row(store, ty.span)
	}
	return fresh_value_var(store, Source_Span_ZERO)
}

instantiate :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> Type_Var_ID {
	resolved := resolve_var(store, var_id)
	v := get_var(store, resolved)

	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked && is_generic(store, resolved) {
		new_id := fresh_var(store, v.kind, v.name, v.span)
		return new_id
	}

	return resolved
}

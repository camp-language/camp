package semantics

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:diagnostics"
import "camp:frontend"

typecheck_lambda :: proc(e: ^CExpr_Lambda, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	child_env: Type_Env
	child_env.bindings = make(
		map[base.Intern_ID]base.Type_Var_ID,
		len(e.params) + len(e.type_params) + 4,
	)
	child_env.parent = env
	child_env.handled_effects = make([dynamic]base.Intern_ID, 0, 8)
	child_env.current_module = env.current_module
	child_env.spawned_handles = make([dynamic]base.Source_Span, 0, 8)
	defer delete(child_env.bindings)
	defer delete(child_env.handled_effects)
	defer delete(child_env.spawned_handles)
	defer {
		for span in child_env.spawned_handles {
			diagnostics.collector_add_diag(store.collector, diagnostics.diag_unjoined_spawn(span))
		}
	}

	param_ids := store_alloc(store, base.Type_Var_ID, len(e.params))

	mark_effect_type_params_in_ctype(e.type_params, e.effects)

	for tp in e.type_params {
		tv: base.Type_Var_ID
		if tp.is_effect {
			tv = fresh_effect_row(store, e.span)
		} else {
			tv = fresh_value_var(store, e.span)
		}
		check_shadow(&child_env, tp.name, store, e.span)
		child_env.bindings[tp.name] = tv
		env.bindings[tp.name] = tv
		store.type_constraints[tv] = tp.constraints[:]
	}

	params_t := make([dynamic]TFunc_Param, len(e.params))
	for i in 0 ..< len(e.params) {
		param := e.params[i]
		param_var := fresh_value_var(store, param.span)
		if param.type_ann != nil {
			ann_var := convert_type_to_var(param.type_ann, store, &child_env)
			unify(store, param_var, ann_var)
		}
		check_shadow(&child_env, param.name, store, param.span)
		child_env.bindings[param.name] = param_var
		param_ids[i] = param_var
		params_t[i] = TFunc_Param {
			name = param.name,
			eff_ = lower_effect_type(store, fresh_effect_row(store, param.span)),
			span = param.span,
		}
	}

	body_result := typecheck_synth(e.body, &child_env, store)

	// Lower each param's type only after the body has been checked — the body
	// (e.g. a `match` on the param) is what constrains an otherwise-free param
	// var. Lowering earlier captured the free var as .I64, contradicting the
	// i32 heap value of a list/tag-union argument at the call boundary.
	for i in 0 ..< len(e.params) {
		params_t[i].type_ = lower_type(store, param_ids[i])
	}

	effect_id := fresh_effect_row(store, e.span)
	unify(store, effect_id, body_result.effects)
	if e.effects != nil {
		ann_effects := convert_type_to_var(e.effects, store, &child_env)
		unify(store, effect_id, ann_effects)
	}

	return_id := fresh_value_var(store, e.span)
	if e.return_type != nil {
		ann_return := convert_type_to_var(e.return_type, store, &child_env)
		unify(store, return_id, ann_return)
		unify(store, body_result.var_id, ann_return)
	} else {
		unify(store, return_id, body_result.var_id)
	}

	fn_var := fresh_value_var(store, e.span)
	link_var(
		store,
		fn_var,
		Inferred_Function{param_ids = param_ids, return_id = return_id, effect_id = effect_id},
	)

	outer_eff := fresh_effect_row(store, e.span)
	t := new(TExpr_Lambda)
	t^ = TExpr_Lambda {
		type_params = e.type_params,
		params      = params_t,
		return_type = lower_type(store, return_id),
		effects     = lower_effect_type(store, effect_id),
		body        = body_result.texpr,
		type_       = lower_type(store, fn_var),
		eff_        = lower_effect_type(store, outer_eff),
		span        = e.span,
	}
	return Synth_Result{var_id = fn_var, effects = outer_eff, texpr = TExpr(t)}
}

typecheck_call :: proc(e: ^CExpr_Call, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	callee_result := typecheck_synth(e.callee, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, callee_result.effects)

	args_t := make([dynamic]TExpr, len(e.args))
	param_ids := store_alloc(store, base.Type_Var_ID, len(e.args))
	for i in 0 ..< len(e.args) {
		arg_result := typecheck_synth(e.args[i], env, store)
		unify(store, eff, arg_result.effects)
		param_ids[i] = arg_result.var_id
		args_t[i] = arg_result.texpr
	}

	return_var := fresh_value_var(store, e.span)
	callee_effect := fresh_effect_row(store, e.span)

	expected_fn := Inferred_Function {
		param_ids = param_ids,
		return_id = return_var,
		effect_id = callee_effect,
	}
	expected_fn_var := fresh_value_var(store, e.span)
	link_var(store, expected_fn_var, expected_fn)

	unify(store, callee_result.var_id, expected_fn_var)
	unify(store, eff, callee_effect)

	t := new(TExpr_Call)
	t^ = TExpr_Call {
		callee = callee_result.texpr,
		args   = args_t,
		type_  = lower_type(store, return_var),
		eff_   = lower_effect_type(store, eff),
		span   = e.span,
	}
	return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
}

typecheck_if :: proc(e: ^CExpr_If, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	cond_result := typecheck_synth(e.condition, env, store)
	bool_name := base.intern(store.interner, "Bool")
	bool_var := make_primitive_type(store, bool_name, e.span)
	unify(store, cond_result.var_id, bool_var)

	then_result := typecheck_synth(e.then_branch, env, store)
	else_result := typecheck_synth(e.else_branch, env, store)

	unify(store, then_result.var_id, else_result.var_id)

	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, cond_result.effects)
	unify(store, effect_row, then_result.effects)
	unify(store, effect_row, else_result.effects)

	t := new(TExpr_If)
	t^ = TExpr_If {
		condition   = cond_result.texpr,
		then_branch = then_result.texpr,
		else_branch = else_result.texpr,
		type_       = lower_type(store, then_result.var_id),
		eff_        = lower_effect_type(store, effect_row),
		span        = e.span,
	}
	return Synth_Result{var_id = then_result.var_id, effects = effect_row, texpr = TExpr(t)}
}

typecheck_block :: proc(e: ^CExpr_Block, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	if len(e.statements) == 0 {
		unit_name := base.intern(store.interner, "Unit")
		var_id := make_primitive_type(store, unit_name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Block)
		t^ = TExpr_Block {
			type_ = lower_type(store, var_id),
			eff_  = lower_effect_type(store, eff),
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	last_result: Synth_Result
	effect_row := fresh_effect_row(store, e.span)
	stmts_t := make([dynamic]TExpr, 0, len(e.statements))
	for stmt in e.statements {
		last_result = typecheck_synth(stmt, env, store)
		unify(store, effect_row, last_result.effects)
		append(&stmts_t, last_result.texpr)
	}
	t := new(TExpr_Block)
	t^ = TExpr_Block {
		statements = stmts_t,
		type_      = lower_type(store, last_result.var_id),
		eff_       = lower_effect_type(store, effect_row),
		span       = e.span,
	}
	return Synth_Result{var_id = last_result.var_id, effects = effect_row, texpr = TExpr(t)}
}

typecheck_binop :: proc(e: ^CExpr_BinOp, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	left_result := typecheck_synth(e.left, env, store)
	right_result := typecheck_synth(e.right, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, left_result.effects)
	unify(store, eff, right_result.effects)

	result_var: base.Type_Var_ID
	#partial switch e.op {
	case .Kw_And, .Kw_Or:
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, left_result.var_id, bool_var)
		unify(store, right_result.var_id, bool_var)
		result_var = bool_var

	case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		unify(store, left_result.var_id, right_result.var_id)
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		result_var = bool_var
		// Check Eq conformance for the unified type
		unified_type := resolve_var(store, left_result.var_id)
		type_var := &store.vars[int(unified_type)]
		if inf, is_inf := type_var.link.(Inferred_Type); is_inf {
			switch inf in {
			case Inferred_Record_Row, Inferred_Tag_Union_Row, Inferred_Tuple, Inferred_Constructor:
				// Structural types auto-derive Eq
				result_var = base.NO_NAME
			case Inferred_Primitive:
				type_name := inf.primitive_name
				eq_name := base.intern(store.interner, "Eq")
				_, has_impl := find_trait_impl(store, eq_name, type_name)
				if !has_impl {
					type_str := base.intern_get(store.interner, type_name)
					diagnostics.collector_add_diag(
						store.collector,
						diag_missing_trait_method(
							type_str,
							"eq",
							"Eq",
							e.span,
						),
					)
					result_var = base.NO_NAME
				}
			}
		}
	case .Plus, .Minus, .Star, .Slash, .Percent, .Caret, .Lt_Lt, .Gt_Gt:
		unify(store, left_result.var_id, right_result.var_id)
		result_var = left_result.var_id

	case:
		op_str := fmt.tprintf("{}", e.op)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_internal(
				fmt.tprintf("unhandled binary operator in typechecker: {}", op_str),
				e.span,
			),
		)
		result_var = left_result.var_id
	}

	t := new(TExpr_BinOp)
	t^ = TExpr_BinOp {
		op    = e.op,
		left  = left_result.texpr,
		right = right_result.texpr,
		type_ = lower_type(store, result_var),
		eff_  = lower_effect_type(store, eff),
		span  = e.span,
	}
	return Synth_Result{var_id = result_var, effects = eff, texpr = TExpr(t)}
}

typecheck_prefixop :: proc(
	e: ^CExpr_PrefixOp,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	operand_result := typecheck_synth(e.operand, env, store)

	result_var: base.Type_Var_ID
	result_eff: base.Type_Var_ID
	#partial switch e.op {
	case .Kw_Not:
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, operand_result.var_id, bool_var)
		result_var = bool_var
		result_eff = operand_result.effects
	case .Minus:
		result_var = operand_result.var_id
		result_eff = operand_result.effects
	case:
		op_str := fmt.tprintf("{}", e.op)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_internal(
				fmt.tprintf("unhandled prefix operator in typechecker: {}", op_str),
				e.span,
			),
		)
		result_var = operand_result.var_id
		result_eff = operand_result.effects
	}

	t := new(TExpr_PrefixOp)
	t^ = TExpr_PrefixOp {
		op      = e.op,
		operand = operand_result.texpr,
		type_   = lower_type(store, result_var),
		eff_    = lower_effect_type(store, result_eff),
		span    = e.span,
	}
	return Synth_Result{var_id = result_var, effects = result_eff, texpr = TExpr(t)}
}

typecheck_tag :: proc(e: ^CExpr_Tag, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	if is_declared_newtype(store, e.name.name) {
		if len(e.payload) == 1 {
			return typecheck_newtype_construct(e, env, store)
		}
		if len(e.payload) == 0 {
			nt_binding, has_binding := env_lookup(env, e.name.name)
			if !has_binding {
				nt_binding = store.bindings[e.name.name]
			}
			inst := instantiate(store, nt_binding)
			payload_t := make([dynamic]TExpr, 0)
			t := new(TExpr_Tag)
			t^ = TExpr_Tag {
				name    = e.name,
				payload = payload_t,
				type_   = lower_type(store, inst),
				eff_    = lower_effect_type(store, eff),
				span    = e.span,
			}
			return Synth_Result{var_id = inst, effects = eff, texpr = TExpr(t)}
		}
	}

	nt_name, owned := newtype_owning_tag(store, e.name.name)
	if owned {
		nt_info := store.newtype_decls[nt_name]
		same_mod := is_same_module(env, nt_info.module)
		if !same_mod && !nt_info.pub_variants {
			nt_str := base.intern_get(store.interner, nt_name)
			tag_str := base.intern_get(store.interner, e.name.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_newtype_opaque_violation(
					nt_str,
					fmt.tprintf("construct variant {}", tag_str),
					e.span,
				),
			)
		} else if !same_mod && e.name.module == base.NO_NAME {
			nt_str := base.intern_get(store.interner, nt_name)
			tag_str := base.intern_get(store.interner, e.name.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_unqualified_tag(nt_str, tag_str, e.span),
			)
		} else if same_mod && e.name.module == base.NO_NAME && !nt_info.pub_variants {
			nt_str := base.intern_get(store.interner, nt_name)
			tag_str := base.intern_get(store.interner, e.name.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_unqualified_tag(nt_str, tag_str, e.span),
			)
		}
	}

	payload_ids := store_alloc(store, base.Type_Var_ID, len(e.payload))
	payload_t := make([dynamic]TExpr, len(e.payload))
	for p, i in e.payload {
		p_result := typecheck_synth(p, env, store)
		unify(store, eff, p_result.effects)
		payload_ids[i] = resolve_var(store, p_result.var_id)
		payload_t[i] = p_result.texpr
	}

	tag_var := fresh_value_var(store, e.span)
	rest_var := fresh_tag_row(store, e.span)
	tag_entries := store_alloc(store, Type_Tag_Entry, 1)
	tag_entries[0] = Type_Tag_Entry {
		name    = e.name.name,
		payload = payload_ids,
	}
	inf := Inferred_Tag_Union_Row {
		tag_entries = tag_entries,
		tag_rest    = resolve_var(store, rest_var),
	}
	link_var(store, tag_var, inf)

	t := new(TExpr_Tag)
	t^ = TExpr_Tag {
		name    = e.name,
		payload = payload_t,
		type_   = lower_type(store, tag_var),
		eff_    = lower_effect_type(store, eff),
		span    = e.span,
	}
	return Synth_Result{var_id = tag_var, effects = eff, texpr = TExpr(t)}
}

typecheck_nominal_construct :: proc(
	e: ^CExpr_Nominal_Construct,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)
	payload_t := make([dynamic]TExpr, len(e.payload))
	for p, i in e.payload {
		p_result := typecheck_synth(p, env, store)
		unify(store, eff, p_result.effects)
		payload_t[i] = p_result.texpr
	}
	resolved_type := fresh_value_var(store, e.span)
	resolved_var, found := env_lookup(env, e.type_name.name)
	if !found {
		if var, ok := store.bindings[e.type_name.name]; ok {
			resolved_var = var
			found = true
		}
	}
	if found {
		unify(store, resolved_type, resolved_var)
	} else {
		type_str := base.intern_get(store.interner, e.type_name.name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_undefined_type(type_str, []string{"newtype"}, e.span),
		)
	}
	t := new(TExpr_Nominal_Construct)
	t^ = TExpr_Nominal_Construct {
		type_name     = e.type_name,
		variant       = e.variant,
		payload       = payload_t,
		resolved_type = resolve_var(store, resolved_type),
		span          = e.span,
	}
	return Synth_Result{var_id = resolved_type, effects = eff, texpr = TExpr(t)}
}

typecheck_record :: proc(e: ^CExpr_Record, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	record_fields := store_alloc(store, Type_Field_Entry, len(e.fields))
	fields_t := make([dynamic]TRecord_Field, len(e.fields))
	for i in 0 ..< len(e.fields) {
		field := e.fields[i]
		field_result := typecheck_synth(field.value, env, store)
		unify(store, eff, field_result.effects)
		record_fields[i] = Type_Field_Entry {
			name = field.name,
			var  = field_result.var_id,
		}
		fields_t[i] = TRecord_Field {
			name  = field.name,
			value = field_result.texpr,
			span  = field.span,
		}
	}

	record_rest := fresh_record_row(store, e.span)
	rest_t: TExpr
	_, has_rest := e.rest.(^CExpr_Record)
	if has_rest {
		rest_result := typecheck_synth(e.rest, env, store)
		unify(store, eff, rest_result.effects)
		unify(store, record_rest, rest_result.var_id)
		rest_t = rest_result.texpr
	}

	var_id := fresh_value_var(store, e.span)
	link_var(
		store,
		var_id,
		Inferred_Record_Row {
			record_fields = record_fields,
			record_rest = record_rest,
			closed = false,
		},
	)

	t := new(TExpr_Record)
	t^ = TExpr_Record {
		fields  = fields_t,
		rest    = rest_t,
		is_open = e.is_open,
		type_   = lower_type(store, var_id),
		eff_    = lower_effect_type(store, eff),
		span    = e.span,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}
typecheck_tuple :: proc(e: ^CExpr_Tuple, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	element_types := store_alloc(store, base.Type_Var_ID, len(e.elements))
	elements_t := make([dynamic]TExpr, len(e.elements))
	for i in 0 ..< len(e.elements) {
		element_result := typecheck_synth(e.elements[i], env, store)
		unify(store, eff, element_result.effects)
		element_types[i] = element_result.var_id
		elements_t[i] = element_result.texpr
	}

	var_id := fresh_value_var(store, e.span)
	link_var(
		store,
		var_id,
		Inferred_Tuple {
			element_types = element_types,
			element_count = len(e.elements),
			closed = true,
		},
	)

	t := new(TExpr_Tuple)
	t^ = TExpr_Tuple {
		elements = elements_t,
		type_    = lower_type(store, var_id),
		eff_     = lower_effect_type(store, eff),
		span     = e.span,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_field_access :: proc(
	e: ^CExpr_Field_Access,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	record_result := typecheck_synth(e.record, env, store)
	field_var := fresh_value_var(store, e.span)
	rest_var := fresh_record_row(store, e.span)
	record_fields := store_alloc(store, Type_Field_Entry, 1)
	record_fields[0] = Type_Field_Entry {
		name = e.field,
		var  = resolve_var(store, field_var),
	}
	inf := Inferred_Record_Row {
		record_fields = record_fields,
		record_rest   = resolve_var(store, rest_var),
		closed        = false,
	}
	// Unify (not overwrite) so the record's existing fields are preserved.
	// Linking directly would clobber an already-inferred full record type
	// (e.g. `{ fst, snd }`) with the single-field constraint `{ field | rest }`,
	// losing the other fields and corrupting field offsets at codegen.
	constraint_var := fresh_value_var(store, e.span)
	link_var(store, constraint_var, inf)
	// Field access on a nominal record (`@Pt : { x, y }`) targets the inner
	// record, so unwrap one level of newtype before applying the constraint.
	// (Codegen's flatten_record_fields already unwraps the same way.)
	target_var := record_result.var_id
	rec_resolved := resolve_var(store, record_result.var_id)
	if rinf, rok := store.vars[int(rec_resolved)].link.(Inferred_Type); rok {
		if nt, is_nt := rinf.(Inferred_Newtype); is_nt {
			target_var = nt.inner_id
		}
	}
	unify(store, target_var, constraint_var)

	t := new(TExpr_Field_Access)
	t^ = TExpr_Field_Access {
		record = record_result.texpr,
		field  = e.field,
		type_  = lower_type(store, field_var),
		eff_   = lower_effect_type(store, record_result.effects),
		span   = e.span,
	}
	return Synth_Result{var_id = field_var, effects = record_result.effects, texpr = TExpr(t)}
}
typecheck_field_index :: proc(
	e: ^CExpr_Field_Index,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	record_result := typecheck_synth(e.record, env, store)

	element_count := 0
	record_var := resolve_var(store, record_result.var_id)
	rv := store.vars[int(record_var)]
	if inf, ok := rv.link.(Inferred_Type); ok {
		if tuple_inf, ok := inf.(Inferred_Tuple); ok {
			element_count = tuple_inf.element_count
		}
	}

	element_types := store_alloc(store, base.Type_Var_ID, element_count)
	for i in 0 ..< element_count {
		element_types[i] = fresh_value_var(store, e.span)
	}

	tuple_var := fresh_value_var(store, e.span)
	link_var(
		store,
		tuple_var,
		Inferred_Tuple {
			element_types = element_types,
			element_count = element_count,
			closed = true,
		},
	)
	unify(store, record_result.var_id, tuple_var)

	field_var := element_types[e.field_index]

	t := new(TExpr_Field_Index)
	t^ = TExpr_Field_Index {
		record      = record_result.texpr,
		field_index = e.field_index,
		type_       = lower_type(store, field_var),
		eff_        = lower_effect_type(store, record_result.effects),
		span        = e.span,
	}
	return Synth_Result{var_id = field_var, effects = record_result.effects, texpr = TExpr(t)}
}

typecheck_list :: proc(e: ^CExpr_List, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	element_var := fresh_value_var(store, e.span)
	eff := fresh_effect_row(store, e.span)

	elements_t := make([dynamic]TExpr, len(e.elements))
	for el, i in e.elements {
		el_result := typecheck_synth(el, env, store)
		unify(store, element_var, el_result.var_id)
		unify(store, eff, el_result.effects)
		elements_t[i] = el_result.texpr
	}

	rest_t: TExpr
	if e.rest != nil {
		rest_result := typecheck_synth(e.rest, env, store)
		unify(store, eff, rest_result.effects)
		unify(store, element_var, rest_result.var_id)
		rest_t = rest_result.texpr
	}

	var_id := fresh_value_var(store, e.span)
	// Type the list literal as the tag union `[Nil | Cons(elem, tail)]` — exactly
	// what the Cons/Nil construction it lowers to produces. This makes it an i32
	// heap value (so lower_type no longer defaults to .I64, which produced invalid
	// WASM) AND lets it unify with `Nil`/`Cons` patterns. A bare List constructor
	// gave the right wasm type but failed to unify with the patterns.
	nil_name := base.intern(store.interner, "Nil")
	cons_name := base.intern(store.interner, "Cons")
	tail_var := fresh_value_var(store, e.span)
	tag_rest := fresh_tag_row(store, e.span)
	tag_entries := store_alloc(store, Type_Tag_Entry, 2)
	tag_entries[0] = Type_Tag_Entry {
		name    = nil_name,
		payload = store_alloc(store, base.Type_Var_ID, 0),
	}
	cons_payload := store_alloc(store, base.Type_Var_ID, 2)
	cons_payload[0] = resolve_var(store, element_var)
	cons_payload[1] = tail_var
	tag_entries[1] = Type_Tag_Entry {
		name    = cons_name,
		payload = cons_payload,
	}
	link_var(
		store,
		var_id,
		Inferred_Tag_Union_Row{tag_entries = tag_entries, tag_rest = resolve_var(store, tag_rest)},
	)
	// The Cons tail is left as an open var; it re-unifies with the concrete list
	// type at use sites (matching, recursion). Tying it back to var_id directly
	// would build a cyclic type that loops the unifier.
	_ = tail_var
	t := new(TExpr_List)
	t^ = TExpr_List {
		elements = elements_t,
		rest     = rest_t,
		type_    = lower_type(store, var_id),
		eff_     = lower_effect_type(store, eff),
		span     = e.span,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_record_update :: proc(
	e: ^CExpr_Record_Update,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	rest_result := typecheck_synth(e.rest, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, rest_result.effects)

	updates_t := make([dynamic]TRecord_Field, len(e.updates))
	for u, i in e.updates {
		u_result := typecheck_synth(u.value, env, store)
		unify(store, eff, u_result.effects)
		updates_t[i] = TRecord_Field {
			name  = u.name,
			value = u_result.texpr,
			span  = u.span,
		}
	}

	t := new(TExpr_Record_Update)
	t^ = TExpr_Record_Update {
		rest    = rest_result.texpr,
		updates = updates_t,
		type_   = lower_type(store, rest_result.var_id),
		eff_    = lower_effect_type(store, eff),
		span    = e.span,
	}
	return Synth_Result{var_id = rest_result.var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_method_call :: proc(
	e: ^CExpr_Method_Call,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	inner_name := base.intern(store.interner, "inner")
	if e.method.name == inner_name && len(e.args) == 0 {
		receiver_result := typecheck_synth(e.receiver, env, store)
		receiver_resolved := store.vars[int(resolve_var(store, receiver_result.var_id))]
		if inf, is_inf := receiver_resolved.link.(Inferred_Type); is_inf {
			if nt, nt_ok := inf.(Inferred_Newtype); nt_ok {
				nt_info, nt_ok_nt := store.newtype_decls[nt.primitive_name]
				if nt_ok_nt && !is_same_module(env, nt_info.module) {
					nt_str := base.intern_get(store.interner, nt.primitive_name)
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_newtype_opaque_violation(nt_str, "unwrap", e.span),
					)
				}
				args_t := make([dynamic]TExpr, 0)
				t := new(TExpr_Method_Call)
				t^ = TExpr_Method_Call {
					receiver  = receiver_result.texpr,
					method    = e.method,
					args      = args_t,
					type_     = lower_type(store, nt.inner_id),
					eff_      = lower_effect_type(store, receiver_result.effects),
					resolved_ = e.method,
					dispatch  = e.dispatch,
					span      = e.span,
				}
				return Synth_Result {
					var_id = nt.inner_id,
					effects = receiver_result.effects,
					texpr = TExpr(t),
				}
			}
		}
	}

	receiver_result := typecheck_synth(e.receiver, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, receiver_result.effects)

	is_effect_op := false
	effect_name: base.Intern_ID = base.NO_NAME

	#partial switch r in e.receiver {
	case ^CExpr_Tag:
		if is_declared_newtype(store, r.name.name) && len(r.payload) == 0 && len(e.args) >= 1 {
			return typecheck_qualified_tag_construct(r, e, env, store)
		}
		if len(r.payload) == 0 && is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	case ^CExpr_Name:
		if is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	}

	args_t := make([dynamic]TExpr, 0, len(e.args))

	if is_effect_op {

		effect_entries := store_alloc(store, Effect_Row_Entry, 1)
		effect_entries[0] = Effect_Row_Entry {
			name      = effect_name,
			type_args = {},
		}
		rest := fresh_effect_row(store, e.span)
		row := fresh_effect_row(store, e.span)
		link_var(store, row, Inferred_Effect_Row{effects = effect_entries, rest_id = rest})
		unify(store, eff, row)

		spawn_name := base.intern(store.interner, "spawn!")
		join_name := base.intern(store.interner, "join!")
		is_scheduler :=
			effect_name == base.intern(store.interner, "Spawn!") ||
			effect_name == base.intern(store.interner, "Async!")

		if is_scheduler && e.method.name == spawn_name && len(e.args) == 1 {
			arg_result := typecheck_synth(e.args[0], env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)

			arg_resolved := store.vars[int(resolve_var(store, arg_result.var_id))]
			if inf, is_inf := arg_resolved.link.(Inferred_Type); is_inf {
				if fn_inf, fn_ok := inf.(Inferred_Function); fn_ok {
					handle_var := fresh_value_var(store, e.span)
					link_var(
						store,
						handle_var,
						Inferred_Handle{inner_id = fn_inf.return_id, effect_id = fn_inf.effect_id},
					)
					append(&env.spawned_handles, e.span)
					t := new(TExpr_Method_Call)
					t^ = TExpr_Method_Call {
						receiver  = receiver_result.texpr,
						method    = e.method,
						args      = args_t,
						type_     = lower_type(store, handle_var),
						eff_      = lower_effect_type(store, eff),
						resolved_ = e.method,
						dispatch  = e.dispatch,
						span      = e.span,
					}
					return Synth_Result{var_id = handle_var, effects = eff, texpr = TExpr(t)}
				}
			}
			inner_var := fresh_value_var(store, e.span)
			effect_var := fresh_effect_row(store, e.span)
			handle_var := fresh_value_var(store, e.span)
			link_var(
				store,
				handle_var,
				Inferred_Handle{inner_id = inner_var, effect_id = effect_var},
			)
			append(&env.spawned_handles, e.span)
			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call {
				receiver  = receiver_result.texpr,
				method    = e.method,
				args      = args_t,
				type_     = lower_type(store, handle_var),
				eff_      = lower_effect_type(store, eff),
				resolved_ = e.method,
				dispatch  = e.dispatch,
				span      = e.span,
			}
			return Synth_Result{var_id = handle_var, effects = eff, texpr = TExpr(t)}
		}

		if is_scheduler && e.method.name == join_name && len(e.args) == 1 {
			arg_result := typecheck_synth(e.args[0], env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)

			arg_resolved := store.vars[int(resolve_var(store, arg_result.var_id))]
			if inf, is_inf := arg_resolved.link.(Inferred_Type); is_inf {
				if h_inf, h_ok := inf.(Inferred_Handle); h_ok {
					if len(env.spawned_handles) > 0 {
						pop(&env.spawned_handles)
					}
					unify(store, eff, h_inf.effect_id)
					t := new(TExpr_Method_Call)
					t^ = TExpr_Method_Call {
						receiver  = receiver_result.texpr,
						method    = e.method,
						args      = args_t,
						type_     = lower_type(store, h_inf.inner_id),
						eff_      = lower_effect_type(store, eff),
						resolved_ = e.method,
						dispatch  = e.dispatch,
						span      = e.span,
					}
					return Synth_Result{var_id = h_inf.inner_id, effects = eff, texpr = TExpr(t)}
				}
			}
			return_var := fresh_value_var(store, e.span)
			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call {
				receiver  = receiver_result.texpr,
				method    = e.method,
				args      = args_t,
				type_     = lower_type(store, return_var),
				eff_      = lower_effect_type(store, eff),
				resolved_ = e.method,
				dispatch  = e.dispatch,
				span      = e.span,
			}
			return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
		}

		is_parallel := effect_name == base.intern(store.interner, "Parallel!")
		if is_parallel {
			// Effect row for Parallel! operations: Parallel! | (callback effects)
			parallel_effect_entries := store_alloc(store, Effect_Row_Entry, 1)
			parallel_effect_entries[0] = Effect_Row_Entry {
				name      = effect_name,
				type_args = {},
			}
			parallel_rest := fresh_effect_row(store, e.span)
			parallel_row := fresh_effect_row(store, e.span)
			link_var(
				store,
				parallel_row,
				Inferred_Effect_Row{effects = parallel_effect_entries, rest_id = parallel_rest},
			)
			unify(store, eff, parallel_row)

			for a in e.args {
				arg_result := typecheck_synth(a, env, store)
				unify(store, eff, arg_result.effects)
				append(&args_t, arg_result.texpr)

				// Propagate callback's effect row to caller
				arg_resolved := resolve_var(store, arg_result.var_id)
				arg_var := store.vars[int(arg_resolved)]
				if inf, is_inf := arg_var.link.(Inferred_Type); is_inf {
					if fn_inf, fn_ok := inf.(Inferred_Function); fn_ok {
						unify(store, eff, fn_inf.effect_id)
					}
				}
			}

			map_name := base.intern(store.interner, "map!")
			all_name := base.intern(store.interner, "all!")
			filter_name := base.intern(store.interner, "filter!")
			for_each_name := base.intern(store.interner, "for_each!")
			reduce_name := base.intern(store.interner, "reduce!")
			any_name := base.intern(store.interner, "any!")

			result_var: base.Type_Var_ID

			if e.method.name == for_each_name {
				unit_name := base.intern(store.interner, "Unit")
				result_var = make_primitive_type(store, unit_name, e.span)
			} else if e.method.name == any_name && len(e.args) >= 2 {
				result_var = fresh_value_var(store, e.span)
			} else if e.method.name == reduce_name && len(e.args) >= 3 {
				init_result := typecheck_synth(e.args[2], env, store)
				result_var = init_result.var_id
			} else {
				result_var = fresh_value_var(store, e.span)
			}

			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call {
				receiver  = receiver_result.texpr,
				method    = e.method,
				args      = args_t,
				type_     = lower_type(store, result_var),
				eff_      = lower_effect_type(store, eff),
				resolved_ = e.method,
				dispatch  = e.dispatch,
				span      = e.span,
			}
			return Synth_Result{var_id = result_var, effects = eff, texpr = TExpr(t)}
		}
	}

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
		append(&args_t, arg_result.texpr)

		if is_effect_op {
			arg_resolved := resolve_var(store, arg_result.var_id)
			arg_var := store.vars[int(arg_resolved)]
			if inf, is_inf := arg_var.link.(Inferred_Type); is_inf {
				if fn_inf, fn_ok := inf.(Inferred_Function); fn_ok {
					unify(store, eff, fn_inf.effect_id)
				}
			}
		}
	}

	return_var := fresh_value_var(store, e.span)
	t := new(TExpr_Method_Call)
	t^ = TExpr_Method_Call {
		receiver  = receiver_result.texpr,
		method    = e.method,
		args      = args_t,
		type_     = lower_type(store, return_var),
		eff_      = lower_effect_type(store, eff),
		resolved_ = e.method,
		dispatch  = e.dispatch,
		span      = e.span,
	}
	return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
}

typecheck_qualified_tag_construct :: proc(
	receiver: ^CExpr_Tag,
	e: ^CExpr_Method_Call,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)
	args_t := make([dynamic]TExpr, 0, len(e.args))

	nt_info, ok := store.newtype_decls[receiver.name.name]
	if !ok {
		return_var := fresh_value_var(store, e.span)
		for a in e.args {
			arg_result := typecheck_synth(a, env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)
		}
		t := new(TExpr_Method_Call)
		t^ = TExpr_Method_Call {
			receiver  = TExpr(new(TExpr_Tag)),
			method    = e.method,
			args      = args_t,
			type_     = lower_type(store, return_var),
			eff_      = lower_effect_type(store, eff),
			resolved_ = e.method,
			dispatch  = e.dispatch,
			span      = e.span,
		}
		return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
	}

	if !is_same_module(env, nt_info.module) && !nt_info.pub_variants {
		nt_str := base.intern_get(store.interner, receiver.name.name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_newtype_opaque_violation(nt_str, "construct variant", e.span),
		)
	}

	tag_owned := false
	for owned in nt_info.owned_tags {
		if owned == e.method.name {
			tag_owned = true
			break
		}
	}
	if !tag_owned {
		nt_str := base.intern_get(store.interner, receiver.name.name)
		tag_str := base.intern_get(store.interner, e.method.name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_tag_not_owned(nt_str, tag_str, e.span),
		)
		return_var := fresh_value_var(store, e.span)
		for a in e.args {
			arg_result := typecheck_synth(a, env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)
		}
		t := new(TExpr_Method_Call)
		t^ = TExpr_Method_Call {
			receiver  = TExpr(new(TExpr_Tag)),
			method    = e.method,
			args      = args_t,
			type_     = lower_type(store, return_var),
			eff_      = lower_effect_type(store, eff),
			resolved_ = e.method,
			dispatch  = e.dispatch,
			span      = e.span,
		}
		return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
	}

	nt_binding, has_binding := env_lookup(env, receiver.name.name)
	if !has_binding {
		nt_binding = store.bindings[receiver.name.name]
	}
	inst_binding := instantiate(store, nt_binding)

	nt_resolved := store.vars[int(resolve_var(store, inst_binding))]
	nt_inf, is_nt := nt_resolved.link.(Inferred_Type)

	if is_nt {
		if nt, nt_ok := nt_inf.(Inferred_Newtype); nt_ok {
			inner_resolved := store.vars[int(resolve_var(store, nt.inner_id))]
			if inner_inf, inner_ok := inner_resolved.link.(Inferred_Type); inner_ok {
				if tu_inf, tu_ok := inner_inf.(Inferred_Tag_Union_Row); tu_ok {
					for te in tu_inf.tag_entries {
						if te.name == e.method.name && len(te.payload) == len(e.args) {
							for a, i in e.args {
								arg_result := typecheck_synth(a, env, store)
								unify(store, eff, arg_result.effects)
								unify(store, arg_result.var_id, te.payload[i])
								append(&args_t, arg_result.texpr)
							}
							t := new(TExpr_Method_Call)
							t^ = TExpr_Method_Call {
								receiver  = TExpr(new(TExpr_Tag)),
								method    = e.method,
								args      = args_t,
								type_     = lower_type(store, inst_binding),
								eff_      = lower_effect_type(store, eff),
								resolved_ = e.method,
								dispatch  = e.dispatch,
								span      = e.span,
							}
							return Synth_Result {
								var_id = inst_binding,
								effects = eff,
								texpr = TExpr(t),
							}
						}
					}
				}
			}
		}
	}

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
		append(&args_t, arg_result.texpr)
	}

	t := new(TExpr_Method_Call)
	t^ = TExpr_Method_Call {
		receiver  = TExpr(new(TExpr_Tag)),
		method    = e.method,
		args      = args_t,
		type_     = lower_type(store, inst_binding),
		eff_      = lower_effect_type(store, eff),
		resolved_ = e.method,
		dispatch  = e.dispatch,
		span      = e.span,
	}
	return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
}


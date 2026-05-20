package camp

import "core:fmt"
import "core:strings"

Type_Env :: struct {
	bindings:       map[Intern_ID]Type_Var_ID,
	parent:         ^Type_Env,
	handled_effects: [dynamic]Intern_ID,
}

Type_Result :: struct {
	var_id:  Type_Var_ID,
	effects: Type_Var_ID,
}

env_lookup :: proc(env: ^Type_Env, name: Intern_ID) -> (Type_Var_ID, bool) {
	current := env
	for current != nil {
		if existing, ok := current.bindings[name]; ok {
			return existing, true
		}
		current = current.parent
	}
	return Type_Var_ID(-1), false
}

levenshtein_distance :: proc(a: string, b: string) -> int {
	if len(a) == 0 do return len(b)
	if len(b) == 0 do return len(a)

	a_len := len(a)
	b_len := len(b)
	dist: [dynamic][dynamic]int
	dist = make([dynamic][dynamic]int, a_len + 1)
	for i in 0..<a_len + 1 {
		dist[i] = make([dynamic]int, b_len + 1)
		dist[i][0] = i
	}
	for j in 0..<b_len + 1 {
		dist[0][j] = j
	}
	defer {
		for i in 0..<a_len + 1 {
			delete(dist[i])
		}
		delete(dist)
	}

	for i in 1..<a_len + 1 {
		for j in 1..<b_len + 1 {
			cost := 1
			if a[i-1] == b[j-1] do cost = 0
			dist[i][j] = min(
				dist[i-1][j] + 1,
				dist[i][j-1] + 1,
				dist[i-1][j-1] + cost,
			)
		}
	}

	return dist[a_len][b_len]
}

find_similar_names :: proc(name: string, env: ^Type_Env, interner: ^Intern_Table) -> []string {
	names: [dynamic]string
	current := env
	for current != nil {
		for k, _ in current.bindings {
			k_str := intern_get(interner, k)
			if levenshtein_distance(name, k_str) <= 2 {
				append(&names, k_str)
			}
		}
		current = current.parent
	}
	return names[:]
}

format_effect_row :: proc(store: ^Type_Store, effects: Type_Var_ID) -> string {
	rid := resolve_var(store, effects)
	rv := get_var(store, rid)
	it, is_inferred := rv.link.(Inferred_Type)
	if is_inferred && it.tag == .Effect_Row {
		if len(it.effect_names) == 0 do return "{}"
		builder: strings.Builder
		strings.builder_init_len_cap(&builder, 0, 64)
		strings.write_rune(&builder, '{')
		for i, eid in it.effect_names {
			if i > 0 do strings.write_string(&builder, ", ")
			strings.write_string(&builder, intern_get(store.interner, Intern_ID(eid)))
		}
		strings.write_rune(&builder, '}')
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	}
	return "{}"
}

typecheck_file :: proc(file: CFile, store: ^Type_Store) {
	file := file
	store.spans = file.spans
	env: Type_Env
	env.bindings = make(map[Intern_ID]Type_Var_ID, 64)
	env.parent = nil
	env.handled_effects = make([dynamic]Intern_ID, 0, 8)
	defer delete(env.bindings)
	defer delete(env.handled_effects)

	for decl in file.decls {
		typecheck_decl(decl, &env, store)
	}

	for name_id, var_id in env.bindings {
		store.bindings[name_id] = var_id
	}
}

// decl_name returns the name we tag this decl's diagnostics with. Tests,
// expects, and imports don't bind a name; they use NO_NAME (still flushed,
// just can't be a cascade root for anyone else).
decl_name :: proc(decl: CDecl) -> Intern_ID {
	switch d in decl {
	case ^CDecl_Const:  return d.name.name
	case ^CDecl_Effect: return d.name.name
	case ^CDecl_Trait:  return d.name.name
	case ^CDecl_Alias:  return d.name.name
	case ^CDecl_Test:   return NO_NAME
	case ^CDecl_Expect: return NO_NAME
	case ^CDecl_Import: return NO_NAME
	}
	return NO_NAME
}

typecheck_decl :: proc(decl: CDecl, env: ^Type_Env, store: ^Type_Store) {
	store.current_decl = decl_name(decl)
	store.current_decl_depends_on_broken = NO_NAME
	defer {
		dn := store.current_decl
		typecheck_flush_decl(store)
		// If this decl broke, swap its binding for an Error_Sentinel so any
		// downstream use of its name short-circuits in unify and tags the
		// using decl as cascade.
		if dn != NO_NAME && dn in store.broken_decls {
			sentinel := fresh_error_sentinel(store, dn, Source_Span_ZERO)
			env.bindings[dn] = sentinel
		}
		store.current_decl = NO_NAME
		store.current_decl_depends_on_broken = NO_NAME
	}

	switch d in decl {
	case ^CDecl_Const:
		enter_level(store)
		result := typecheck_synth(d.body, env, store)

		if d.type_ann != nil {
			ann_var := convert_type_to_var(d.type_ann, store)
			unify(store, result.var_id, ann_var)
		}

		if !d.is_effectful && effect_row_nonempty(store, result.effects) {
		name_str := intern_get(store.interner, d.name.name)
		effects_str := format_effect_row(store, result.effects)
		typecheck_emit(store, diag_effectful_naming(name_str, effects_str, span_of(store.spans, d)))
		}

		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		env.bindings[d.name.name] = result.var_id

	case ^CDecl_Effect:
		append(&store.declared_effects, d.name.name)
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
		var_id := make_primitive_type(store, name, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

	case ^CExpr_Float:
		name := intern(store.interner, "F64")
		var_id := make_primitive_type(store, name, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

	case ^CExpr_String:
		name := intern(store.interner, "Str")
		var_id := make_primitive_type(store, name, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

	case ^CExpr_Bool:
		name := intern(store.interner, "Bool")
		var_id := make_primitive_type(store, name, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

	case ^CExpr_Name:
		if existing, ok := env_lookup(env, e.name.name); ok {
			// Cascade detection: if the looked-up binding is an Error_Sentinel
			// (or links to one), record the broken origin on this decl so its
			// diagnostics get tagged Cascade instead of Root.
			if origin := resolved_is_error(store, existing); origin != NO_NAME {
				if store.current_decl_depends_on_broken == NO_NAME {
					store.current_decl_depends_on_broken = origin
				}
			}
			inst := instantiate(store, existing)
			return Type_Result{var_id = inst, effects = fresh_effect_row(store, span_of(store.spans, e))}
		}
		var_id := fresh_value_var(store, span_of(store.spans, e))
		name_str := intern_get(store.interner, e.name.name)
		similar := find_similar_names(name_str, env, store.interner)
		typecheck_emit(store, diag_undefined_name(name_str, similar, span_of(store.spans, e)))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

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
		#partial switch target in e.target {
		case ^CExpr_Name:
			env.bindings[target.name.name] = result.var_id
		case:
		}
		return Type_Result{var_id = result.var_id, effects = result.effects}

	case ^CExpr_Return:
		result := typecheck_synth(e.value, env, store)
		return Type_Result{var_id = result.var_id, effects = result.effects}

	case ^CExpr_Crash:
		var_id := fresh_value_var(store, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}

	case ^CExpr_Interpolate:
		str_name := intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, span_of(store.spans, e))
		eff := fresh_effect_row(store, span_of(store.spans, e))
		for part in e.parts {
			part_result := typecheck_synth(part, env, store)
			unify(store, part_result.var_id, str_var)
			unify(store, eff, part_result.effects)
		}
		return Type_Result{var_id = str_var, effects = eff}

	case ^CExpr_Method_Call:
		return typecheck_method_call(e, env, store)

	case ^CExpr_Handle:
		append(&env.handled_effects, e.effect.name)
		body_result := typecheck_synth(e.body, env, store)
		_ = pop(&env.handled_effects)
		result_eff := fresh_effect_row(store, span_of(store.spans, e))
		return Type_Result{var_id = body_result.var_id, effects = result_eff}
	}
	var_id := fresh_value_var(store, Source_Span_ZERO)
	return Type_Result{var_id = var_id, effects = fresh_effect_row(store, Source_Span_ZERO)}
}

typecheck_lambda :: proc(e: ^CExpr_Lambda, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	child_env: Type_Env
	child_env.bindings = make(map[Intern_ID]Type_Var_ID, len(e.params) + 4)
	child_env.parent = env
	child_env.handled_effects = make([dynamic]Intern_ID, 0, 8)
	defer delete(child_env.bindings)
	defer delete(child_env.handled_effects)

	param_ids := store_alloc(store, Type_Var_ID, len(e.params))

	for i in 0..<len(e.params) {
		param := e.params[i]
		param_var := fresh_value_var(store, param.span)
		if param.type_ann != nil {
			ann_var := convert_type_to_var(param.type_ann, store)
			unify(store, param_var, ann_var)
		}
		child_env.bindings[param.name] = param_var
		param_ids[i] = param_var
	}

	body_result := typecheck_synth(e.body, &child_env, store)

	effect_id := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, effect_id, body_result.effects)
	if e.effects != nil {
		ann_effects := convert_type_to_var(e.effects, store)
		unify(store, effect_id, ann_effects)
	}

	return_id := fresh_value_var(store, span_of(store.spans, e))
	if e.return_type != nil {
		ann_return := convert_type_to_var(e.return_type, store)
		unify(store, return_id, ann_return)
		unify(store, body_result.var_id, ann_return)
	} else {
		unify(store, return_id, body_result.var_id)
	}

	fn_var := fresh_value_var(store, span_of(store.spans, e))
	link_var(store, fn_var, Inferred_Type{
		tag = .Function,
		param_ids = param_ids,
		return_id = return_id,
		effect_id = effect_id,
	})

	return Type_Result{var_id = fn_var, effects = fresh_effect_row(store, span_of(store.spans, e))}
}

typecheck_call :: proc(e: ^CExpr_Call, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	callee_result := typecheck_synth(e.callee, env, store)
	eff := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, eff, callee_result.effects)

	param_ids := store_alloc(store, Type_Var_ID, len(e.args))
	for i in 0..<len(e.args) {
		arg_result := typecheck_synth(e.args[i], env, store)
		unify(store, eff, arg_result.effects)
		param_ids[i] = arg_result.var_id
	}

	return_var := fresh_value_var(store, span_of(store.spans, e))
	callee_effect := fresh_effect_row(store, span_of(store.spans, e))

	expected_fn := Inferred_Type{
		tag = .Function,
		param_ids = param_ids,
		return_id = return_var,
		effect_id = callee_effect,
	}
	expected_fn_var := fresh_value_var(store, span_of(store.spans, e))
	link_var(store, expected_fn_var, expected_fn)

	unify(store, callee_result.var_id, expected_fn_var)
	unify(store, eff, callee_effect)

	return Type_Result{var_id = return_var, effects = eff}
}

typecheck_if :: proc(e: ^CExpr_If, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	cond_result := typecheck_synth(e.condition, env, store)
	bool_name := intern(store.interner, "Bool")
	bool_var := make_primitive_type(store, bool_name, span_of(store.spans, e))
	unify(store, cond_result.var_id, bool_var)

	then_result := typecheck_synth(e.then_branch, env, store)
	else_result := typecheck_synth(e.else_branch, env, store)

	unify(store, then_result.var_id, else_result.var_id)

	effect_row := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, effect_row, cond_result.effects)
	unify(store, effect_row, then_result.effects)
	unify(store, effect_row, else_result.effects)

	return Type_Result{var_id = then_result.var_id, effects = effect_row}
}

typecheck_block :: proc(e: ^CExpr_Block, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	if len(e.statements) == 0 {
		unit_name := intern(store.interner, "Unit")
		var_id := make_primitive_type(store, unit_name, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = fresh_effect_row(store, span_of(store.spans, e))}
	}

	last_result: Type_Result
	effect_row := fresh_effect_row(store, span_of(store.spans, e))
	for stmt in e.statements {
		last_result = typecheck_synth(stmt, env, store)
		unify(store, effect_row, last_result.effects)
	}
	return Type_Result{var_id = last_result.var_id, effects = effect_row}
}

typecheck_binop :: proc(e: ^CExpr_BinOp, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	left_result := typecheck_synth(e.left, env, store)
	right_result := typecheck_synth(e.right, env, store)
	eff := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, eff, left_result.effects)
	unify(store, eff, right_result.effects)

	#partial switch e.op {
	case .Kw_And, .Kw_Or:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, span_of(store.spans, e))
		unify(store, left_result.var_id, bool_var)
		unify(store, right_result.var_id, bool_var)
		return Type_Result{var_id = bool_var, effects = eff}

	case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		unify(store, left_result.var_id, right_result.var_id)
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, span_of(store.spans, e))
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
		bool_var := make_primitive_type(store, bool_name, span_of(store.spans, e))
		unify(store, operand_result.var_id, bool_var)
		return Type_Result{var_id = bool_var, effects = operand_result.effects}
	case .Minus:
		return Type_Result{var_id = operand_result.var_id, effects = operand_result.effects}
	case:
		return Type_Result{var_id = operand_result.var_id, effects = operand_result.effects}
	}
}

typecheck_tag :: proc(e: ^CExpr_Tag, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, span_of(store.spans, e))

	payload_ids := store_alloc(store, Type_Var_ID, len(e.payload))
	for p, i in e.payload {
		p_result := typecheck_synth(p, env, store)
		unify(store, eff, p_result.effects)
		payload_ids[i] = resolve_var(store, p_result.var_id)
	}

	tag_var := fresh_value_var(store, span_of(store.spans, e))
	rest_var := fresh_value_var(store, span_of(store.spans, e))
	tag_entries := store_alloc(store, Type_Tag_Entry, 1)
	tag_entries[0] = Type_Tag_Entry{name = e.name.name, payload = payload_ids}
	inf := Inferred_Type{
		tag = .Tag_Union_Row,
		tag_entries = tag_entries,
		rest_id = resolve_var(store, rest_var),
	}
	link_var(store, tag_var, inf)
	return Type_Result{var_id = tag_var, effects = eff}
}

typecheck_record :: proc(e: ^CExpr_Record, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, span_of(store.spans, e))

	record_fields := store_alloc(store, Type_Field_Entry, len(e.fields))
	for i in 0..<len(e.fields) {
		field := e.fields[i]
		field_result := typecheck_synth(field.value, env, store)
		unify(store, eff, field_result.effects)
		record_fields[i] = Type_Field_Entry{name = field.name, var = field_result.var_id}
	}

	record_rest := fresh_record_row(store, span_of(store.spans, e))
	_, has_rest := e.rest.(^CExpr_Record)
	if has_rest {
		rest_result := typecheck_synth(e.rest, env, store)
		unify(store, eff, rest_result.effects)
		unify(store, record_rest, rest_result.var_id)
	}

	var_id := fresh_value_var(store, span_of(store.spans, e))
	link_var(store, var_id, Inferred_Type{
		tag = .Record_Row,
		record_fields = record_fields,
		record_rest = record_rest,
	})

	return Type_Result{var_id = var_id, effects = eff}
}

typecheck_field_access :: proc(e: ^CExpr_Field_Access, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	record_result := typecheck_synth(e.record, env, store)
	field_var := fresh_value_var(store, span_of(store.spans, e))
	rest_var := fresh_value_var(store, span_of(store.spans, e))
	record_fields := store_alloc(store, Type_Field_Entry, 1)
	record_fields[0] = Type_Field_Entry{name = e.field, var = resolve_var(store, field_var)}
	inf := Inferred_Type{
		tag = .Record_Row,
		record_fields = record_fields,
		record_rest = resolve_var(store, rest_var),
	}
	link_var(store, record_result.var_id, inf)
	return Type_Result{var_id = field_var, effects = record_result.effects}
}

typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, Source_Span_ZERO)

	#partial switch p in pattern {
	case ^CPattern_Identifier:
		env.bindings[p.name] = scrutinee_var
		return Type_Result{var_id = scrutinee_var, effects = eff}

	case ^CPattern_Wildcard:
		return Type_Result{var_id = scrutinee_var, effects = eff}

	case ^CPattern_Bool:
		bool_name := intern(store.interner, "Bool")
		sp := span_of(store.spans, p)
		bool_var := make_primitive_type(store, bool_name, sp)
		unify(store, scrutinee_var, bool_var)
		return Type_Result{var_id = bool_var, effects = eff}

	case ^CPattern_Int:
		i64_name := intern(store.interner, "I64")
		sp := span_of(store.spans, p)
		i64_var := make_primitive_type(store, i64_name, sp)
		unify(store, scrutinee_var, i64_var)
		return Type_Result{var_id = i64_var, effects = eff}

	case ^CPattern_String:
		str_name := intern(store.interner, "Str")
		sp := span_of(store.spans, p)
		str_var := make_primitive_type(store, str_name, sp)
		unify(store, scrutinee_var, str_var)
		return Type_Result{var_id = str_var, effects = eff}

	case ^CPattern_Tag:
		sp := span_of(store.spans, p)
		payload_ids := store_alloc(store, Type_Var_ID, len(p.payload))
		for spat, i in p.payload {
			payload_ids[i] = fresh_value_var(store, sp)
			pat_result := typecheck_pattern(spat, payload_ids[i], env, store)
			unify(store, eff, pat_result.effects)
		}
		rest_var := fresh_value_var(store, sp)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		tag_entries[0] = Type_Tag_Entry{name = p.name.name, payload = payload_ids}
		tag_var := fresh_value_var(store, sp)
		link_var(store, tag_var, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			rest_id = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, tag_var)
		return Type_Result{var_id = tag_var, effects = eff}

	case ^CPattern_Record:
		sp := span_of(store.spans, p)
		field_entries := store_alloc(store, Type_Field_Entry, len(p.fields))
		for sf, i in p.fields {
			field_entries[i].name = sf.name
			field_entries[i].var = fresh_value_var(store, sp)
			env.bindings[sf.binding] = field_entries[i].var
		}
		rest_var := fresh_record_row(store, sp)
		rec_var := fresh_value_var(store, sp)
		link_var(store, rec_var, Inferred_Type{
			tag = .Record_Row,
			record_fields = field_entries,
			record_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, rec_var)
		return Type_Result{var_id = rec_var, effects = eff}
	}

	return Type_Result{var_id = scrutinee_var, effects = eff}
}

collect_covered_tags :: proc(pattern: CPattern, tags: ^map[Intern_ID]bool, saturated: ^bool) {
	#partial switch p in pattern {
	case ^CPattern_Wildcard, ^CPattern_Identifier:
		saturated^ = true
	case ^CPattern_Tag:
		tags^[p.name.name] = true
	case:
	}
}

typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, span_of(store.spans, e))
		return Type_Result{var_id = var_id, effects = scrutinee_result.effects}
	}

	saved_bindings := make(map[Intern_ID]Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	result_var := fresh_value_var(store, span_of(store.spans, e))
	effect_row := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, effect_row, scrutinee_result.effects)

	covered_tags: map[Intern_ID]bool
	covered_tags = make(map[Intern_ID]bool, len(e.arms))
	defer delete(covered_tags)
	saturated := false

	for i := 0; i < len(e.arms); i += 1 {
		arm := e.arms[i]

		for k in env.bindings {
			delete_key(&env.bindings, k)
		}
		for k, v in saved_bindings {
			env.bindings[k] = v
		}

		pat_result := typecheck_pattern(arm.pattern, scrutinee_result.var_id, env, store)
		unify(store, effect_row, pat_result.effects)
		collect_covered_tags(arm.pattern, &covered_tags, &saturated)

		arm_result := typecheck_synth(arm.body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)
	}

	resolved_scrut := get_var(store, resolve_var(store, scrutinee_result.var_id))
	#partial switch inf in resolved_scrut.link {
	case Inferred_Type:
		if inf.tag == .Tag_Union_Row && len(inf.tag_entries) > 0 && !saturated {
			missing_list: [dynamic]string
			missing_list = make([dynamic]string, 0, len(inf.tag_entries))
			defer delete(missing_list)
			for te in inf.tag_entries {
				if !covered_tags[te.name] {
					append(&missing_list, intern_get(store.interner, te.name))
				}
			}
			if len(missing_list) > 0 {
				missing := missing_list[0]
				for j := 1; j < len(missing_list); j += 1 {
					missing = fmt.tprintf("{}, {}", missing, missing_list[j])
				}
				typecheck_emit(store, diag_internal(
					fmt.tprintf("non-exhaustive match: missing branch for {}", missing),
					span_of(store.spans, e)))
			}
		}
	case:
	}

	return Type_Result{var_id = result_var, effects = effect_row}
}

typecheck_list :: proc(e: ^CExpr_List, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	element_var := fresh_value_var(store, span_of(store.spans, e))
	eff := fresh_effect_row(store, span_of(store.spans, e))

	for el in e.elements {
		el_result := typecheck_synth(el, env, store)
		unify(store, element_var, el_result.var_id)
		unify(store, eff, el_result.effects)
	}

	var_id := fresh_value_var(store, span_of(store.spans, e))
	return Type_Result{var_id = var_id, effects = eff}
}

typecheck_record_update :: proc(e: ^CExpr_Record_Update, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	rest_result := typecheck_synth(e.rest, env, store)
	eff := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, eff, rest_result.effects)

	for u in e.updates {
		u_result := typecheck_synth(u.value, env, store)
		unify(store, eff, u_result.effects)
	}

	return Type_Result{var_id = rest_result.var_id, effects = eff}
}

typecheck_method_call :: proc(e: ^CExpr_Method_Call, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	receiver_result := typecheck_synth(e.receiver, env, store)
	eff := fresh_effect_row(store, span_of(store.spans, e))
	unify(store, eff, receiver_result.effects)

	is_effect_op := false
	effect_name: Intern_ID = NO_NAME
	#partial switch r in e.receiver {
	case ^CExpr_Name:
		if is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	case ^CExpr_Tag:
		if len(r.payload) == 0 && is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	}

	if is_effect_op {
		if !is_effect_handled(env, effect_name) {
			effect_str := intern_get(store.interner, effect_name)
			typecheck_emit(store, diag_unhandled_effect(effect_str, span_of(store.spans, e)))
		}

		effect_names := store_alloc(store, Intern_ID, 1)
		effect_names[0] = effect_name
		rest := fresh_effect_row(store, span_of(store.spans, e))
		row := fresh_effect_row(store, span_of(store.spans, e))
		link_var(store, row, Inferred_Type{
			tag = .Effect_Row,
			effect_names = effect_names,
			rest_id = rest,
		})
		unify(store, eff, row)
	}

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
	}

	return_var := fresh_value_var(store, span_of(store.spans, e))
	return Type_Result{var_id = return_var, effects = eff}
}

convert_type_to_var :: proc(t: ^CType, store: ^Type_Store) -> Type_Var_ID {
	return convert_type_to_var_val(t^, store)
}

convert_type_to_var_val :: proc(t: CType, store: ^Type_Store) -> Type_Var_ID {
	switch ty in t {
	case ^CType_Primitive:
		return make_primitive_type(store, ty.name, span_of(store.spans, ty))

	case ^CType_Variable:
		return fresh_value_var(store, span_of(store.spans, ty))

	case ^CType_Wildcard:
		return fresh_value_var(store, span_of(store.spans, ty))

	case ^CType_Function:
		ft := ty
		sp := span_of(store.spans, ft)
		param_ids := store_alloc(store, Type_Var_ID, len(ft.params))
		for i in 0..<len(ft.params) {
			param_ids[i] = convert_type_to_var_val(ft.params[i], store)
		}
		return_id := convert_type_to_var_val(ft.return_, store)
		effect_id := fresh_effect_row(store, sp)
		if ft.effects != nil {
			effect_id = convert_type_to_var(ft.effects, store)
		}
		vid := fresh_value_var(store, sp)
		link_var(store, vid, Inferred_Type{
			tag = .Function,
			param_ids = param_ids,
			return_id = return_id,
			effect_id = effect_id,
		})
		return vid

	case ^CType_Applied:
		sp := span_of(store.spans, ty)
		arg_ids := store_alloc(store, Type_Var_ID, len(ty.args))
		for &a, i in ty.args {
			arg_ids[i] = convert_type_to_var_val(a, store)
		}
		vid := fresh_value_var(store, sp)
		link_var(store, vid, Inferred_Type{
			tag = .Constructor,
			primitive_name = ty.name,
			arity = len(ty.args),
		})
		return vid

	case ^CType_Record:
		rt := ty
		sp := span_of(store.spans, rt)
		record_fields := store_alloc(store, Type_Field_Entry, len(rt.fields))
		for i in 0..<len(rt.fields) {
			record_fields[i] = Type_Field_Entry{
				name = rt.fields[i].name,
				var  = convert_type_to_var_val(rt.fields[i].type, store),
			}
		}
		record_rest := fresh_record_row(store, sp)
		vid := fresh_value_var(store, sp)
		link_var(store, vid, Inferred_Type{
			tag = .Record_Row,
			record_fields = record_fields,
			record_rest = record_rest,
		})
		return vid

	case ^CType_Tag_Union:
		tt := ty
		sp := span_of(store.spans, tt)
		tag_entries := store_alloc(store, Type_Tag_Entry, len(tt.tags))
		for i in 0..<len(tt.tags) {
			tg := tt.tags[i]
			payload := store_alloc(store, Type_Var_ID, len(tg.payload))
			for j in 0..<len(tg.payload) {
				payload[j] = convert_type_to_var_val(tg.payload[j], store)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = tg.name,
				payload = payload,
			}
		}
		tag_rest := fresh_tag_row(store, sp)
		vid := fresh_value_var(store, sp)
		link_var(store, vid, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = tag_rest,
		})
		return vid

	case ^CType_Effect_Row:
		ert := ty
		sp := span_of(store.spans, ert)
		if len(ert.effects) == 0 {
			return fresh_effect_row(store, sp)
		}
		effect_names := store_alloc(store, Intern_ID, len(ert.effects))
		for i in 0..<len(ert.effects) {
			effect_names[i] = ert.effects[i]
		}
		rest_id := fresh_effect_row(store, sp)
		vid := fresh_effect_row(store, sp)
		link_var(store, vid, Inferred_Type{
			tag = .Effect_Row,
			effect_names = effect_names,
			rest_id = rest_id,
		})
		return vid
	}
	return fresh_value_var(store, Source_Span_ZERO)
}

instantiate :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> Type_Var_ID {
	subst := make(map[Type_Var_ID]Type_Var_ID, 8)
	defer delete(subst)
	return instantiate_rec(store, var_id, &subst)
}

instantiate_rec :: proc(store: ^Type_Store, var_id: Type_Var_ID, subst: ^map[Type_Var_ID]Type_Var_ID) -> Type_Var_ID {
	resolved := resolve_var(store, var_id)
	v := get_var(store, resolved)

	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked && is_generic(store, resolved) {
		if existing, ok := subst[resolved]; ok {
			return existing
		}
		new_id := fresh_var(store, v.kind, v.name, v.span)
		subst[resolved] = new_id
		return new_id
	}

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return resolved
	}

	switch inf.tag {
	case .Primitive, .Constructor:
		return resolved

	case .Function:
		param_ids := store_alloc(store, Type_Var_ID, len(inf.param_ids))
		for i in 0..<len(inf.param_ids) {
			param_ids[i] = instantiate_rec(store, inf.param_ids[i], subst)
		}
		return_id := instantiate_rec(store, inf.return_id, subst)
		effect_id := instantiate_rec(store, inf.effect_id, subst)
		vid := fresh_value_var(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Function,
			param_ids = param_ids,
			return_id = return_id,
			effect_id = effect_id,
		})
		return vid

	case .Effect_Row:
		effect_names := store_alloc(store, Intern_ID, len(inf.effect_names))
		for i in 0..<len(inf.effect_names) {
			effect_names[i] = inf.effect_names[i]
		}
		rest_id := instantiate_rec(store, inf.rest_id, subst)
		vid := fresh_effect_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Effect_Row,
			effect_names = effect_names,
			rest_id = rest_id,
		})
		return vid

	case .Record_Row:
		record_fields := store_alloc(store, Type_Field_Entry, len(inf.record_fields))
		for i in 0..<len(inf.record_fields) {
			f := inf.record_fields[i]
			record_fields[i] = Type_Field_Entry{
				name = f.name,
				var  = instantiate_rec(store, f.var, subst),
			}
		}
		record_rest := instantiate_rec(store, inf.record_rest, subst)
		vid := fresh_record_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Record_Row,
			record_fields = record_fields,
			record_rest = record_rest,
		})
		return vid

	case .Tag_Union_Row:
		tag_entries := store_alloc(store, Type_Tag_Entry, len(inf.tag_entries))
		for i in 0..<len(inf.tag_entries) {
			te := inf.tag_entries[i]
			payload := store_alloc(store, Type_Var_ID, len(te.payload))
			for j in 0..<len(te.payload) {
				payload[j] = instantiate_rec(store, te.payload[j], subst)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := instantiate_rec(store, inf.tag_rest, subst)
		vid := fresh_tag_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = tag_rest,
		})
		return vid
	}

	return resolved
}

effect_row_nonempty :: proc(store: ^Type_Store, effect_var: Type_Var_ID) -> bool {
	resolved := resolve_var(store, effect_var)
	v := get_var(store, resolved)

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf || inf.tag != .Effect_Row {
		return false
	}

	if len(inf.effect_names) > 0 {
		return true
	}

	rest_resolved := resolve_var(store, inf.rest_id)
	rest_v := get_var(store, rest_resolved)
	_, rest_unlinked := rest_v.link.(Type_Unlinked)
	if rest_unlinked && !is_generic(store, rest_resolved) {
		return true
	}

	rest_inf, rest_is_inf := rest_v.link.(Inferred_Type)
	if rest_is_inf && rest_inf.tag == .Effect_Row {
		return effect_row_nonempty(store, inf.rest_id)
	}

	return false
}

is_effect_handled :: proc(env: ^Type_Env, effect_id: Intern_ID) -> bool {
	current := env
	for current != nil {
		for e in current.handled_effects {
			if e == effect_id {
				return true
			}
		}
		current = current.parent
	}
	return false
}

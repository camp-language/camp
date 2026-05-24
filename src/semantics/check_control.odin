package semantics

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:frontend"
import "camp:diagnostics"

typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: base.Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Pat_Result {
	eff := fresh_effect_row(store, base.Source_Span_ZERO)

	#partial switch p in pattern {
	case ^CPattern_Identifier:
		check_shadow(env, p.name, store, p.span)
		env.bindings[p.name] = scrutinee_var
		tp := new(TPattern_Identifier)
		tp^ = TPattern_Identifier{name = p.name, span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Wildcard:
		tp := new(TPattern_Wildcard)
		tp^ = TPattern_Wildcard{span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Bool:
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, p.span)
		unify(store, scrutinee_var, bool_var)
		tp := new(TPattern_Bool)
		tp^ = TPattern_Bool{value = p.value, span = p.span}
		return Pat_Result{var_id = bool_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Int:
		i64_name := base.intern(store.interner, "I64")
		i64_var := make_primitive_type(store, i64_name, p.span)
		unify(store, scrutinee_var, i64_var)
		tp := new(TPattern_Int)
		tp^ = TPattern_Int{value = p.value, span = p.span}
		return Pat_Result{var_id = i64_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_String:
		str_name := base.intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, p.span)
		unify(store, scrutinee_var, str_var)
		tp := new(TPattern_String)
		tp^ = TPattern_String{value = p.value, span = p.span}
		return Pat_Result{var_id = str_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Tag:
		nt_name, owned := newtype_owning_tag(store, p.name.name)
		if owned && !is_same_module(env, store.newtype_decls[nt_name].module) {
			nt_info := store.newtype_decls[nt_name]
			if !nt_info.pub_variants {
				nt_str := base.intern_get(store.interner, nt_name)
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_newtype_opaque_violation(nt_str, "destructure variant", p.span))
			}
		}

		payload_ids := store_alloc(store, base.Type_Var_ID, len(p.payload))
		payload_t := make([dynamic]TPattern, len(p.payload))
		for sp, i in p.payload {
			payload_ids[i] = fresh_value_var(store, p.span)
			pat_result := typecheck_pattern(sp, payload_ids[i], env, store)
			unify(store, eff, pat_result.effects)
			payload_t[i] = pat_result.tpat
		}
		rest_var := fresh_tag_row(store, p.span)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		tag_entries[0] = Type_Tag_Entry{name = p.name.name, payload = payload_ids}
		tag_var := fresh_value_var(store, p.span)
		link_var(store, tag_var, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, tag_var)
		tp := new(TPattern_Tag)
		tp^ = TPattern_Tag{name = p.name, payload = payload_t, span = p.span}
		return Pat_Result{var_id = tag_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Record:
		field_entries := store_alloc(store, Type_Field_Entry, len(p.fields))
		fields_t := make([dynamic]TPattern_Field, len(p.fields))
		for sf, i in p.fields {
			field_entries[i].name = sf.name
			field_entries[i].var = fresh_value_var(store, p.span)
			env.bindings[sf.binding] = field_entries[i].var
			fields_t[i] = TPattern_Field{name = sf.name, binding = sf.binding, span = sf.span}
		}
		rest_var := fresh_record_row(store, p.span)
		rec_var := fresh_value_var(store, p.span)
		link_var(store, rec_var, Inferred_Type{
			tag = .Record_Row,
			record_fields = field_entries,
			record_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, rec_var)
		tp := new(TPattern_Record)
		tp^ = TPattern_Record{fields = fields_t, is_open = p.is_open, span = p.span}
		return Pat_Result{var_id = rec_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Or:
		alternatives := make([dynamic]TPattern, 0, len(p.alternatives))
		for alt in p.alternatives {
			pat_result := typecheck_pattern(alt, scrutinee_var, env, store)
			append(&alternatives, pat_result.tpat)
		}
		tp := new(TPattern_Or)
		tp^ = TPattern_Or{alternatives = alternatives, span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Destructure:
		if is_declared_newtype(store, p.type_name.name) {
			nt_info, nt_ok := store.newtype_decls[p.type_name.name]
			if nt_ok && !is_same_module(env, nt_info.module) {
				nt_str := base.intern_get(store.interner, p.type_name.name)
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_newtype_opaque_violation(nt_str, "destructure", p.span))
			}
		}
		inner_var := fresh_value_var(store, p.span)
		pat_result := typecheck_pattern(p.inner, inner_var, env, store)
		unify(store, eff, pat_result.effects)

		nt_binding, has_binding := env_lookup(env, p.type_name.name)
		if !has_binding {
			nt_binding = store.bindings[p.type_name.name]
		}
		inst_binding := instantiate(store, nt_binding)
		unify(store, scrutinee_var, inst_binding)
		unify(store, inner_var, store.newtype_decls[p.type_name.name].inner_type)

		tp := new(TPattern_Destructure)
		tp^ = TPattern_Destructure{type_name = p.type_name, inner = pat_result.tpat, span = p.span}
		return Pat_Result{var_id = inst_binding, effects = eff, tpat = TPattern(tp)}
	}

	tp := new(TPattern_Wildcard)
	tp^ = TPattern_Wildcard{span = base.Source_Span_ZERO}
	return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}
}

Match_Coverage :: struct {
	tags:          map[base.Intern_ID]bool,
	bool_values:   map[bool]bool,
	int_values:    map[i64]bool,
	string_values: map[string]bool,
	saturated:     bool,
}

match_coverage_init :: proc(cov: ^Match_Coverage, capacity: int) {
	cov.tags = make(map[base.Intern_ID]bool, capacity)
	cov.bool_values = make(map[bool]bool, 2)
	cov.int_values = make(map[i64]bool, capacity)
	cov.string_values = make(map[string]bool, capacity)
	cov.saturated = false
}

match_coverage_destroy :: proc(cov: ^Match_Coverage) {
	delete(cov.tags)
	delete(cov.bool_values)
	delete(cov.int_values)
	delete(cov.string_values)
}

collect_pattern_coverage :: proc(pattern: CPattern, cov: ^Match_Coverage) {
	#partial switch p in pattern {
	case ^CPattern_Wildcard, ^CPattern_Identifier:
		cov.saturated = true
	case ^CPattern_Tag:
		cov.tags[p.name.name] = true
	case ^CPattern_Bool:
		cov.bool_values[p.value] = true
	case ^CPattern_Int:
		cov.int_values[p.value] = true
	case ^CPattern_String:
		cov.string_values[p.value] = true
	case ^CPattern_Or:
		for alt in p.alternatives {
			collect_pattern_coverage(alt, cov)
		}
	case ^CPattern_Record, ^CPattern_List, ^CPattern_Destructure:
	}
}

typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, e.span)
		eff := scrutinee_result.effects
		arms_t := make([dynamic]TMatch_Arm, 0)
		t := new(TExpr_Match)
		t^ = TExpr_Match{
			scrutinee = scrutinee_result.texpr,
			arms = arms_t,
			type_ = lower_type(store, var_id),
			eff_ = lower_effect_type(store, eff),
			span = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	saved_bindings := make(map[base.Intern_ID]base.Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	result_var := fresh_value_var(store, e.span)
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)

	cov: Match_Coverage
	match_coverage_init(&cov, len(e.arms))
	defer match_coverage_destroy(&cov)

	// Track per-arm coverage for redundancy detection
	arm_coverages := make([dynamic]Match_Coverage, len(e.arms))
	for i in 0..<len(e.arms) {
		match_coverage_init(&arm_coverages[i], 1)
	}
	defer for i in 0..<len(arm_coverages) {
		match_coverage_destroy(&arm_coverages[i])
	}
	defer delete(arm_coverages)

	arms_t := make([dynamic]TMatch_Arm, len(e.arms))

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

		// Check redundancy: is this pattern already covered by earlier arms?
		is_redundant := false
		if cov.saturated {
			is_redundant = true
		} else {
			#partial switch p in arm.pattern {
			case ^CPattern_Bool:
				if cov.bool_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_Int:
				if cov.int_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_String:
				if cov.string_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_Tag:
				if cov.tags[p.name.name] {
					is_redundant = true
				}
			case ^CPattern_Record, ^CPattern_List, ^CPattern_Identifier, ^CPattern_Wildcard, ^CPattern_Destructure, ^CPattern_Or:
			}
		}
		if is_redundant {
			diagnostics.collector_add_diag(store.collector, diagnostics.diag_redundant_pattern(arm.span))
		}

		collect_pattern_coverage(arm.pattern, &cov)
		collect_pattern_coverage(arm.pattern, &arm_coverages[i])

		arm_result := typecheck_synth(arm.body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)

		arms_t[i] = TMatch_Arm{pattern = pat_result.tpat, body = arm_result.texpr, span = arm.span}
	}

	// Exhaustiveness checking
	resolved_scrut := store.vars[int(resolve_var(store, scrutinee_result.var_id))]
	#partial switch inf in resolved_scrut.link {
	case Inferred_Type:
		if inf.tag == .Tag_Union_Row && len(inf.tag_entries) > 0 && !cov.saturated {
			missing_list: [dynamic]string
			missing_list = make([dynamic]string, 0, len(inf.tag_entries))
			defer delete(missing_list)
			for te in inf.tag_entries {
				if !cov.tags[te.name] {
					append(&missing_list, base.intern_get(store.interner, te.name))
				}
			}
			if len(missing_list) > 0 {
				missing := missing_list[0]
				for j := 1; j < len(missing_list); j += 1 {
					missing = fmt.tprintf("{}, {}", missing, missing_list[j])
				}
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_internal(
					fmt.tprintf("non-exhaustive match: missing branch for {}", missing),
					e.span))
			}
		}
		// Bool exhaustiveness: must cover both true and false
		if inf.tag == .Primitive && inf.primitive_name == base.intern(store.interner, "Bool") && !cov.saturated {
			if !cov.bool_values[true] || !cov.bool_values[false] {
				missing: string
				if !cov.bool_values[true] && !cov.bool_values[false] {
					missing = "True and False"
				} else if !cov.bool_values[true] {
					missing = "True"
				} else {
					missing = "False"
				}
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_non_exhaustive_bool(missing, e.span))
			}
		}
		// Int/String exhaustiveness: can never be exhaustive without wildcard
		if inf.tag == .Primitive && !cov.saturated {
			prim_name := base.intern_get(store.interner, inf.primitive_name)
			if prim_name == "I64" || prim_name == "I32" || prim_name == "I16" || prim_name == "I8" ||
			   prim_name == "U64" || prim_name == "U32" || prim_name == "U16" || prim_name == "U8" {
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_non_exhaustive_int_string(prim_name, e.span))
			}
			if prim_name == "Str" {
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_non_exhaustive_int_string(prim_name, e.span))
			}
		}
	case Type_Unlinked, base.Type_Var_ID:
	}

	t := new(TExpr_Match)
	t^ = TExpr_Match{
		scrutinee = scrutinee_result.texpr,
		arms = arms_t,
		type_ = lower_type(store, result_var),
		eff_ = lower_effect_type(store, effect_row),
		span = e.span,
	}
	return Synth_Result{var_id = result_var, effects = effect_row, texpr = TExpr(t)}
}

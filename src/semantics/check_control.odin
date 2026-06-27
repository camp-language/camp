package semantics

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:diagnostics"
import "camp:frontend"

typecheck_pattern :: proc(
	pattern: CPattern,
	scrutinee_var: base.Type_Var_ID,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Pat_Result {
	eff := fresh_effect_row(store, base.Source_Span_ZERO)

	#partial switch p in pattern {
	case ^CPattern_Identifier:
		check_shadow(env, p.name, store, p.span)
		env.bindings[p.name] = scrutinee_var
		tp := new(TPattern_Identifier)
		tp^ = TPattern_Identifier {
			name = p.name,
			span = p.span,
		}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Wildcard:
		tp := new(TPattern_Wildcard)
		tp^ = TPattern_Wildcard {
			span = p.span,
		}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Bool:
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, p.span)
		unify(store, scrutinee_var, bool_var)
		tp := new(TPattern_Bool)
		tp^ = TPattern_Bool {
			value = p.value,
			span  = p.span,
		}
		return Pat_Result{var_id = bool_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Int:
		i64_name := base.intern(store.interner, "I64")
		i64_var := make_primitive_type(store, i64_name, p.span)
		unify(store, scrutinee_var, i64_var)
		tp := new(TPattern_Int)
		tp^ = TPattern_Int {
			value = p.value,
			span  = p.span,
		}
		return Pat_Result{var_id = i64_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_String:
		str_name := base.intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, p.span)
		unify(store, scrutinee_var, str_var)
		tp := new(TPattern_String)
		tp^ = TPattern_String {
			value = p.value,
			span  = p.span,
		}
		return Pat_Result{var_id = str_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Char:
		char_name := base.intern(store.interner, "Char")
		char_var := make_primitive_type(store, char_name, p.span)
		unify(store, scrutinee_var, char_var)
		tp := new(TPattern_Char)
		tp^ = TPattern_Char {
			value = p.value,
			span  = p.span,
		}
		return Pat_Result{var_id = char_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Tag:
		nt_name, owned := newtype_owning_tag(store, p.name.name)
		if owned && !is_same_module(env, store.newtype_decls[nt_name].module) {
			nt_info := store.newtype_decls[nt_name]
			if !nt_info.pub_variants {
				nt_str := base.intern_get(store.interner, nt_name)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_newtype_opaque_violation(
						nt_str,
						"destructure variant",
						p.span,
					),
				)
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
		tag_entries[0] = Type_Tag_Entry {
			name    = p.name.name,
			payload = payload_ids,
		}
		tag_var := fresh_value_var(store, p.span)
		link_var(
			store,
			tag_var,
			Inferred_Tag_Union_Row {
				tag_entries = tag_entries,
				tag_rest    = resolve_var(store, rest_var),
				// Match tag patterns are open rows — they unify with the
				// scrutinee's (possibly closed) row but are not themselves
				// closed declarations.
				closed      = false,
			},
		)
		unify(store, scrutinee_var, tag_var)
		tp := new(TPattern_Tag)
		tp^ = TPattern_Tag {
			name    = p.name,
			payload = payload_t,
			span    = p.span,
		}
		return Pat_Result{var_id = tag_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Record:
		field_entries := store_alloc(store, Type_Field_Entry, len(p.fields))
		fields_t := make([dynamic]TPattern_Field, len(p.fields))
		for sf, i in p.fields {
			field_entries[i].name = sf.name
			field_entries[i].var = fresh_value_var(store, p.span)
			env.bindings[sf.binding] = field_entries[i].var
			fields_t[i] = TPattern_Field {
				name    = sf.name,
				binding = sf.binding,
				span    = sf.span,
			}
		}
		rest_var := fresh_record_row(store, p.span)
		if p.rest != 0 {
			env.bindings[p.rest] = rest_var
		}
		rec_var := fresh_value_var(store, p.span)
		link_var(
			store,
			rec_var,
			Inferred_Record_Row {
				record_fields = field_entries,
				record_rest = resolve_var(store, rest_var),
				closed = false,
			},
		)
		unify(store, scrutinee_var, rec_var)

		// C0506 / C0507: validate the record pattern's field names against
		// the scrutinee's resolved record type. After unification the
		// scrutinee's row carries the actual declared fields. A pattern
		// field absent from the record is C0507 (unknown field); a declared
		// field absent from a non-open pattern is C0506 (missing field). Open
		// patterns (`{ .. }` / `{ ..rest }`) explicitly ignore the rest, so
		// they never report missing fields.
		check_record_pattern_fields(p, scrutinee_var, store)

		tp := new(TPattern_Record)
		tp^ = TPattern_Record {
			fields  = fields_t,
			is_open = p.is_open,
			span    = p.span,
			rest    = p.rest,
		}
		return Pat_Result{var_id = rec_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Tuple:
		element_types := store_alloc(store, base.Type_Var_ID, len(p.elements))
		elements_t := make([dynamic]TPattern, len(p.elements))
		for sp, i in p.elements {
			element_types[i] = fresh_value_var(store, p.span)
			pat_result := typecheck_pattern(sp, element_types[i], env, store)
			unify(store, eff, pat_result.effects)
			elements_t[i] = pat_result.tpat
		}
		tuple_var := fresh_value_var(store, p.span)
		link_var(
			store,
			tuple_var,
			Inferred_Tuple {
				element_types = element_types,
				element_count = len(p.elements),
				closed = true,
			},
		)
		unify(store, scrutinee_var, tuple_var)
		tp := new(TPattern_Tuple)
		tp^ = TPattern_Tuple {
			elements = elements_t,
			span     = p.span,
		}
		return Pat_Result{var_id = tuple_var, effects = eff, tpat = TPattern(tp)}
	case ^CPattern_As:
		check_shadow(env, p.name, store, p.span)
		env.bindings[p.name] = scrutinee_var
		inner_result := typecheck_pattern(p.inner, scrutinee_var, env, store)
		tp := new(TPattern_As)
		tp^ = TPattern_As {
			name  = p.name,
			inner = inner_result.tpat,
			span  = p.span,
		}
		return Pat_Result {
			var_id = inner_result.var_id,
			effects = inner_result.effects,
			tpat = TPattern(tp),
		}

	case ^CPattern_Or:
		alternatives := make([dynamic]TPattern, 0, len(p.alternatives))
		for alt in p.alternatives {
			pat_result := typecheck_pattern(alt, scrutinee_var, env, store)
			append(&alternatives, pat_result.tpat)
		}
		tp := new(TPattern_Or)
		tp^ = TPattern_Or {
			alternatives = alternatives,
			span         = p.span,
		}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Destructure:
		if is_declared_newtype(store, p.type_name.name) {
			nt_info, nt_ok := store.newtype_decls[p.type_name.name]
			if nt_ok && !is_same_module(env, nt_info.module) {
				nt_str := base.intern_get(store.interner, p.type_name.name)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_newtype_opaque_violation(nt_str, "destructure", p.span),
				)
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
		tp^ = TPattern_Destructure {
			type_name = p.type_name,
			inner     = pat_result.tpat,
			span      = p.span,
		}
		return Pat_Result{var_id = inst_binding, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_List:
		elements_t := make([dynamic]TPattern, len(p.elements))
		for el, i in p.elements {
			el_var := fresh_value_var(store, p.span)
			el_pat := typecheck_pattern(el, el_var, env, store)
			unify(store, eff, el_pat.effects)
			elements_t[i] = el_pat.tpat
		}

		rest_t: TPattern
		if p.rest != nil {
			tail_var := fresh_value_var(store, p.span)
			rest_result := typecheck_pattern(p.rest, tail_var, env, store)
			unify(store, eff, rest_result.effects)
			rest_t = rest_result.tpat
		}

		tp := new(TPattern_List)
		tp^ = TPattern_List {
			elements = elements_t,
			rest     = rest_t,
			span     = p.span,
		}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}
	}
	diagnostics.collector_add_diag(
		store.collector,
		diagnostics.diag_internal(
			"unhandled CPattern variant in typecheck_pattern",
			base.Source_Span_ZERO,
		),
	)

	tp := new(TPattern_Wildcard)
	tp^ = TPattern_Wildcard {
		span = base.Source_Span_ZERO,
	}
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
	case ^CPattern_As:
		collect_pattern_coverage(p.inner, cov)
	case ^CPattern_Or:
		for alt in p.alternatives {
			collect_pattern_coverage(alt, cov)
		}
	case ^CPattern_Record:
		if !p.is_open {
			cov.saturated = true
		}
	case ^CPattern_List:
		for el in p.elements {
			collect_pattern_coverage(el, cov)
		}
	case ^CPattern_Destructure:
		collect_pattern_coverage(p.inner, cov)
	case ^CPattern_Tuple:
		cov.saturated = true
		for el in p.elements {
			collect_pattern_coverage(el, cov)
		}
	}
}

// check_duplicate_bindings walks `pattern` and emits C0508 for any variable
// name that appears more than once within a single (non-or) binding
// context.
check_duplicate_bindings :: proc(pattern: CPattern, store: ^Type_Store) {
	seen: map[base.Intern_ID]base.Source_Span
	defer delete(seen)
	check_duplicate_bindings_rec(pattern, store, &seen)
}

check_duplicate_bindings_rec :: proc(
	pattern: CPattern,
	store: ^Type_Store,
	seen: ^map[base.Intern_ID]base.Source_Span,
) {
	#partial switch p in pattern {
	case ^CPattern_Identifier:
		emit_dup_if_repeated(p.name, p.span, store, seen)
	case ^CPattern_Wildcard:
	case ^CPattern_Bool, ^CPattern_Int, ^CPattern_String, ^CPattern_Char:
	case ^CPattern_Tag:
		for sp in p.payload do check_duplicate_bindings_rec(sp, store, seen)
	case ^CPattern_Record:
		for sf in p.fields do emit_dup_if_repeated(sf.binding, sf.span, store, seen)
		if p.rest != 0 do emit_dup_if_repeated(p.rest, p.span, store, seen)
	case ^CPattern_Tuple:
		for el in p.elements do check_duplicate_bindings_rec(el, store, seen)
	case ^CPattern_List:
		for el in p.elements do check_duplicate_bindings_rec(el, store, seen)
		if p.rest != nil do check_duplicate_bindings_rec(p.rest, store, seen)
	case ^CPattern_As:
		emit_dup_if_repeated(p.name, p.span, store, seen)
		check_duplicate_bindings_rec(p.inner, store, seen)
	case ^CPattern_Or:
		// Each or-branch is mutually exclusive; reset `seen` per branch so a
		// name reused across branches is allowed (they never bind together).
		for alt in p.alternatives {
			branch_seen: map[base.Intern_ID]base.Source_Span
			check_duplicate_bindings_rec(alt, store, &branch_seen)
			delete(branch_seen)
		}
	case ^CPattern_Destructure:
		check_duplicate_bindings_rec(p.inner, store, seen)
	}
}

emit_dup_if_repeated :: proc(
	name: base.Intern_ID,
	span: base.Source_Span,
	store: ^Type_Store,
	seen: ^map[base.Intern_ID]base.Source_Span,
) {
	if _, ok := seen[name]; ok {
		name_str := base.intern_get(store.interner, name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_duplicate_binding_pattern(name_str, span),
		)
	} else {
		seen[name] = span
	}
}

// pattern_span returns the source span of `pattern`'s syntactic node, or
// `fallback` when the pattern carries no span (should not happen for
// well-formed AST). Used so diagnostics point at the pattern token, not the
// enclosing arm.
pattern_span :: proc(pattern: CPattern, fallback: base.Source_Span) -> base.Source_Span {
	#partial switch p in pattern {
	case ^CPattern_Identifier:
		return p.span
	case ^CPattern_Wildcard:
		return p.span
	case ^CPattern_Bool:
		return p.span
	case ^CPattern_Int:
		return p.span
	case ^CPattern_String:
		return p.span
	case ^CPattern_Char:
		return p.span
	case ^CPattern_Tag:
		return p.span
	case ^CPattern_Record:
		return p.span
	case ^CPattern_Tuple:
		return p.span
	case ^CPattern_As:
		return p.span
	case ^CPattern_Or:
		return p.span
	case ^CPattern_Destructure:
		return p.span
	case ^CPattern_List:
		return p.span
	case:
		return fallback
	}
}

// check_record_pattern_fields validates a record pattern's field names
// against the scrutinee's resolved record row (C0506 missing field, C0507
// unknown field). Called after `scrutinee_var` unifies with the pattern's
// fresh record row, so resolving `scrutinee_var` yields the actual declared
// field set. `similar_fields` for the "Did you mean?" hint uses a substring
// match against the declared names.
check_record_pattern_fields :: proc(
	p: ^CPattern_Record,
	scrutinee_var: base.Type_Var_ID,
	store: ^Type_Store,
) {
	resolved := resolve_var(store, scrutinee_var)
	link := store.vars[int(resolved)].link
	inf, is_inf := link.(Inferred_Type)
	if !is_inf do return
	row, is_row := inf.(Inferred_Record_Row)
	if !is_row do return
	if len(row.record_fields) == 0 do return

	declared: map[base.Intern_ID]bool
	defer delete(declared)
	for f in row.record_fields do declared[f.name] = true

	// C0507: pattern field not on the record type.
	unknown_reported := false
	for sf in p.fields {
		if !declared[sf.name] {
			similar := find_similar_fields(sf.name, row.record_fields, store)
			type_name := record_row_type_name(store, row.record_fields)
			field_str := base.intern_get(store.interner, sf.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_unknown_field_pattern(field_str, type_name, similar, sf.span),
			)
			unknown_reported = true
		}
	}

	// C0506: declared field absent from a non-open pattern. Open patterns
	// (`{ .. }` / `{ ..rest }`) explicitly ignore remaining fields. Skip when
	// a C0507 already fired for this pattern —— the unknown field is the
	// primary error, and reporting missing fields against a pattern that
	// names a non-existent field just doubles the noise.
	if unknown_reported do return
	if p.is_open do return
	if p.rest != 0 do return
	pattern_fields: map[base.Intern_ID]bool
	defer delete(pattern_fields)
	for sf in p.fields do pattern_fields[sf.name] = true
	for f in row.record_fields {
		if !pattern_fields[f.name] {
			field_str := base.intern_get(store.interner, f.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_missing_field_pattern(field_str, p.span),
			)
		}
	}
}

// find_similar_fields returns up to one name from `declared` that resembles
// `target` (one contains the other), for the C0507 "Did you mean `{}`?"
// hint. Empty when no plausible match exists.
find_similar_fields :: proc(
	target: base.Intern_ID,
	declared: []Type_Field_Entry,
	store: ^Type_Store,
) -> []string {
	target_str := base.intern_get(store.interner, target)
	for f in declared {
		cand := base.intern_get(store.interner, f.name)
		if strings.contains(target_str, cand) || strings.contains(cand, target_str) {
			out := make([]string, 1)
			out[0] = cand
			return out
		}
	}
	out := make([]string, 0)
	return out
}

// record_row_type_name renders a readable name for an anonymous record row
// by joining its field names (`{ x, y }`). Newtype-owned records would use
// the newtype name; anonymous records are the common case here.
record_row_type_name :: proc(store: ^Type_Store, fields: []Type_Field_Entry) -> string {
	if len(fields) == 0 do return "record"
	parts: [dynamic]string
	defer delete(parts)
	for f in fields do append(&parts, base.intern_get(store.interner, f.name))
	return fmt.tprintf("{{ {} }}", strings.join(parts[:], ", "))
}

typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)
	// Snapshot the scrutinee's full variant set BEFORE pattern typechecking.
	// Pattern unification (open rows) decomposes the scrutinee's row chain
	// into single-entry open rows, losing variants that lived in the
	// annotation's closed row. Capturing the variant set now (by walking the
	// rest chain) lets exhaustiveness checking (C0502/C0504) see every
	// declared variant even after pattern rows overwrite the chain.
	scrut_pre_variants := snapshot_tag_union_variants(store, scrutinee_result.var_id)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, e.span)
		eff := scrutinee_result.effects
		arms_t := make([dynamic]TMatch_Arm, 0)
		t := new(TExpr_Match)
		t^ = TExpr_Match {
			scrutinee = scrutinee_result.texpr,
			arms      = arms_t,
			type_     = lower_type(store, var_id),
			eff_      = lower_effect_type(store, eff),
			span      = e.span,
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
	for i in 0 ..< len(e.arms) {
		match_coverage_init(&arm_coverages[i], 1)
	}
	defer for i in 0 ..< len(arm_coverages) {
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

		// C0508: duplicate binding within a single pattern.
		check_duplicate_bindings(arm.pattern, store)

		// Typecheck guard if present (must be Bool)
		guard_t: TExpr = nil
		if arm.guard != nil {
			guard_result := typecheck_synth(arm.guard, env, store)
			bool_id := base.intern(store.interner, "Bool")
			bool_var := make_primitive_type(store, bool_id, arm.span)
			unify(store, guard_result.var_id, bool_var)
			unify(store, effect_row, guard_result.effects)
			guard_t = guard_result.texpr
		}

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
			case ^CPattern_Record,
			     ^CPattern_List,
			     ^CPattern_Identifier,
			     ^CPattern_Wildcard,
			     ^CPattern_Destructure,
			     ^CPattern_Or:
			}
		}
		if is_redundant {
			// C0509: a more specific case of C0503 — a wildcard or
			// variable pattern that is unreachable because an earlier
			// wildcard/variable already saturated coverage.
			is_catch_all_redundant := false
			if cov.saturated {
				#partial switch p in arm.pattern {
				case ^CPattern_Wildcard, ^CPattern_Identifier:
					is_catch_all_redundant = true
				case:
				}
			}
			if is_catch_all_redundant {
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_wildcard_after_catch_all(pattern_span(arm.pattern, arm.span)),
				)
			} else {
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_redundant_pattern(arm.span),
				)
			}
		}

		collect_pattern_coverage(arm.pattern, &cov)
		collect_pattern_coverage(arm.pattern, &arm_coverages[i])

		arm_result := typecheck_synth(arm.body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)

		arms_t[i] = TMatch_Arm {
			pattern = pat_result.tpat,
			guard   = guard_t,
			body    = arm_result.texpr,
			span    = arm.span,
		}
	}

	// Exhaustiveness checking
	resolved_scrut := store.vars[int(resolve_var(store, scrutinee_result.var_id))]
	#partial switch inf in resolved_scrut.link {
	case Inferred_Type:
		#partial switch v in inf {
		case Inferred_Tag_Union_Row:
			// C0502 / C0504: recover the full variant set for this tag union.
			// The scrutinee's resolved var (after pattern typechecking) often
			// points at the pattern's open row (one entry), because unification
			// of a closed annotation row `[A | B]` with the open pattern row
			// `[A, ...rest]` stitches the remaining variants onto the pattern's
			// `tag_rest` rather than merging them into one row, and (for
			// payloaded unions) does not propagate the `closed` flag. So we
			// prefer the pre-pattern snapshot, then fall back to walking the
			// current chain. If a newtype owns the matched tags, its
			// `owned_tags` is the authoritative closed variant set instead.
			nt_name, has_owned := newtype_owning_tags(store, cov.tags)
			owned: []base.Intern_ID
			if has_owned {
				owned = store.newtype_decls[nt_name].owned_tags
			} else if len(scrut_pre_variants) > 0 {
				owned = scrut_pre_variants
			} else {
				owned_dyn := make([dynamic]base.Intern_ID, 0, 8)
				collect_tag_row_variants(store, scrutinee_result.var_id, &owned_dyn)
				owned = owned_dyn[:]
				defer delete(owned_dyn)
			}

			// C0502: non-exhaustive tag-union match. The variant set comes
			// from a newtype's owned_tags (closed by definition) or from
			// walking the scrutinee's row chain (which only carries multiple
			// variants when the scrutinee was annotated with a syntactic
			// `[A | B | C]` declaration——a fresh inline tag construction
			// yields a single-variant chain, so it produces no false
			// positive). Skip when coverage is saturated (wildcard/variable
			// arm present) —— that is always exhaustive.
			if len(owned) > 0 && !cov.saturated {
				missing_list: [dynamic]string
				missing_list = make([dynamic]string, 0, len(owned))
				defer delete(missing_list)
				for tag_id in owned {
					if !cov.tags[tag_id] {
						append(&missing_list, base.intern_get(store.interner, tag_id))
					}
				}
				if len(missing_list) > 0 {
					type_name := tag_union_type_name(store, nt_name, has_owned, owned)
					missing := missing_list[0]
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_non_exhaustive_tag(type_name, missing, e.span),
					)
				}
			}
			// C0504 fragile match: exhaustive without a wildcard when the
			// union is newtype-owned with more than one variant. Adding a
			// new variant would silently make this match non-exhaustive.
			// Only fires for newtype-owned unions (anonymous `[A | B]`
			// declarations can't gain variants after the fact).
			if has_owned && len(owned) > 1 && !cov.saturated {
				covered_all := true
				for tag_id in owned {
					if !cov.tags[tag_id] {covered_all = false; break}
				}
				if covered_all {
					type_name := base.intern_get(store.interner, nt_name)
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_fragile_match(type_name, e.span),
					)
				}
			}
		case Inferred_Primitive:
			// Bool exhaustiveness: must cover both true and false
			if v.primitive_name == base.intern(store.interner, "Bool") && !cov.saturated {
				if !cov.bool_values[true] || !cov.bool_values[false] {
					missing: string
					if !cov.bool_values[true] && !cov.bool_values[false] {
						missing = "True and False"
					} else if !cov.bool_values[true] {
						missing = "True"
					} else {
						missing = "False"
					}
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_non_exhaustive_bool(missing, e.span),
					)
				}
			}
			// Int/String exhaustiveness: can never be exhaustive without wildcard
			if !cov.saturated {
				prim_name := base.intern_get(store.interner, v.primitive_name)
				if prim_name == "I64" ||
				   prim_name == "I32" ||
				   prim_name == "I16" ||
				   prim_name == "I8" ||
				   prim_name == "U64" ||
				   prim_name == "U32" ||
				   prim_name == "U16" ||
				   prim_name == "U8" {
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_non_exhaustive_int_string(prim_name, e.span),
					)
				}
				if prim_name == "Str" {
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_non_exhaustive_int_string(prim_name, e.span),
					)
				}
			}
		}
	case Type_Unlinked, base.Type_Var_ID:
	}

	t := new(TExpr_Match)
	t^ = TExpr_Match {
		scrutinee = scrutinee_result.texpr,
		arms      = arms_t,
		type_     = lower_type(store, result_var),
		eff_      = lower_effect_type(store, effect_row),
		span      = e.span,
	}
	return Synth_Result{var_id = result_var, effects = effect_row, texpr = TExpr(t)}
}


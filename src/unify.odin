package camp

import "core:fmt"

unify :: proc(store: ^Type_Store, a: Type_Var_ID, b: Type_Var_ID) -> bool {
	ra := resolve_var(store, a)
	rb := resolve_var(store, b)

	if ra == rb {
		return true
	}

	va := get_var(store, ra)
	vb := get_var(store, rb)

	if va.kind != vb.kind {
		if va.kind == .Value && vb.kind != .Value {
			inf, is_inf := va.link.(Inferred_Type)
			if is_inf && ((inf.tag == .Tag_Union_Row && vb.kind == .Row_Tag) || (inf.tag == .Record_Row && vb.kind == .Row_Record) || (inf.tag == .Effect_Row && vb.kind == .Row_Effect)) {
				if vb.kind == .Row_Tag {
					return unify(store, inf.tag_rest, rb)
				} else if vb.kind == .Row_Record {
					return unify(store, inf.record_rest, rb)
				} else if vb.kind == .Row_Effect {
					return unify(store, inf.rest_id, rb)
				}
			}
			collector_add_diag(store.collector, diag_value_row_conflict("value", "row", va.span, vb.span))
			return false
		}
		if va.kind != .Value && vb.kind == .Value {
			inf, is_inf := vb.link.(Inferred_Type)
			if is_inf && ((inf.tag == .Tag_Union_Row && va.kind == .Row_Tag) || (inf.tag == .Record_Row && va.kind == .Row_Record) || (inf.tag == .Effect_Row && va.kind == .Row_Effect)) {
				if va.kind == .Row_Tag {
					return unify(store, ra, inf.tag_rest)
				} else if va.kind == .Row_Record {
					return unify(store, ra, inf.record_rest)
				} else if va.kind == .Row_Effect {
					return unify(store, ra, inf.rest_id)
				}
			}
			collector_add_diag(store.collector, diag_value_row_conflict("row", "value", va.span, vb.span))
			return false
		}
	}

	if len(store.rec_vars) > 0 {
		if occurs_check(store, ra, rb) {
			if !is_rec_var_reachable(store, ra) {
				collector_add_diag(store.collector, diag_infinite_type("infinite type", va.span, vb.span))
				return false
			}
		}
		if occurs_check(store, rb, ra) {
			if !is_rec_var_reachable(store, rb) {
				collector_add_diag(store.collector, diag_infinite_type("infinite type", va.span, vb.span))
				return false
			}
		}
	} else {
		if occurs_check(store, ra, rb) || occurs_check(store, rb, ra) {
			collector_add_diag(store.collector, diag_infinite_type("infinite type", va.span, vb.span))
			return false
		}
	}

	max_level := max(va.level, vb.level)
	va.level = max_level
	vb.level = max_level

	_, a_unlinked := va.link.(Type_Unlinked)
	_, b_unlinked := vb.link.(Type_Unlinked)

	if a_unlinked && b_unlinked {
		if int(ra) < int(rb) {
			link_var(store, rb, ra)
		} else {
			link_var(store, ra, rb)
		}
	} else if a_unlinked {
		link_var(store, ra, rb)
	} else if b_unlinked {
		link_var(store, rb, ra)
	} else {
		a_inf, a_is_inf := va.link.(Inferred_Type)
		b_inf, b_is_inf := vb.link.(Inferred_Type)
		if a_is_inf && b_is_inf {
			if !unify_inferred(store, a_inf, b_inf, ra, rb) {
				return false
			}
			if int(ra) < int(rb) {
				link_var(store, rb, ra)
			} else {
				link_var(store, ra, rb)
			}
		} else {
			if int(ra) < int(rb) {
				link_var(store, rb, ra)
			} else {
				link_var(store, ra, rb)
			}
		}
	}

	check_constraint_violation(ra, store)
	check_constraint_violation(rb, store)

	return true
}

unify_inferred :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, a_id: Type_Var_ID, b_id: Type_Var_ID) -> bool {
	if a.tag != b.tag {
		type_a_str := format_inferred_type(store, a)
		type_b_str := format_inferred_type(store, b)
		va := get_var(store, resolve_var(store, a_id))
		vb := get_var(store, resolve_var(store, b_id))
		collector_add_diag(store.collector, diag_type_mismatch(type_a_str, type_b_str, va.span, vb.span))
		return false
	}

	if a.tag == .Primitive && a.primitive_name != b.primitive_name {
		name_a := intern_get(store.interner, a.primitive_name)
		name_b := intern_get(store.interner, b.primitive_name)
		va := get_var(store, resolve_var(store, a_id))
		vb := get_var(store, resolve_var(store, b_id))
		collector_add_diag(store.collector, diag_primitive_mismatch(name_a, name_b, va.span, vb.span))
		return false
	}

	switch a.tag {
	case .Function:
		if len(a.param_ids) != len(b.param_ids) {
			va := get_var(store, resolve_var(store, a_id))
			vb := get_var(store, resolve_var(store, b_id))
			collector_add_diag(store.collector, diag_arity_mismatch(len(a.param_ids), len(b.param_ids), va.span, vb.span))
			return false
		}
		for i in 0..<len(a.param_ids) {
			if !unify(store, a.param_ids[i], b.param_ids[i]) {
				return false
			}
		}
		if !unify(store, a.return_id, b.return_id) {
			return false
		}
		if !unify(store, a.effect_id, b.effect_id) {
			return false
		}

	case .Effect_Row:
		if !unify_effect_rows(store, a, b) {
			return false
		}

	case .Record_Row:
		if !unify_record_rows(store, a, b) {
			return false
		}

	case .Tag_Union_Row:
		if !unify_tag_union_rows(store, a, b, a_id, b_id) {
			return false
		}

	case .Newtype:
		if a.primitive_name != b.primitive_name {
			name_a := intern_get(store.interner, a.primitive_name)
			name_b := intern_get(store.interner, b.primitive_name)
			va := get_var(store, resolve_var(store, a_id))
			vb := get_var(store, resolve_var(store, b_id))
			collector_add_diag(store.collector, diag_primitive_mismatch(name_a, name_b, va.span, vb.span))
			return false
		}
		if len(a.param_ids) != len(b.param_ids) {
			va := get_var(store, resolve_var(store, a_id))
			vb := get_var(store, resolve_var(store, b_id))
			collector_add_diag(store.collector, diag_arity_mismatch(len(a.param_ids), len(b.param_ids), va.span, vb.span))
			return false
		}
		for i in 0..<len(a.param_ids) {
			if !unify(store, a.param_ids[i], b.param_ids[i]) {
				return false
			}
		}
		if !unify(store, a.inner_id, b.inner_id) {
			return false
		}

	case .Handle:
		if !unify(store, a.inner_id, b.inner_id) {
			return false
		}
		if !unify(store, a.effect_id, b.effect_id) {
			return false
		}

	case .Primitive, .Constructor:
	}

	return true
}

unify_effect_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type) -> bool {
	a_only: [dynamic]Effect_Row_Entry
	a_only = make([dynamic]Effect_Row_Entry, 0, len(a.effects))
	defer delete(a_only)

	b_only: [dynamic]Effect_Row_Entry
	b_only = make([dynamic]Effect_Row_Entry, 0, len(b.effects))
	defer delete(b_only)

	for ae in a.effects {
		found := false
		for be in b.effects {
			if ae.name == be.name {
				found = true
				// Unify type args for matching effects
				if len(ae.type_args) == len(be.type_args) {
					for i in 0..<len(ae.type_args) {
						if !unify(store, ae.type_args[i], be.type_args[i]) {
							return false
						}
					}
				} else if len(ae.type_args) > 0 || len(be.type_args) > 0 {
					// Arity mismatch
					return false
				}
				break
			}
		}
		if !found {
			append(&a_only, ae)
		}
	}

	for be in b.effects {
		found := false
		for ae in a.effects {
			if be.name == ae.name {
				found = true
				break
			}
		}
		if !found {
			append(&b_only, be)
		}
	}

	if len(a_only) == 0 && len(b_only) == 0 {
		return unify(store, a.rest_id, b.rest_id)
	}

	shared_rest := fresh_effect_row(store, Source_Span_ZERO)

	if len(b_only) > 0 {
		b_only_entries := store_alloc(store, Effect_Row_Entry, len(b_only))
		for i in 0..<len(b_only) {
			b_only_entries[i] = b_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Effect_Row,
			effects = b_only_entries,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, a.rest_id, rem_var) {
			return false
		}
	} else {
		if !unify(store, a.rest_id, shared_rest) {
			return false
		}
	}

	if len(a_only) > 0 {
		a_only_entries := store_alloc(store, Effect_Row_Entry, len(a_only))
		for i in 0..<len(a_only) {
			a_only_entries[i] = a_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Effect_Row,
			effects = a_only_entries,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, b.rest_id, rem_var) {
			return false
		}
	} else {
		if !unify(store, b.rest_id, shared_rest) {
			return false
		}
	}

	return true
}

unify_record_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type) -> bool {
	a_only: [dynamic]Type_Field_Entry
	a_only = make([dynamic]Type_Field_Entry, 0, len(a.record_fields))
	defer delete(a_only)

	b_only: [dynamic]Type_Field_Entry
	b_only = make([dynamic]Type_Field_Entry, 0, len(b.record_fields))
	defer delete(b_only)

	for af in a.record_fields {
		found := false
		for bf in b.record_fields {
			if af.name == bf.name {
				found = true
				if !unify(store, af.var, bf.var) {
					return false
				}
				break
			}
		}
		if !found {
			append(&a_only, af)
		}
	}

	for bf in b.record_fields {
		found := false
		for af in a.record_fields {
			if bf.name == af.name {
				found = true
				break
			}
		}
		if !found {
			append(&b_only, bf)
		}
	}

	if len(a_only) == 0 && len(b_only) == 0 {
		return unify(store, a.record_rest, b.record_rest)
	}

	shared_rest := fresh_record_row(store, Source_Span_ZERO)

	if len(b_only) > 0 {
		fields := store_alloc(store, Type_Field_Entry, len(b_only))
		for i in 0..<len(b_only) {
			fields[i] = b_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Record_Row,
			record_fields = fields,
			record_rest = shared_rest,
		}
		rem_var := fresh_record_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, a.record_rest, rem_var) {
			return false
		}
	} else {
		if !unify(store, a.record_rest, shared_rest) {
			return false
		}
	}

	if len(a_only) > 0 {
		fields := store_alloc(store, Type_Field_Entry, len(a_only))
		for i in 0..<len(a_only) {
			fields[i] = a_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Record_Row,
			record_fields = fields,
			record_rest = shared_rest,
		}
		rem_var := fresh_record_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, b.record_rest, rem_var) {
			return false
		}
	} else {
		if !unify(store, b.record_rest, shared_rest) {
			return false
		}
	}

	return true
}

unify_tag_union_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, a_id: Type_Var_ID, b_id: Type_Var_ID) -> bool {
	a_only: [dynamic]Type_Tag_Entry
	a_only = make([dynamic]Type_Tag_Entry, 0, len(a.tag_entries))
	defer delete(a_only)

	b_only: [dynamic]Type_Tag_Entry
	b_only = make([dynamic]Type_Tag_Entry, 0, len(b.tag_entries))
	defer delete(b_only)

	for at in a.tag_entries {
		found := false
		for bt in b.tag_entries {
			if at.name == bt.name {
				found = true
				if len(at.payload) != len(bt.payload) {
					tag_name := intern_get(store.interner, at.name)
					va := get_var(store, resolve_var(store, a_id))
					vb := get_var(store, resolve_var(store, b_id))
					collector_add_diag(store.collector, diag_tag_arity_mismatch(tag_name, len(at.payload), len(bt.payload), va.span, vb.span))
					return false
				}
				for i in 0..<len(at.payload) {
					if !unify(store, at.payload[i], bt.payload[i]) {
						return false
					}
				}
				break
			}
		}
		if !found {
			append(&a_only, at)
		}
	}

	for bt in b.tag_entries {
		found := false
		for at in a.tag_entries {
			if bt.name == at.name {
				found = true
				break
			}
		}
		if !found {
			append(&b_only, bt)
		}
	}

	if len(a_only) == 0 && len(b_only) == 0 {
		return unify(store, a.tag_rest, b.tag_rest)
	}

	shared_rest := fresh_tag_row(store, Source_Span_ZERO)

	if len(b_only) > 0 {
		entries := store_alloc(store, Type_Tag_Entry, len(b_only))
		for i in 0..<len(b_only) {
			entries[i] = b_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = entries,
			tag_rest = shared_rest,
		}
		rem_var := fresh_tag_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, a.tag_rest, rem_var) {
			return false
		}
	} else {
		if !unify(store, a.tag_rest, shared_rest) {
			return false
		}
	}

	if len(a_only) > 0 {
		entries := store_alloc(store, Type_Tag_Entry, len(a_only))
		for i in 0..<len(a_only) {
			entries[i] = a_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = entries,
			tag_rest = shared_rest,
		}
		rem_var := fresh_tag_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		if !unify(store, b.tag_rest, rem_var) {
			return false
		}
	} else {
		if !unify(store, b.tag_rest, shared_rest) {
			return false
		}
	}

	return true
}

occurs_check :: proc(store: ^Type_Store, target: Type_Var_ID, in_var: Type_Var_ID) -> bool {
	rv := resolve_var(store, in_var)
	if rv == target {
		return !store.rec_vars[target]
	}

	v := get_var(store, rv)

	inf, is_inf := v.link.(Inferred_Type)
	if is_inf {
		return occurs_check_inferred(store, target, inf)
	}

	linked_id, is_id := v.link.(Type_Var_ID)
	if is_id {
		return occurs_check(store, target, linked_id)
	}
	return false
}

occurs_check_inferred :: proc(store: ^Type_Store, target: Type_Var_ID, inf: Inferred_Type) -> bool {
	switch inf.tag {
	case .Function:
		for pid in inf.param_ids {
			if occurs_check(store, target, pid) {
				return true
			}
		}
		if occurs_check(store, target, inf.return_id) {
			return true
		}
		if occurs_check(store, target, inf.effect_id) {
			return true
		}
	case .Effect_Row:
		if occurs_check(store, target, inf.rest_id) {
			return true
		}
	case .Record_Row:
		for f in inf.record_fields {
			if occurs_check(store, target, f.var) {
				return true
			}
		}
		if occurs_check(store, target, inf.record_rest) {
			return true
		}
	case .Tag_Union_Row:
		for te in inf.tag_entries {
			for pid in te.payload {
				if occurs_check(store, target, pid) {
					return true
				}
			}
		}
		if occurs_check(store, target, inf.tag_rest) {
			return true
		}
	case .Newtype:
		for pid in inf.param_ids {
			if occurs_check(store, target, pid) {
				return true
			}
		}
		if occurs_check(store, target, inf.inner_id) {
			return true
		}
	case .Handle:
		if occurs_check(store, target, inf.inner_id) {
			return true
		}
		if occurs_check(store, target, inf.effect_id) {
			return true
		}
	case .Primitive, .Constructor:
	}
	return false
}

format_inferred_type :: proc(store: ^Type_Store, t: Inferred_Type) -> string {
	#partial switch t.tag {
	case .Primitive:
		return intern_get(store.interner, t.primitive_name)
	case .Constructor:
		return intern_get(store.interner, t.primitive_name)
	case .Newtype:
		return intern_get(store.interner, t.primitive_name)
	case .Function:
		return fmt.tprintf("({} params) -> {}", len(t.param_ids), format_type_var(store, t.return_id))
	case .Record_Row:
		return "record"
	case .Tag_Union_Row:
		return "tag union"
	case .Effect_Row:
		return "effect row"
	case .Handle:
		return fmt.tprintf("Handle({}, {})", format_type_var(store, t.inner_id), format_type_var(store, t.effect_id))
	case:
		return "unknown"
	}
}

format_type_var :: proc(store: ^Type_Store, id: Type_Var_ID) -> string {
	rid := resolve_var(store, id)
	rv := get_var(store, rid)
	it, is_inferred := rv.link.(Inferred_Type)
	if rv.kind == .Value && is_inferred {
		return format_inferred_type(store, it)
	}
	return "?"
}

is_rec_var_reachable :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> bool {
	resolved := resolve_var(store, var_id)
	for rv, _ in store.rec_vars {
		rv_resolved := resolve_var(store, rv)
		if rv_resolved == resolved {
			return true
		}
		if occurs_check(store, resolved, rv_resolved) {
			return true
		}
	}
	return false
}

package camp

import "core:fmt"

Unify_Error :: struct {
	message: string,
	span_a:  Source_Span,
	span_b:  Source_Span,
}

unify :: proc(store: ^Type_Store, a: Type_Var_ID, b: Type_Var_ID) -> ^Unify_Error {
	ra := resolve_var(store, a)
	rb := resolve_var(store, b)

	if ra == rb {
		return nil
	}

	va := get_var(store, ra)
	vb := get_var(store, rb)

	if va.kind != vb.kind {
		if va.kind == .Value && vb.kind != .Value {
			return make_unify_error(store, ra, rb, "cannot unify value type with row type")
		}
		if va.kind != .Value && vb.kind == .Value {
			return make_unify_error(store, ra, rb, "cannot unify row type with value type")
		}
	}

	if occurs_check(store, ra, rb) {
		return make_unify_error(store, ra, rb, "infinite type (occurs check failed)")
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
			err := unify_inferred(store, a_inf, b_inf, ra)
			if err != nil {
				return err
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

	return nil
}

unify_inferred :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, context_var: Type_Var_ID) -> ^Unify_Error {
	if a.tag != b.tag {
		span := get_var(store, context_var).span
		collector_add(store.collector, .Error,
			fmt.tprintf("type mismatch: {} vs {}", a.tag, b.tag),
			span)
		err := new(Unify_Error)
		err^ = Unify_Error{
			message = fmt.tprintf("type mismatch: {} vs {}", a.tag, b.tag),
			span_a = Source_Span_ZERO,
			span_b = Source_Span_ZERO,
		}
		return err
	}

	if a.tag == .Primitive && a.primitive_name != b.primitive_name {
		span := get_var(store, context_var).span
		collector_add(store.collector, .Error,
			fmt.tprintf("primitive mismatch: {} vs {}", a.primitive_name, b.primitive_name),
			span)
		err := new(Unify_Error)
		err^ = Unify_Error{
			message = "primitive type mismatch",
			span_a = Source_Span_ZERO,
			span_b = Source_Span_ZERO,
		}
		return err
	}

	switch a.tag {
	case .Function:
		if len(a.param_ids) != len(b.param_ids) {
			return make_unify_error(store, context_var, context_var,
				fmt.tprintf("function arity mismatch: {} vs {}", len(a.param_ids), len(b.param_ids)))
		}
		for i in 0..<len(a.param_ids) {
			err := unify(store, a.param_ids[i], b.param_ids[i])
			if err != nil {
				return err
			}
		}
		err := unify(store, a.return_id, b.return_id)
		if err != nil {
			return err
		}
		err = unify(store, a.effect_id, b.effect_id)
		if err != nil {
			return err
		}

	case .Effect_Row:
		err := unify_effect_rows(store, a, b, context_var)
		if err != nil {
			return err
		}

	case .Record_Row:
		err := unify_record_rows(store, a, b, context_var)
		if err != nil {
			return err
		}

	case .Tag_Union_Row:
		err := unify_tag_union_rows(store, a, b, context_var)
		if err != nil {
			return err
		}

	case .Primitive, .Constructor:
	}

	return nil
}

unify_effect_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, context_var: Type_Var_ID) -> ^Unify_Error {
	a_only: [dynamic]Intern_ID
	a_only = make([dynamic]Intern_ID, 0, len(a.effect_names))
	defer delete(a_only)

	b_only: [dynamic]Intern_ID
	b_only = make([dynamic]Intern_ID, 0, len(b.effect_names))
	defer delete(b_only)

	for an in a.effect_names {
		found := false
		for bn in b.effect_names {
			if an == bn {
				found = true
				break
			}
		}
		if !found {
			append(&a_only, an)
		}
	}

	for bn in b.effect_names {
		found := false
		for an in a.effect_names {
			if bn == an {
				found = true
				break
			}
		}
		if !found {
			append(&b_only, bn)
		}
	}

	if len(a_only) == 0 && len(b_only) == 0 {
		return unify(store, a.rest_id, b.rest_id)
	}

	shared_rest := fresh_effect_row(store, Source_Span_ZERO)

	if len(b_only) > 0 {
		names := store_alloc(store, Intern_ID, len(b_only))
		for i in 0..<len(b_only) {
			names[i] = b_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Effect_Row,
			effect_names = names,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, a.rest_id, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, a.rest_id, shared_rest)
		if err != nil {
			return err
		}
	}

	if len(a_only) > 0 {
		names := store_alloc(store, Intern_ID, len(a_only))
		for i in 0..<len(a_only) {
			names[i] = a_only[i]
		}
		rem_type := Inferred_Type{
			tag = .Effect_Row,
			effect_names = names,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, b.rest_id, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, b.rest_id, shared_rest)
		if err != nil {
			return err
		}
	}

	return nil
}

unify_record_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, context_var: Type_Var_ID) -> ^Unify_Error {
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
				err := unify(store, af.var, bf.var)
				if err != nil {
					return err
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
		rem_var := fresh_value_var(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, a.record_rest, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, a.record_rest, shared_rest)
		if err != nil {
			return err
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
		rem_var := fresh_value_var(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, b.record_rest, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, b.record_rest, shared_rest)
		if err != nil {
			return err
		}
	}

	return nil
}

unify_tag_union_rows :: proc(store: ^Type_Store, a: Inferred_Type, b: Inferred_Type, context_var: Type_Var_ID) -> ^Unify_Error {
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
					return make_unify_error(store, context_var, context_var,
						fmt.tprintf("tag payload arity mismatch for {}: {} vs {}", at.name, len(at.payload), len(bt.payload)))
				}
				for i in 0..<len(at.payload) {
					err := unify(store, at.payload[i], bt.payload[i])
					if err != nil {
						return err
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
		rem_var := fresh_value_var(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, a.tag_rest, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, a.tag_rest, shared_rest)
		if err != nil {
			return err
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
		rem_var := fresh_value_var(store, Source_Span_ZERO)
		link_var(store, rem_var, rem_type)
		err := unify(store, b.tag_rest, rem_var)
		if err != nil {
			return err
		}
	} else {
		err := unify(store, b.tag_rest, shared_rest)
		if err != nil {
			return err
		}
	}

	return nil
}

occurs_check :: proc(store: ^Type_Store, target: Type_Var_ID, in_var: Type_Var_ID) -> bool {
	rv := resolve_var(store, in_var)
	if rv == target {
		return true
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
	case .Primitive, .Constructor:
	}
	return false
}

make_unify_error :: proc(store: ^Type_Store, a: Type_Var_ID, b: Type_Var_ID, message: string) -> ^Unify_Error {
	va := get_var(store, a)
	vb := get_var(store, b)
	collector_add(store.collector, .Error, message, va.span)
	err := new(Unify_Error)
	err^ = Unify_Error{message = message, span_a = va.span, span_b = vb.span}
	return err
}

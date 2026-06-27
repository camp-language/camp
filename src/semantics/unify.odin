package semantics

import "core:fmt"

import "core:strings"

import "camp:base"
import "camp:diagnostics"

unify :: proc(store: ^Type_Store, a: base.Type_Var_ID, b: base.Type_Var_ID) -> bool {
	ra := resolve_var(store, a)
	rb := resolve_var(store, b)

	if ra == rb {
		return true
	}

	va := store.vars[int(ra)]
	vb := store.vars[int(rb)]

	if va.kind != vb.kind {
		if va.kind == .Value && vb.kind != .Value {
			inf, is_inf := va.link.(Inferred_Type)
			if is_inf {
				switch v in inf {
				case Inferred_Tag_Union_Row:
					if vb.kind == .Row_Tag {
						return unify(store, v.tag_rest, rb)
					}
				case Inferred_Record_Row:
					if vb.kind == .Row_Record {
						return unify(store, v.record_rest, rb)
					}
				case Inferred_Effect_Row:
					if vb.kind == .Row_Effect {
						return unify(store, v.rest_id, rb)
					}
				case Inferred_Primitive,
				     Inferred_Constructor,
				     Inferred_Function,
				     Inferred_Newtype,
				     Inferred_Handle,
				     Inferred_Tuple:
				}
			}
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_value_row_conflict("value", "row", va.span, vb.span),
			)
			return false
		}
		if va.kind != .Value && vb.kind == .Value {
			inf, is_inf := vb.link.(Inferred_Type)
			if is_inf {
				switch v in inf {
				case Inferred_Tag_Union_Row:
					if va.kind == .Row_Tag {
						return unify(store, ra, v.tag_rest)
					}
				case Inferred_Record_Row:
					if va.kind == .Row_Record {
						return unify(store, ra, v.record_rest)
					}
				case Inferred_Effect_Row:
					if va.kind == .Row_Effect {
						return unify(store, ra, v.rest_id)
					}
				case Inferred_Primitive,
				     Inferred_Constructor,
				     Inferred_Function,
				     Inferred_Newtype,
				     Inferred_Handle,
				     Inferred_Tuple:
				}
			}
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_value_row_conflict("row", "value", va.span, vb.span),
			)
			return false
		}
	}

	if len(store.rec_vars) > 0 {
		if occurs_check(store, ra, rb) {
			if !is_rec_var_reachable(store, ra) {
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_infinite_type("infinite type", va.span, vb.span),
				)
				return false
			}
		}
		if occurs_check(store, rb, ra) {
			if !is_rec_var_reachable(store, rb) {
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_infinite_type("infinite type", va.span, vb.span),
				)
				return false
			}
		}
	} else {
		if occurs_check(store, ra, rb) || occurs_check(store, rb, ra) {
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_infinite_type("infinite type", va.span, vb.span),
			)
			return false
		}
	}

	max_level := max(va.level, vb.level)
	store.vars[int(ra)].level = max_level
	store.vars[int(rb)].level = max_level

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
			// unify_inferred handles structural unification and may
			// already link vars (e.g. try_narrow_literal links lit→target).
			// Only create a representative link if neither side was already
			// linked during structural unification.
			ra_resolved := resolve_var(store, ra)
			rb_resolved := resolve_var(store, rb)
			if ra_resolved != rb_resolved {
				if int(ra) < int(rb) {
					link_var(store, rb, ra)
				} else {
					link_var(store, ra, rb)
				}
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

unify_inferred :: proc(
	store: ^Type_Store,
	a: Inferred_Type,
	b: Inferred_Type,
	a_id: base.Type_Var_ID,
	b_id: base.Type_Var_ID,
) -> bool {
	switch va in a {
	case Inferred_Primitive:
		vb, ok := b.(Inferred_Primitive)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if va.primitive_name != vb.primitive_name {
			if try_narrow_literal(store, va, vb, a_id, b_id) {
				return true
			}
			if try_narrow_literal(store, vb, va, b_id, a_id) {
				return true
			}
			name_a := base.intern_get(store.interner, va.primitive_name)
			name_b := base.intern_get(store.interner, vb.primitive_name)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_primitive_mismatch(name_a, name_b, va_var.span, vb_var.span),
			)
			return false
		}

	case Inferred_Constructor:
		a_cons := a.(Inferred_Constructor)
		b_cons, ok := b.(Inferred_Constructor)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if a_cons.primitive_name != b_cons.primitive_name {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if a_cons.arity != b_cons.arity {
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_arity_mismatch(
					a_cons.arity,
					b_cons.arity,
					va_var.span,
					vb_var.span,
				),
			)
			return false
		}

	case Inferred_Function:
		vb, ok := b.(Inferred_Function)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if len(va.param_ids) != len(vb.param_ids) {
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_arity_mismatch(
					len(va.param_ids),
					len(vb.param_ids),
					va_var.span,
					vb_var.span,
				),
			)
			return false
		}
		for i in 0 ..< len(va.param_ids) {
			if !unify(store, va.param_ids[i], vb.param_ids[i]) {
				return false
			}
		}
		if !unify(store, va.return_id, vb.return_id) {
			return false
		}
		if !unify(store, va.effect_id, vb.effect_id) {
			return false
		}

	case Inferred_Newtype:
		vb, ok := b.(Inferred_Newtype)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if va.primitive_name != vb.primitive_name {
			name_a := base.intern_get(store.interner, va.primitive_name)
			name_b := base.intern_get(store.interner, vb.primitive_name)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_primitive_mismatch(name_a, name_b, va_var.span, vb_var.span),
			)
			return false
		}
		if len(va.param_ids) != len(vb.param_ids) {
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_arity_mismatch(
					len(va.param_ids),
					len(vb.param_ids),
					va_var.span,
					vb_var.span,
				),
			)
			return false
		}
		for i in 0 ..< len(va.param_ids) {
			if !unify(store, va.param_ids[i], vb.param_ids[i]) {
				return false
			}
		}
		if !unify(store, va.inner_id, vb.inner_id) {
			return false
		}

	case Inferred_Record_Row:
		vb, ok := b.(Inferred_Record_Row)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if !unify_record_rows(store, va, vb) {
			return false
		}

	case Inferred_Tag_Union_Row:
		vb, ok := b.(Inferred_Tag_Union_Row)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if !unify_tag_union_rows(store, va, vb, a_id, b_id) {
			return false
		}

	case Inferred_Effect_Row:
		vb, ok := b.(Inferred_Effect_Row)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if !unify_effect_rows(store, va, vb) {
			return false
		}

	case Inferred_Handle:
		vb, ok := b.(Inferred_Handle)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if !unify(store, va.inner_id, vb.inner_id) {
			return false
		}
		if !unify(store, va.effect_id, vb.effect_id) {
			return false
		}
	case Inferred_Tuple:
		vb, ok := b.(Inferred_Tuple)
		if !ok {
			type_a_str := format_inferred_type(store, a)
			type_b_str := format_inferred_type(store, b)
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
			)
			return false
		}
		if va.element_count != vb.element_count {
			va_var := store.vars[int(resolve_var(store, a_id))]
			vb_var := store.vars[int(resolve_var(store, b_id))]
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_arity_mismatch(
					va.element_count,
					vb.element_count,
					va_var.span,
					vb_var.span,
				),
			)
			return false
		}
		for i in 0 ..< len(va.element_types) {
			if !unify(store, va.element_types[i], vb.element_types[i]) {
				return false
			}
		}
	}

	return true
}

// NOTE: unify_effect_rows, unify_record_rows, and unify_tag_union_rows
// share the same structural pattern (compute a_only/b_only, unify rests via shared rest).
// They differ in entry types, field names, rest field names, fresh row functions,
// and inner unification logic (tag_union has arity checking).
// Extracting a common helper would require Odin generics or function pointer dispatch.

unify_effect_rows :: proc(
	store: ^Type_Store,
	a: Inferred_Effect_Row,
	b: Inferred_Effect_Row,
) -> bool {
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
					for i in 0 ..< len(ae.type_args) {
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

	shared_rest := fresh_effect_row(store, base.Source_Span_ZERO)

	if len(b_only) > 0 {
		b_only_entries := store_alloc(store, Effect_Row_Entry, len(b_only))
		for i in 0 ..< len(b_only) {
			b_only_entries[i] = b_only[i]
		}
		rem_type := Inferred_Effect_Row {
			effects = b_only_entries,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, base.Source_Span_ZERO)
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
		for i in 0 ..< len(a_only) {
			a_only_entries[i] = a_only[i]
		}
		rem_type := Inferred_Effect_Row {
			effects = a_only_entries,
			rest_id = shared_rest,
		}
		rem_var := fresh_effect_row(store, base.Source_Span_ZERO)
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

unify_record_rows :: proc(
	store: ^Type_Store,
	a: Inferred_Record_Row,
	b: Inferred_Record_Row,
) -> bool {
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

	// Closed records reject extra fields on the other side
	if a.closed && len(b_only) > 0 {
		type_a_str := format_inferred_type(
			store,
			Inferred_Record_Row {
				record_fields = a.record_fields,
				record_rest = a.record_rest,
				closed = a.closed,
			},
		)
		type_b_str := format_inferred_type(
			store,
			Inferred_Record_Row {
				record_fields = b.record_fields,
				record_rest = b.record_rest,
				closed = b.closed,
			},
		)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_type_mismatch(
				type_a_str,
				type_b_str,
				base.Source_Span_ZERO,
				base.Source_Span_ZERO,
			),
		)
		return false
	}
	if b.closed && len(a_only) > 0 {
		type_a_str := format_inferred_type(
			store,
			Inferred_Record_Row {
				record_fields = a.record_fields,
				record_rest = a.record_rest,
				closed = a.closed,
			},
		)
		type_b_str := format_inferred_type(
			store,
			Inferred_Record_Row {
				record_fields = b.record_fields,
				record_rest = b.record_rest,
				closed = b.closed,
			},
		)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_type_mismatch(
				type_a_str,
				type_b_str,
				base.Source_Span_ZERO,
				base.Source_Span_ZERO,
			),
		)
		return false
	}

	if len(a_only) == 0 && len(b_only) == 0 {
		return unify(store, a.record_rest, b.record_rest)
	}

	shared_rest := fresh_record_row(store, base.Source_Span_ZERO)

	if len(b_only) > 0 {
		fields := store_alloc(store, Type_Field_Entry, len(b_only))
		for i in 0 ..< len(b_only) {
			fields[i] = b_only[i]
		}
		rem_type := Inferred_Record_Row {
			record_fields = fields,
			record_rest   = shared_rest,
			closed        = false,
		}
		rem_var := fresh_record_row(store, base.Source_Span_ZERO)
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
		for i in 0 ..< len(a_only) {
			fields[i] = a_only[i]
		}
		rem_type := Inferred_Record_Row {
			record_fields = fields,
			record_rest   = shared_rest,
			closed        = false,
		}
		rem_var := fresh_record_row(store, base.Source_Span_ZERO)
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

unify_tag_union_rows :: proc(
	store: ^Type_Store,
	a: Inferred_Tag_Union_Row,
	b: Inferred_Tag_Union_Row,
	a_id: base.Type_Var_ID,
	b_id: base.Type_Var_ID,
) -> bool {
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
					tag_name := base.intern_get(store.interner, at.name)
					va := store.vars[int(resolve_var(store, a_id))]
					vb := store.vars[int(resolve_var(store, b_id))]
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_tag_arity_mismatch(
							tag_name,
							len(at.payload),
							len(bt.payload),
							va.span,
							vb.span,
						),
					)
					return false
				}
				for i in 0 ..< len(at.payload) {
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
		// Both rows have identical entry sets. Propagate closedness: if
		// either side is closed, both become closed (the union is at least
		// as closed as the most-closed side). This also handles the rest
		// unification below.
		if a.closed != b.closed {
			mark_tag_row_closed(store, a_id, a.closed || b.closed)
			mark_tag_row_closed(store, b_id, a.closed || b.closed)
		}
		return unify(store, a.tag_rest, b.tag_rest)
	}

	// camp-9xi6: propagate closedness from a closed all-no-payload superset
	// to an open subset. The common case is a bare tag `Blue` (open, one
	// entry, no payload) unifying with the closed `Color` declaration
	// `[Red | Green | Blue]`. After this, `Blue`'s tag_var resolves to a
	// closed row, so lower_type (re-derived at IR lowering in lower_ttag)
	// sees is_heap=false and the construction emits i32.const — matching
	// the closed-union match dispatch. Without this, construction stays
	// boxed while the scrutinee reads immediate (trap).
	//
	// Rule: side X is closed AND all its entries have no payload AND the
	// OTHER side adds no entries the closed side doesn't have (other's
	// a_only/b_only is empty) => the other side becomes closed. This is
	// conservative: only a closed all-no-payload superset absorbs an open
	// subset. A payloaded closed union (List/Result) never absorbs, so its
	// open tag pattern stays open (and stays boxed, correct).
	a_all_no_payload := row_all_entries_no_payload(a)
	b_all_no_payload := row_all_entries_no_payload(b)
	if !a.closed && b.closed && b_all_no_payload && len(a_only) == 0 {
		mark_tag_row_closed(store, a_id, true)
	}
	if !b.closed && a.closed && a_all_no_payload && len(b_only) == 0 {
		mark_tag_row_closed(store, b_id, true)
	}

	shared_rest := fresh_tag_row(store, base.Source_Span_ZERO)

	if len(b_only) > 0 {
		entries := store_alloc(store, Type_Tag_Entry, len(b_only))
		for i in 0 ..< len(b_only) {
			entries[i] = b_only[i]
		}
		rem_type := Inferred_Tag_Union_Row {
			tag_entries = entries,
			tag_rest    = shared_rest,
			// Remainder rows built during unification are OPEN (they
			// represent the variants unique to one side and unify with
			// the other side's open rest). Never a closed declaration.
			closed      = false,
		}
		rem_var := fresh_tag_row(store, base.Source_Span_ZERO)
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
		for i in 0 ..< len(a_only) {
			entries[i] = a_only[i]
		}
		rem_type := Inferred_Tag_Union_Row {
			tag_entries = entries,
			tag_rest    = shared_rest,
			// Remainder rows built during unification are OPEN (they
			// represent the variants unique to one side and unify with
			// the other side's open rest). Never a closed declaration.
			closed      = false,
		}
		rem_var := fresh_tag_row(store, base.Source_Span_ZERO)
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

// row_all_entries_no_payload returns true iff every entry in the row has an
// empty payload slice. Used by unify closedness propagation (camp-9xi6): only
// a closed all-no-payload superset absorbs an open subset into the immediate
// representation. A payloaded closed union (List/Result) returns false and does
// not absorb, keeping its tag patterns boxed.
row_all_entries_no_payload :: proc(row: Inferred_Tag_Union_Row) -> bool {
	for te in row.tag_entries {
		if len(te.payload) > 0 do return false
	}
	return true
}

// mark_tag_row_closed mutates the Inferred_Tag_Union_Row linked to type_var to
// set its `closed` field. Used by unify_tag_union_rows to propagate closedness
// from a closed all-no-payload superset to an open subset (e.g. bare `Blue`
// unifying with `Color`). Resolves the var, re-reads the link, rebuilds the
// row with closed overridden, and re-links. No-op if the var isn't linked to a
// tag-union row.
mark_tag_row_closed :: proc(store: ^Type_Store, type_var: base.Type_Var_ID, closed: bool) {
	resolved := resolve_var(store, type_var)
	v := &store.vars[int(resolved)]
	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf do return
	row, ok := inf.(Inferred_Tag_Union_Row)
	if !ok do return
	if row.closed == closed do return
	row.closed = closed
	v.link = Inferred_Type(row)
}

occurs_check :: proc(
	store: ^Type_Store,
	target: base.Type_Var_ID,
	in_var: base.Type_Var_ID,
) -> bool {
	visited := make(map[base.Type_Var_ID]bool, 16)
	defer delete(visited)
	return occurs_check_impl(store, target, in_var, &visited)
}

occurs_check_impl :: proc(
	store: ^Type_Store,
	target: base.Type_Var_ID,
	in_var: base.Type_Var_ID,
	visited: ^map[base.Type_Var_ID]bool,
) -> bool {
	rv := resolve_var(store, in_var)
	if rv == target {
		return !store.rec_vars[target]
	}

	if _, seen := visited[rv]; seen {
		return false
	}
	visited[rv] = true

	v := store.vars[int(rv)]

	inf, is_inf := v.link.(Inferred_Type)
	if is_inf {
		return occurs_check_inferred_impl(store, target, inf, visited)
	}

	linked_id, is_id := v.link.(base.Type_Var_ID)
	if is_id {
		return occurs_check_impl(store, target, linked_id, visited)
	}
	return false
}

occurs_check_inferred_impl :: proc(
	store: ^Type_Store,
	target: base.Type_Var_ID,
	inf: Inferred_Type,
	visited: ^map[base.Type_Var_ID]bool,
) -> bool {
	switch v in inf {
	case Inferred_Function:
		for pid in v.param_ids {
			if occurs_check_impl(store, target, pid, visited) {
				return true
			}
		}
		if occurs_check_impl(store, target, v.return_id, visited) {
			return true
		}
		if occurs_check_impl(store, target, v.effect_id, visited) {
			return true
		}
	case Inferred_Effect_Row:
		if occurs_check_impl(store, target, v.rest_id, visited) {
			return true
		}
		for entry in v.effects {
			for type_arg in entry.type_args {
				if occurs_check_impl(store, target, type_arg, visited) {
					return true
				}
			}
		}
	case Inferred_Record_Row:
		for f in v.record_fields {
			if occurs_check_impl(store, target, f.var, visited) {
				return true
			}
		}
		if occurs_check_impl(store, target, v.record_rest, visited) {
			return true
		}
	case Inferred_Tag_Union_Row:
		for te in v.tag_entries {
			for pid in te.payload {
				if occurs_check_impl(store, target, pid, visited) {
					return true
				}
			}
		}
		if occurs_check_impl(store, target, v.tag_rest, visited) {
			return true
		}
	case Inferred_Newtype:
		for pid in v.param_ids {
			if occurs_check_impl(store, target, pid, visited) {
				return true
			}
		}
		if occurs_check_impl(store, target, v.inner_id, visited) {
			return true
		}
	case Inferred_Handle:
		if occurs_check_impl(store, target, v.inner_id, visited) {
			return true
		}
		if occurs_check_impl(store, target, v.effect_id, visited) {
			return true
		}

	case Inferred_Tuple:
		for eid in v.element_types {
			if occurs_check_impl(store, target, eid, visited) {
				return true
			}
		}

	case Inferred_Primitive, Inferred_Constructor:
	}
	return false
}

format_inferred_type :: proc(store: ^Type_Store, t: Inferred_Type) -> string {
	switch v in t {
	case Inferred_Primitive:
		return base.intern_get(store.interner, v.primitive_name)
	case Inferred_Constructor:
		return base.intern_get(store.interner, v.primitive_name)
	case Inferred_Newtype:
		return base.intern_get(store.interner, v.primitive_name)
	case Inferred_Function:
		return fmt.tprintf(
			"({} params) -> {}",
			len(v.param_ids),
			format_type_var(store, v.return_id),
		)
	case Inferred_Record_Row:
		return "record"
	case Inferred_Tag_Union_Row:
		return "tag union"
	case Inferred_Effect_Row:
		return "effect row"
	case Inferred_Handle:
		return fmt.tprintf(
			"Handle({}, {})",
			format_type_var(store, v.inner_id),
			format_type_var(store, v.effect_id),
		)
	case Inferred_Tuple:
		parts: []string = make([]string, len(v.element_types))
		for i in 0 ..< len(v.element_types) {
			parts[i] = format_type_var(store, v.element_types[i])
		}
		return fmt.tprintf("({})", strings.join(parts, ", "))
	}
	return "unknown"
}

format_type_var :: proc(store: ^Type_Store, id: base.Type_Var_ID) -> string {
	rid := resolve_var(store, id)
	rv := store.vars[int(rid)]
	it, is_inferred := rv.link.(Inferred_Type)
	if rv.kind == .Value && is_inferred {
		return format_inferred_type(store, it)
	}
	return "?"
}

is_rec_var_reachable :: proc(store: ^Type_Store, var_id: base.Type_Var_ID) -> bool {
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

try_narrow_literal :: proc(
	store: ^Type_Store,
	lit_inf: Inferred_Primitive,
	target_inf: Inferred_Primitive,
	lit_id: base.Type_Var_ID,
	target_id: base.Type_Var_ID,
) -> bool {
	target_name_str := base.intern_get(store.interner, target_inf.primitive_name)

	if int_val, ok := store.literal_int_values[lit_id]; ok {
		if is_int_primitive_name(store, target_inf.primitive_name) &&
		   int_fits_type(int_val, target_name_str) {
			link_var(store, lit_id, target_id)
			return true
		}
	}

	if float_val, ok := store.literal_float_values[lit_id]; ok {
		if is_float_primitive_name(store, target_inf.primitive_name) &&
		   float_fits_type(float_val, target_name_str) {
			link_var(store, lit_id, target_id)
			return true
		}
	}

	return false
}


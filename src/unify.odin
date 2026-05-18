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

	return nil
}

occurs_check :: proc(store: ^Type_Store, target: Type_Var_ID, in_var: Type_Var_ID) -> bool {
	rv := resolve_var(store, in_var)
	if rv == target {
		return true
	}

	v := get_var(store, rv)
	linked_id, is_id := v.link.(Type_Var_ID)
	if is_id {
		return occurs_check(store, target, linked_id)
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

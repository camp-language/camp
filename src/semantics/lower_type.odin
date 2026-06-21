package semantics

import "camp:base"

lower_type :: proc(store: ^Type_Store, type_var: base.Type_Var_ID) -> base.IR_Type {
	resolved := resolve_var(store, type_var)
	v := &store.vars[int(resolved)]

	wasm_type: base.IR_Wasm_Type = .I64
	is_heap: bool = false

	inf, is_inf := v.link.(Inferred_Type)
	if is_inf {
		switch f in inf {
		case Inferred_Primitive:
			name_str := base.intern_get(store.interner, f.primitive_name)
			switch name_str {
			case "I64":
				wasm_type = .I64
			case "I32":
				wasm_type = .I32
			case "F64":
				wasm_type = .F64
			case "F32":
				wasm_type = .F32
			case "Bool", "Char":
				wasm_type = .I32
			case "Str":
				wasm_type = .I32; is_heap = true
			case "Unit":
				wasm_type = .Void
			case "I8", "I16", "U8", "U16", "U32", "U64":
				wasm_type = .I64
			}
		case Inferred_Function:
			wasm_type = .Funcref
		case Inferred_Record_Row:
			wasm_type = .I32; is_heap = true
		case Inferred_Tag_Union_Row:
			wasm_type = .I32
			// Unboxed-enum optimization (camp-9xi6): a CLOSED tag union whose
			// variants have NO payload across the board lowers to an immediate
			// i32 variant ordinal (Bool-style), eliminating per-value heap alloc
			// and RC drop/dup. Open rows (bare tags, list literals, match
			// patterns, generic instantiation) and payloaded unions stay boxed.
			// Newtype-wrapped unions route through the Inferred_Newtype case
			// above, which delegates is_heap to lower_type(inner_id) — so
			// @Order : [Less | Equal | Greater] reaches this branch via its
			// inner row and correctly becomes immediate.
			is_heap = !tag_union_is_immediate(store, resolved)
		case Inferred_Effect_Row:
			wasm_type = .Void
		case Inferred_Constructor:
			wasm_type = .I32; is_heap = true
		case Inferred_Newtype:
			inner := lower_type(store, f.inner_id)
			wasm_type = inner.wasm_type
			is_heap = inner.is_heap
		case Inferred_Handle:
			wasm_type = .I32; is_heap = true
		case Inferred_Tuple:
			wasm_type = .I32; is_heap = true
		}
	}

	return base.IR_Type{wasm_type = wasm_type, type_id = resolved, is_heap = is_heap}
}

lower_effect_type :: proc(store: ^Type_Store, eff_var: base.Type_Var_ID) -> base.IR_Type {
	resolved := resolve_var(store, eff_var)
	v := &store.vars[int(resolved)]
	if inf, is_inf := v.link.(Inferred_Type); is_inf {
		if _, ok := inf.(Inferred_Effect_Row); ok {
			return base.IR_Type{wasm_type = .Void, type_id = resolved}
		}
	}
	return base.IR_Type{wasm_type = .Void, type_id = eff_var}
}

// tag_union_is_immediate reports whether a closed, all-no-payload tag union
// should lower to an immediate i32 (camp-9xi6). Conditions:
//   1. The row itself is closed (set by convert_type_to_var_val for syntactic
//      `[A | B | ...]` declarations and by prelude synthesis for Order).
//   2. Every entry in tag_entries has an empty payload slice.
//   3. The tag_rest, if it resolves to another Inferred_Tag_Union_Row, also
//      satisfies (1) and (2) — i.e. a closed row that unified with another
//      closed row keeps the immediate property only if BOTH halves are
//      no-payload. An unresolved tag_rest (the common case for a closed
//      declaration — fresh_row never bound) means "no additional variants",
//      which is fine for a closed row.
// Any payloaded variant, any open sub-row, or a non-tag-union rest disqualifies.
tag_union_is_immediate :: proc(store: ^Type_Store, type_var: base.Type_Var_ID) -> bool {
	resolved := resolve_var(store, type_var)
	v := &store.vars[int(resolved)]
	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf do return false
	row, ok := inf.(Inferred_Tag_Union_Row)
	if !ok do return false
	if !row.closed do return false
	for te in row.tag_entries {
		if len(te.payload) > 0 do return false
	}
	// Walk the rest. An unresolved fresh Row_Tag var means "no more variants";
	// only a linked Inferred_Tag_Union_Row can add constraints.
	rest_resolved := resolve_var(store, row.tag_rest)
	rest_v := &store.vars[int(rest_resolved)]
	rest_inf, rest_is_inf := rest_v.link.(Inferred_Type)
	if rest_is_inf {
		if _, rest_is_row := rest_inf.(Inferred_Tag_Union_Row); rest_is_row {
			// Rest is itself a tag-union row — recurse. If it's open or has
			// a payload, this disqualifies the immediate optimization.
			return tag_union_is_immediate(store, row.tag_rest)
		}
		// Rest linked to a non-tag-union inferred type (shouldn't happen for
		// a tag row, but be conservative).
		return false
	}
	// Unresolved fresh row var: closed declaration with no additional variants.
	return true
}

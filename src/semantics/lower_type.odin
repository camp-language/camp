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
			case "Bool":
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
			wasm_type = .I32; is_heap = true
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


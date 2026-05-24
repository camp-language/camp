package semantics

import "camp:base"

lower_type :: proc(store: ^Type_Store, type_var: base.Type_Var_ID) -> base.IR_Type {
	resolved := resolve_var(store, type_var)
	v := &store.vars[int(resolved)]

	wasm_type: base.IR_Wasm_Type = .I64

	inf, is_inf := v.link.(Inferred_Type)
	if is_inf {
		switch inf.tag {
		case .Primitive:
			name_str := base.intern_get(store.interner, inf.primitive_name)
			switch name_str {
			case "I64": wasm_type = .I64
			case "I32": wasm_type = .I32
			case "F64": wasm_type = .F64
			case "F32": wasm_type = .F32
			case "Bool": wasm_type = .I32
			case "Str": wasm_type = .I32
			case "Unit": wasm_type = .Void
			case "I8", "I16", "U8", "U16", "U32", "U64": wasm_type = .I64
			}
		case .Function:
			wasm_type = .Funcref
		case .Record_Row:
			wasm_type = .I32
		case .Tag_Union_Row:
			wasm_type = .I32
		case .Effect_Row:
			wasm_type = .Void
		case .Constructor:
			wasm_type = .I32
		case .Newtype:
			wasm_type = lower_type(store, inf.inner_id).wasm_type
		case .Handle:
			wasm_type = .I32
		}
	}

	return base.IR_Type{wasm_type = wasm_type, type_id = resolved}
}

lower_effect_type :: proc(store: ^Type_Store, eff_var: base.Type_Var_ID) -> base.IR_Type {
	resolved := resolve_var(store, eff_var)
	v := &store.vars[int(resolved)]
	if inf, is_inf := v.link.(Inferred_Type); is_inf && inf.tag == .Effect_Row {
		return base.IR_Type{wasm_type = .Void, type_id = resolved}
	}
	return base.IR_Type{wasm_type = .Void, type_id = eff_var}
}

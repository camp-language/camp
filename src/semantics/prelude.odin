package semantics

import "core:fmt"

import "camp:base"

Prelude_Builtin_Type :: struct {
	name:           string,
	is_constructor: bool,
}

Prelude_Constructor_Type :: struct {
	name:  string,
	arity: int,
}

Prelude_Tag_Decl :: struct {
	name:        string,
	has_payload: bool,
}

PRELUDE_BUILTIN_TYPES :: []Prelude_Builtin_Type {
	{"Bool", true},
	{"I64", false},
	{"I32", false},
	{"U64", false},
	{"F64", false},
	{"F32", false},
	{"Str", false},
	{"Unit", false},
	{"I8", false},
	{"I16", false},
	{"U8", false},
	{"U16", false},
	{"U32", false},
	{"Bytes", false},
}

PRELUDE_CONSTRUCTOR_TYPES :: []Prelude_Constructor_Type {
	{"List", 1},
	{"Iter", 1},
	{"Map", 2},
	{"Set", 1},
	{"Handle", 1},
	{"Ordering", 0},
	{"Result", 2},
}

PRELUDE_TAG_DECLS :: []Prelude_Tag_Decl {
	{"True", false},
	{"False", false},
	{"Ok", true},
	{"Err", true},
	{"Less", false},
	{"Equal", false},
	{"Greater", false},
	{"Nil", false},
	{"Cons", true},
}

PRELUDE_EFFECT_FULL :: []string{"Console", "Throw", "Parallel", "Spawn", "Async"}
PRELUDE_EFFECT_FORWARD :: []string{"File", "Env", "Time", "Random", "Log", "CryptoRandom"}

is_prelude_effect :: proc(name: base.Intern_ID, interner: ^base.Intern_Table) -> bool {
	for eff in PRELUDE_EFFECT_FULL {
		if base.intern(interner, eff) == name {
			return true
		}
	}
	for eff in PRELUDE_EFFECT_FORWARD {
		if base.intern(interner, eff) == name {
			return true
		}
	}
	return false
}

prelude_resolve_type_ref :: proc(
	store: ^Type_Store,
	ref: string,
	generic_idx: int,
	generic_vars: ^map[int]base.Type_Var_ID,
) -> base.Type_Var_ID {
	if ref == "generic" {
		if v, ok := generic_vars^[generic_idx]; ok do return v
		v := fresh_value_var(store, base.Source_Span_ZERO)
		generic_vars^[generic_idx] = v
		return v
	}
	name_id := base.intern(store.interner, ref)
	if v, ok := store.bindings[name_id]; ok do return v
	return fresh_value_var(store, base.Source_Span_ZERO)
}

prelude_lower_type_ref :: proc(store: ^Type_Store, ref: string) -> base.IR_Type {
	if ref == "generic" {
		return base.IR_Type{wasm_type = .I32, type_id = 0}
	}
	name_id := base.intern(store.interner, ref)
	if v, ok := store.bindings[name_id]; ok {
		return lower_type(store, v)
	}
	return base.IR_Type{wasm_type = .I32, type_id = 0}
}

// NOTE: inject_prelude_effects_typecheck and inject_prelude_effects_lower
// are nearly identical in structure (same switch on eff_name, same per-effect
// operations). They differ in the type resolution function (prelude_resolve_type_ref
// vs prelude_lower_type_ref) and the target storage (store.effect_ops vs mod.effect_defs).
// Consider extracting the effect data (names, operations, signatures) into a shared table.

inject_prelude_effects_typecheck :: proc(store: ^Type_Store) {
	for eff_name in PRELUDE_EFFECT_FULL {
		name_id := base.intern(store.interner, eff_name)
		append(&store.declared_effects, name_id)

		generic_vars: map[int]base.Type_Var_ID
		generic_vars = make(map[int]base.Type_Var_ID, 4, store.allocator)

		ops := make([dynamic]Effect_Op_Sig, 0, 8, store.allocator)

		switch eff_name {
		case "Console":
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "println!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = prelude_resolve_type_ref(store, "Unit", 0, &generic_vars),
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"Str",
				0,
				&generic_vars,
			)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "readln!"),
					param_count = 0,
					param_types = make([]base.Type_Var_ID, 0, store.allocator),
					return_type = prelude_resolve_type_ref(store, "Str", 0, &generic_vars),
				},
			)
		case "Throw":
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "throw!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = prelude_resolve_type_ref(store, "generic", 1, &generic_vars),
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"generic",
				0,
				&generic_vars,
			)
		case "Parallel":
			items_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			f_type := prelude_resolve_type_ref(store, "generic", 1, &generic_vars)
			list_type := prelude_resolve_type_ref(store, "List", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "map!"),
					param_count = 2,
					param_types = make([]base.Type_Var_ID, 2, store.allocator),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].param_types[0] =
				items_type; ops[len(ops) - 1].param_types[1] = f_type
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "for_each!"),
					param_count = 2,
					param_types = make([]base.Type_Var_ID, 2, store.allocator),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].param_types[0] =
				items_type; ops[len(ops) - 1].param_types[1] = f_type
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "filter!"),
					param_count = 2,
					param_types = make([]base.Type_Var_ID, 2, store.allocator),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].param_types[0] =
				items_type; ops[len(ops) - 1].param_types[1] = f_type
			init_type := prelude_resolve_type_ref(store, "generic", 1, &generic_vars)
			reduce_f_type := prelude_resolve_type_ref(store, "generic", 2, &generic_vars)
			reduce_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "reduce!"),
					param_count = 3,
					param_types = make([]base.Type_Var_ID, 3, store.allocator),
					return_type = reduce_return,
				},
			)
			ops[len(ops) - 1].param_types[0] =
				items_type; ops[len(ops) - 1].param_types[1] = init_type; ops[len(ops) - 1].param_types[2] = reduce_f_type
			tasks_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "all!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = tasks_type
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "any!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = tasks_type
		case "Spawn":
			thunk_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			handle_type := prelude_resolve_type_ref(store, "Handle", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			join_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "spawn!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = handle_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = thunk_type
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "join!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = join_return,
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"generic",
				0,
				&generic_vars,
			)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "cancel!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"generic",
				0,
				&generic_vars,
			)
		case "Async":
			thunk_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			handle_type := prelude_resolve_type_ref(store, "Handle", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			join_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "spawn!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = handle_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = thunk_type
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "join!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = join_return,
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"generic",
				0,
				&generic_vars,
			)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "yield!"),
					param_count = 0,
					param_types = make([]base.Type_Var_ID, 0, store.allocator),
					return_type = unit_type,
				},
			)
			append(
				&ops,
				Effect_Op_Sig {
					name = base.intern(store.interner, "cancel!"),
					param_count = 1,
					param_types = make([]base.Type_Var_ID, 1, store.allocator),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].param_types[0] = prelude_resolve_type_ref(
				store,
				"generic",
				0,
				&generic_vars,
			)
		}

		store.effect_ops[name_id] = ops[:]
		delete(generic_vars)
	}

	for eff_name in PRELUDE_EFFECT_FORWARD {
		name_id := base.intern(store.interner, eff_name)
		append(&store.declared_effects, name_id)
	}

	// Register Display trait with to_str: (Self) -> Str
	display_name := base.intern(store.interner, "Display")
	to_str_name := base.intern(store.interner, "to_str")

	if !is_trait_declared(store, display_name) {
		display_generic_vars: map[int]base.Type_Var_ID
		display_generic_vars = make(map[int]base.Type_Var_ID, 4, store.allocator)

		display_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)

		params := make([]base.Type_Var_ID, 1, store.allocator)
		params[0] = fresh_value_var(store, base.Source_Span_ZERO)
		return_type := prelude_resolve_type_ref(store, "Str", 0, &display_generic_vars)

		append(
			&display_methods,
			Trait_Method_Info{name = to_str_name, param_types = params, return_type = return_type},
		)

		store.trait_registry[display_name] = Trait_Info {
			name    = display_name,
			module  = base.NO_NAME,
			parent  = base.NO_NAME,
			methods = display_methods[:],
		}

		delete(display_generic_vars)
	}

	// Register Display implementations for primitive types
	primitive_display_types := []struct {
		name:  string,
		canon: string,
	} {
		{"Str", "Str_to_str"},
		{"I64", "I64_to_str"},
		{"I32", "I32_to_str"},
		{"F64", "F64_to_str"},
		{"Bool", "Bool_to_str"},
	}

	for pdt in primitive_display_types {
		type_id := base.intern(store.interner, pdt.name)
		method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
		method_map[to_str_name] = base.Canonical_Name {
			module = base.NO_NAME,
			name   = base.intern(store.interner, pdt.canon),
		}
		append(
			&store.trait_impls,
			Trait_Impl {
				trait_name = display_name,
				type_name = type_id,
				type_module = base.NO_NAME,
				methods = method_map,
			},
		)
	}

	// Register Debug trait with debug: (Self) -> Str
	debug_name := base.intern(store.interner, "Debug")
	debug_method_name := base.intern(store.interner, "debug")

	if !is_trait_declared(store, debug_name) {
		debug_generic_vars: map[int]base.Type_Var_ID
		debug_generic_vars = make(map[int]base.Type_Var_ID, 4, store.allocator)

		debug_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)

		params := make([]base.Type_Var_ID, 1, store.allocator)
		params[0] = fresh_value_var(store, base.Source_Span_ZERO)
		return_type := prelude_resolve_type_ref(store, "Str", 0, &debug_generic_vars)

		append(
			&debug_methods,
			Trait_Method_Info {
				name = debug_method_name,
				param_types = params,
				return_type = return_type,
			},
		)

		store.trait_registry[debug_name] = Trait_Info {
			name    = debug_name,
			module  = base.NO_NAME,
			parent  = base.NO_NAME,
			methods = debug_methods[:],
		}

		delete(debug_generic_vars)
	}

	// Register Debug implementations for primitive types
	// Map to same runtime functions as Display.to_str
	primitive_debug_types := []struct {
		name:  string,
		canon: string,
	} {
		{"I64", "I64_debug"},
		{"I32", "I32_debug"},
		{"F64", "F64_debug"},
		{"F32", "F32_debug"},
		{"Bool", "Bool_debug"},
		{"Str", "Str_debug"},
		{"Char", "Char_debug"},
		{"Bytes", "Bytes_debug"},
		{"Unit", "Unit_debug"},
	}

	for pdt in primitive_debug_types {
		type_id := base.intern(store.interner, pdt.name)
		method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
		method_map[debug_method_name] = base.Canonical_Name {
			module = base.NO_NAME,
			name   = base.intern(store.interner, pdt.canon),
		}
		append(
			&store.trait_impls,
			Trait_Impl {
				trait_name = debug_name,
				type_name = type_id,
				type_module = base.NO_NAME,
				methods = method_map,
			},
		)
	}
	// Register Ord trait with compare: (Self, Self) -> Order
	ord_name := base.intern(store.interner, "Ord")
	compare_method_name := base.intern(store.interner, "compare")

	if !is_trait_declared(store, ord_name) {
		ord_generic_vars: map[int]base.Type_Var_ID
		ord_generic_vars = make(map[int]base.Type_Var_ID, 4, store.allocator)

		ord_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)

		params := make([]base.Type_Var_ID, 2, store.allocator)
		params[0] = fresh_value_var(store, base.Source_Span_ZERO)
		params[1] = fresh_value_var(store, base.Source_Span_ZERO)
		return_type := prelude_resolve_type_ref(store, "Order", 0, &ord_generic_vars)

		append(
			&ord_methods,
			Trait_Method_Info{name = compare_method_name, param_types = params, return_type = return_type},
		)

		store.trait_registry[ord_name] = Trait_Info {
			name    = ord_name,
			module  = base.NO_NAME,
			parent  = base.NO_NAME,
			methods = ord_methods[:],
		}

		delete(ord_generic_vars)
	}

	// Register Ord implementations for primitive types
	primitive_ord_types := []struct {
		name:  string,
		canon: string,
	} {
		{"I64", "I64_compare"},
		{"I32", "I32_compare"},
		{"I16", "I16_compare"},
		{"I8", "I8_compare"},
		{"U64", "U64_compare"},
		{"U32", "U32_compare"},
		{"U16", "U16_compare"},
		{"U8", "U8_compare"},
		{"F64", "F64_compare"},
		{"F32", "F32_compare"},
		{"Bool", "Bool_compare"},
		{"Str", "Str_compare"},
		{"Bytes", "Bytes_compare"},
		{"Char", "Char_compare"},
	}

	for pdt in primitive_ord_types {
		type_id := base.intern(store.interner, pdt.name)
		method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
		method_map[compare_method_name] = base.Canonical_Name {
			module = base.NO_NAME,
			name   = base.intern(store.interner, pdt.canon),
		}
		append(
			&store.trait_impls,
			Trait_Impl {
				trait_name = ord_name,
				type_name = type_id,
				type_module = base.NO_NAME,
				methods = method_map,
			},
		)
	}

}

package camp

import "core:fmt"

Prelude_Builtin_Type :: struct {
	name: string,
	kind: Inferred_Tag,
}

Prelude_Constructor_Type :: struct {
	name:  string,
	arity: int,
}

Prelude_Tag_Decl :: struct {
	name:        string,
	has_payload: bool,
}

PRELUDE_BUILTIN_TYPES :: []Prelude_Builtin_Type{
	{"Bool",  .Constructor},
	{"I64",   .Primitive},
	{"I32",   .Primitive},
	{"U64",   .Primitive},
	{"F64",   .Primitive},
	{"F32",   .Primitive},
	{"Str",   .Primitive},
	{"Unit",  .Primitive},
	{"I8",    .Primitive},
	{"I16",   .Primitive},
	{"U8",    .Primitive},
	{"U16",   .Primitive},
	{"U32",   .Primitive},
	{"Bytes", .Primitive},
}

PRELUDE_CONSTRUCTOR_TYPES :: []Prelude_Constructor_Type{
	{"List",     1},
	{"Iter",     1},
	{"Map",      2},
	{"Set",      1},
	{"Handle",   1},
	{"Ordering", 0},
	{"Result",   2},
	{"Option",   1},
}

PRELUDE_TAG_DECLS :: []Prelude_Tag_Decl{
	{"True",  false},
	{"False", false},
	{"Ok",    true},
	{"Err",   true},
	{"Some",  true},
	{"None",  false},
	{"Less",  false},
	{"Equal", false},
	{"Greater", false},
	{"Nil",   false},
	{"Cons",  true},
}

PRELUDE_EFFECT_FULL :: []string{"Console", "Throw", "Parallel", "Spawn", "Async"}
PRELUDE_EFFECT_FORWARD :: []string{"File", "Env", "Time", "Random", "Log", "CryptoRandom"}

is_prelude_effect :: proc(name: Intern_ID, interner: ^Intern_Table) -> bool {
	for eff in PRELUDE_EFFECT_FULL {
		if intern(interner, eff) == name {
			return true
		}
	}
	for eff in PRELUDE_EFFECT_FORWARD {
		if intern(interner, eff) == name {
			return true
		}
	}
	return false
}

prelude_resolve_type_ref :: proc(store: ^Type_Store, ref: string, generic_idx: int, generic_vars: ^map[int]Type_Var_ID) -> Type_Var_ID {
	if ref == "generic" {
		if v, ok := generic_vars^[generic_idx]; ok do return v
		v := fresh_value_var(store, Source_Span_ZERO)
		generic_vars^[generic_idx] = v
		return v
	}
	name_id := intern(store.interner, ref)
	if v, ok := store.bindings[name_id]; ok do return v
	return fresh_value_var(store, Source_Span_ZERO)
}

prelude_lower_type_ref :: proc(store: ^Type_Store, ref: string) -> IR_Type {
	if ref == "generic" {
		return IR_Type{wasm_type = .I32, type_id = 0}
	}
	name_id := intern(store.interner, ref)
	if v, ok := store.bindings[name_id]; ok {
		return lower_type(store, v)
	}
	return IR_Type{wasm_type = .I32, type_id = 0}
}

inject_prelude_effects_typecheck :: proc(store: ^Type_Store) {
	for eff_name in PRELUDE_EFFECT_FULL {
		name_id := intern(store.interner, eff_name)
		append(&store.declared_effects, name_id)

		generic_vars: map[int]Type_Var_ID
		generic_vars = make(map[int]Type_Var_ID, 4)

		ops := make([dynamic]Effect_Op_Sig, 0, 8)

		switch eff_name {
		case "Console":
			append(&ops, Effect_Op_Sig{
				name = intern(store.interner, "println!"),
				param_count = 1,
				param_types = make([]Type_Var_ID, 1),
				return_type = prelude_resolve_type_ref(store, "Unit", 0, &generic_vars),
			})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "Str", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{
				name = intern(store.interner, "readln!"),
				param_count = 0,
				param_types = make([]Type_Var_ID, 0),
				return_type = prelude_resolve_type_ref(store, "Str", 0, &generic_vars),
			})
		case "Throw":
			append(&ops, Effect_Op_Sig{
				name = intern(store.interner, "throw!"),
				param_count = 1,
				param_types = make([]Type_Var_ID, 1),
				return_type = prelude_resolve_type_ref(store, "generic", 1, &generic_vars),
			})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
		case "Parallel":
			items_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			f_type := prelude_resolve_type_ref(store, "generic", 1, &generic_vars)
			list_type := prelude_resolve_type_ref(store, "List", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "map!"), param_count = 2, param_types = make([]Type_Var_ID, 2), return_type = list_type})
			ops[len(ops)-1].param_types[0] = items_type; ops[len(ops)-1].param_types[1] = f_type
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "for_each!"), param_count = 2, param_types = make([]Type_Var_ID, 2), return_type = unit_type})
			ops[len(ops)-1].param_types[0] = items_type; ops[len(ops)-1].param_types[1] = f_type
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "filter!"), param_count = 2, param_types = make([]Type_Var_ID, 2), return_type = list_type})
			ops[len(ops)-1].param_types[0] = items_type; ops[len(ops)-1].param_types[1] = f_type
			init_type := prelude_resolve_type_ref(store, "generic", 1, &generic_vars)
			reduce_f_type := prelude_resolve_type_ref(store, "generic", 2, &generic_vars)
			reduce_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "reduce!"), param_count = 3, param_types = make([]Type_Var_ID, 3), return_type = reduce_return})
			ops[len(ops)-1].param_types[0] = items_type; ops[len(ops)-1].param_types[1] = init_type; ops[len(ops)-1].param_types[2] = reduce_f_type
			tasks_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "all!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = list_type})
			ops[len(ops)-1].param_types[0] = tasks_type
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "any!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = list_type})
			ops[len(ops)-1].param_types[0] = tasks_type
		case "Spawn":
			thunk_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			handle_type := prelude_resolve_type_ref(store, "Handle", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			join_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "spawn!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = handle_type})
			ops[len(ops)-1].param_types[0] = thunk_type
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "join!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = join_return})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "cancel!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = unit_type})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
		case "Async":
			thunk_type := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			handle_type := prelude_resolve_type_ref(store, "Handle", 0, &generic_vars)
			unit_type := prelude_resolve_type_ref(store, "Unit", 0, &generic_vars)
			join_return := prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "spawn!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = handle_type})
			ops[len(ops)-1].param_types[0] = thunk_type
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "join!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = join_return})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "yield!"), param_count = 0, param_types = make([]Type_Var_ID, 0), return_type = unit_type})
			append(&ops, Effect_Op_Sig{name = intern(store.interner, "cancel!"), param_count = 1, param_types = make([]Type_Var_ID, 1), return_type = unit_type})
			ops[len(ops)-1].param_types[0] = prelude_resolve_type_ref(store, "generic", 0, &generic_vars)
		}

		store.effect_ops[name_id] = ops[:]
		delete(generic_vars)
	}

	for eff_name in PRELUDE_EFFECT_FORWARD {
		name_id := intern(store.interner, eff_name)
		append(&store.declared_effects, name_id)
	}
}

inject_prelude_effects_lower :: proc(mod: ^IR_Module, store: ^Type_Store) {
	for eff_name in PRELUDE_EFFECT_FULL {
		eff_name_id := intern(store.interner, eff_name)
		if !is_declared_effect(store, eff_name_id) do continue

		already := false
		for eff in mod.effect_defs {
			if eff.name.name == eff_name_id {
				already = true
				break
			}
		}
		if already do continue

		ops := make([dynamic]IR_Effect_Op, 0, 8)

		switch eff_name {
		case "Console":
			append(&ops, IR_Effect_Op{
				name = intern(store.interner, "println!"),
				params = make([dynamic]IR_Param, 1),
				return_type = prelude_lower_type_ref(store, "Unit"),
			})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "msg"), type = prelude_lower_type_ref(store, "Str")}
			append(&ops, IR_Effect_Op{
				name = intern(store.interner, "readln!"),
				params = make([dynamic]IR_Param, 0),
				return_type = prelude_lower_type_ref(store, "Str"),
			})
		case "Throw":
			append(&ops, IR_Effect_Op{
				name = intern(store.interner, "throw!"),
				params = make([dynamic]IR_Param, 1),
				return_type = prelude_lower_type_ref(store, "generic"),
			})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "err"), type = prelude_lower_type_ref(store, "generic")}
		case "Parallel":
			items_type := prelude_lower_type_ref(store, "generic")
			f_type := prelude_lower_type_ref(store, "generic")
			list_type := prelude_lower_type_ref(store, "List")
			unit_type := prelude_lower_type_ref(store, "Unit")
			append(&ops, IR_Effect_Op{name = intern(store.interner, "map!"), params = make([dynamic]IR_Param, 2), return_type = list_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "items"), type = items_type}
			ops[len(ops)-1].params[1] = IR_Param{name = intern(store.interner, "f"), type = f_type}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "for_each!"), params = make([dynamic]IR_Param, 2), return_type = unit_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "items"), type = items_type}
			ops[len(ops)-1].params[1] = IR_Param{name = intern(store.interner, "f"), type = f_type}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "filter!"), params = make([dynamic]IR_Param, 2), return_type = list_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "items"), type = items_type}
			ops[len(ops)-1].params[1] = IR_Param{name = intern(store.interner, "pred"), type = f_type}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "reduce!"), params = make([dynamic]IR_Param, 3), return_type = prelude_lower_type_ref(store, "generic")})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "items"), type = items_type}
			ops[len(ops)-1].params[1] = IR_Param{name = intern(store.interner, "init"), type = prelude_lower_type_ref(store, "generic")}
			ops[len(ops)-1].params[2] = IR_Param{name = intern(store.interner, "f"), type = prelude_lower_type_ref(store, "generic")}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "all!"), params = make([dynamic]IR_Param, 1), return_type = list_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "tasks"), type = prelude_lower_type_ref(store, "generic")}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "any!"), params = make([dynamic]IR_Param, 1), return_type = list_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "tasks"), type = prelude_lower_type_ref(store, "generic")}
		case "Spawn":
			thunk_type := prelude_lower_type_ref(store, "generic")
			handle_type := prelude_lower_type_ref(store, "Handle")
			unit_type := prelude_lower_type_ref(store, "Unit")
			append(&ops, IR_Effect_Op{name = intern(store.interner, "spawn!"), params = make([dynamic]IR_Param, 1), return_type = handle_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "thunk"), type = thunk_type}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "join!"), params = make([dynamic]IR_Param, 1), return_type = prelude_lower_type_ref(store, "generic")})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "handle"), type = prelude_lower_type_ref(store, "generic")}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "cancel!"), params = make([dynamic]IR_Param, 1), return_type = unit_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "handle"), type = prelude_lower_type_ref(store, "generic")}
		case "Async":
			thunk_type := prelude_lower_type_ref(store, "generic")
			handle_type := prelude_lower_type_ref(store, "Handle")
			unit_type := prelude_lower_type_ref(store, "Unit")
			append(&ops, IR_Effect_Op{name = intern(store.interner, "spawn!"), params = make([dynamic]IR_Param, 1), return_type = handle_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "thunk"), type = thunk_type}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "join!"), params = make([dynamic]IR_Param, 1), return_type = prelude_lower_type_ref(store, "generic")})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "handle"), type = prelude_lower_type_ref(store, "generic")}
			append(&ops, IR_Effect_Op{name = intern(store.interner, "yield!"), params = make([dynamic]IR_Param, 0), return_type = unit_type})
			append(&ops, IR_Effect_Op{name = intern(store.interner, "cancel!"), params = make([dynamic]IR_Param, 1), return_type = unit_type})
			ops[len(ops)-1].params[0] = IR_Param{name = intern(store.interner, "handle"), type = prelude_lower_type_ref(store, "generic")}
		}

		append(&mod.effect_defs, IR_Effect_Def{
			name = Canonical_Name{module = NO_NAME, name = eff_name_id},
			operations = ops,
			type_params = make([dynamic]Intern_ID, 0),
		})
	}
}

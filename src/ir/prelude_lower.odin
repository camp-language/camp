package ir

import "camp:base"
import "camp:semantics"

inject_prelude_effects_lower :: proc(mod: ^IR_Module, store: ^semantics.Type_Store) {
	for eff_name in semantics.PRELUDE_EFFECT_FULL {
		eff_name_id := base.intern(store.interner, eff_name)
		if !semantics.is_declared_effect(store, eff_name_id) do continue

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
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "println!"),
					params = make([dynamic]IR_Param, 1),
					return_type = semantics.prelude_lower_type_ref(store, "Unit"),
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "msg"),
				type = semantics.prelude_lower_type_ref(store, "Str"),
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "readln!"),
					params = make([dynamic]IR_Param, 0),
					return_type = semantics.prelude_lower_type_ref(store, "Str"),
				},
			)
		case "Throw":
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "throw!"),
					params = make([dynamic]IR_Param, 1),
					return_type = semantics.prelude_lower_type_ref(store, "generic"),
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "err"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
		case "Parallel":
			items_type := semantics.prelude_lower_type_ref(store, "generic")
			f_type := semantics.prelude_lower_type_ref(store, "generic")
			list_type := semantics.prelude_lower_type_ref(store, "List")
			unit_type := semantics.prelude_lower_type_ref(store, "Unit")
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "map!"),
					params = make([dynamic]IR_Param, 2),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "items"),
				type = items_type,
			}
			ops[len(ops) - 1].params[1] = IR_Param {
				name = base.intern(store.interner, "f"),
				type = f_type,
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "for_each!"),
					params = make([dynamic]IR_Param, 2),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "items"),
				type = items_type,
			}
			ops[len(ops) - 1].params[1] = IR_Param {
				name = base.intern(store.interner, "f"),
				type = f_type,
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "filter!"),
					params = make([dynamic]IR_Param, 2),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "items"),
				type = items_type,
			}
			ops[len(ops) - 1].params[1] = IR_Param {
				name = base.intern(store.interner, "pred"),
				type = f_type,
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "reduce!"),
					params = make([dynamic]IR_Param, 3),
					return_type = semantics.prelude_lower_type_ref(store, "generic"),
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "items"),
				type = items_type,
			}
			ops[len(ops) - 1].params[1] = IR_Param {
				name = base.intern(store.interner, "init"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
			ops[len(ops) - 1].params[2] = IR_Param {
				name = base.intern(store.interner, "f"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "all!"),
					params = make([dynamic]IR_Param, 1),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "tasks"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "any!"),
					params = make([dynamic]IR_Param, 1),
					return_type = list_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "tasks"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
		case "Spawn":
			thunk_type := semantics.prelude_lower_type_ref(store, "generic")
			handle_type := semantics.prelude_lower_type_ref(store, "Handle")
			unit_type := semantics.prelude_lower_type_ref(store, "Unit")
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "spawn!"),
					params = make([dynamic]IR_Param, 1),
					return_type = handle_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "thunk"),
				type = thunk_type,
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "join!"),
					params = make([dynamic]IR_Param, 1),
					return_type = semantics.prelude_lower_type_ref(store, "generic"),
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "handle"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "cancel!"),
					params = make([dynamic]IR_Param, 1),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "handle"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
		case "Async":
			thunk_type := semantics.prelude_lower_type_ref(store, "generic")
			handle_type := semantics.prelude_lower_type_ref(store, "Handle")
			unit_type := semantics.prelude_lower_type_ref(store, "Unit")
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "spawn!"),
					params = make([dynamic]IR_Param, 1),
					return_type = handle_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "thunk"),
				type = thunk_type,
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "join!"),
					params = make([dynamic]IR_Param, 1),
					return_type = semantics.prelude_lower_type_ref(store, "generic"),
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "handle"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "yield!"),
					params = make([dynamic]IR_Param, 0),
					return_type = unit_type,
				},
			)
			append(
				&ops,
				IR_Effect_Op {
					name = base.intern(store.interner, "cancel!"),
					params = make([dynamic]IR_Param, 1),
					return_type = unit_type,
				},
			)
			ops[len(ops) - 1].params[0] = IR_Param {
				name = base.intern(store.interner, "handle"),
				type = semantics.prelude_lower_type_ref(store, "generic"),
			}
		}

		append(
			&mod.effect_defs,
			IR_Effect_Def {
				name = base.Canonical_Name{module = base.NO_NAME, name = eff_name_id},
				operations = ops,
				type_params = make([dynamic]base.Intern_ID, 0),
			},
		)
	}
}


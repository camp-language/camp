package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:semantics"
import "core:testing"

@(test)
test_prelude_builtin_types :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	for bt in semantics.PRELUDE_BUILTIN_TYPES {
		name_id := base.intern(&ctx.interner, bt.name)
		_, ok := store.bindings[name_id]
		testing.expectf(t, ok, "Builtin type %q not injected into store.bindings", bt.name)
	}
}

@(test)
test_prelude_constructor_types :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	for ct in semantics.PRELUDE_CONSTRUCTOR_TYPES {
		name_id := base.intern(&ctx.interner, ct.name)
		_, ok := store.bindings[name_id]
		testing.expectf(t, ok, "Constructor type %q not injected into store.bindings", ct.name)
	}
}

@(test)
test_prelude_tag_decls :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	for td in semantics.PRELUDE_TAG_DECLS {
		name_id := base.intern(&ctx.interner, td.name)
		_, ok := store.bindings[name_id]
		testing.expectf(t, ok, "Tag decl %q not injected into store.bindings", td.name)
	}
}

@(test)
test_prelude_is_prelude_effect :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	for eff in semantics.PRELUDE_EFFECT_FULL {
		name_id := base.intern(&ctx.interner, eff)
		ok := semantics.is_prelude_effect(name_id, &ctx.interner)
		testing.expectf(t, ok, "is_prelude_effect(%q) should return true", eff)
	}

	for eff in semantics.PRELUDE_EFFECT_FORWARD {
		name_id := base.intern(&ctx.interner, eff)
		ok := semantics.is_prelude_effect(name_id, &ctx.interner)
		testing.expectf(t, ok, "is_prelude_effect(%q) should return true", eff)
	}

	unknowns := []string{"Foo", "Bar", "Baz", "NotAnEffect"}
	for name in unknowns {
		name_id := base.intern(&ctx.interner, name)
		ok := semantics.is_prelude_effect(name_id, &ctx.interner)
		testing.expectf(t, !ok, "is_prelude_effect(%q) should return false", name)
	}
}

@(test)
test_prelude_full_effects_declared :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	for eff in semantics.PRELUDE_EFFECT_FULL {
		name_id := base.intern(&ctx.interner, eff)
		found := false
		for declared in store.declared_effects {
			if declared == name_id {
				found = true
				break
			}
		}
		testing.expectf(t, found, "Full effect %q should be in store.declared_effects", eff)
	}
}

@(test)
test_prelude_full_effects_have_ops :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	for eff in semantics.PRELUDE_EFFECT_FULL {
		name_id := base.intern(&ctx.interner, eff)
		ops, has_ops := store.effect_ops[name_id]
		testing.expectf(t, has_ops, "Full effect %q should have effect_ops entry", eff)
		testing.expectf(t, len(ops) > 0, "Full effect %q should have at least one operation", eff)
	}

	for eff in semantics.PRELUDE_EFFECT_FORWARD {
		name_id := base.intern(&ctx.interner, eff)
		_, has_ops := store.effect_ops[name_id]
		testing.expectf(t, !has_ops, "Forwarded effect %q should NOT have effect_ops entry", eff)
	}
}

@(test)
test_prelude_inject_twice_idempotent :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)

	first_count := len(store.bindings)
	first_bindings := make(map[base.Intern_ID]base.Type_Var_ID)
	defer delete(first_bindings)
	for k, v in store.bindings {
		first_bindings[k] = v
	}

	semantics.inject_prelude(&store)

	second_count := len(store.bindings)
	testing.expectf(
		t,
		second_count == first_count,
		"Binding count changed on second inject: %d -> %d",
		first_count,
		second_count,
	)

	expected_total :=
		len(semantics.PRELUDE_BUILTIN_TYPES) +
		len(semantics.PRELUDE_CONSTRUCTOR_TYPES) +
		len(semantics.PRELUDE_TAG_DECLS) +
		1 // Order tag-union binding (registered explicitly, not via PRELUDE_CONSTRUCTOR_TYPES)
	testing.expectf(
		t,
		second_count == expected_total,
		"Expected %d total prelude bindings, got %d",
		expected_total,
		second_count,
	)

	for k, v in first_bindings {
		v2, ok := store.bindings[k]
		name := base.intern_get(&ctx.interner, k)
		testing.expectf(t, ok, "Binding %q disappeared after second inject", name)
		if ok {
			testing.expectf(
				t,
				v != v2,
				"Binding %q should get fresh Type_Var_ID on second inject (identity warning)",
				name,
			)
		}
	}
}


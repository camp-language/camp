package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:testing"

// Match on Bool with both True and False arms — must be exhaustive, no errors
@(test)
test_match_bool_all_cases :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match True {\n    True => 1\n    False => 2\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match on Bool with only True arm — must report non-exhaustive error
@(test)
test_match_bool_missing_case :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match True { True => 1 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match on prelude tag union Ok/Err with both branches — no errors
@(test)
test_match_tag_union_exhaustive :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"x : [Ok(I64) | Err(I64)] = Ok(42)\nval = match x {\n    Ok(v) => v\n    Err(_) => 0\n}",
		{with_prelude = true},
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match on int literal with exact match and wildcard — no errors
@(test)
test_match_int_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match 42 {\n    42 => 1\n    _ => 0\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match with identifier pattern binding — binds matched value, no errors
@(test)
test_match_binding :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match 42 { x => x }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match on string literal with exact match and wildcard — no errors
@(test)
test_match_string :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match \"hello\" {\n    \"hello\" => 1\n    _ => 0\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Match with only wildcard — always exhaustive, no errors
@(test)
test_match_wildcard :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match 42 { _ => 1 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Redundant Bool arm after same literal already covered — warning but no error
@(test)
test_match_redundant_pattern :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match True {\n    True => 1\n    True => 2\n    False => 0\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	// Redundant pattern is a Warning, not an Error — no errors expected
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

// If condition with non-Bool expression — must report type error
@(test)
test_if_condition_not_bool :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = if 42 { 1 } else { 2 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

// Or-pattern with alternatives and wildcard — no errors
@(test)
test_match_or_pattern :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match 1 {\n    1 | 2 => 0\n    _ => 1\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

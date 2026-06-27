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
	store, _ := setup_for_typecheck(
		&ctx,
		"val = match \"hello\" {\n    \"hello\" => 1\n    _ => 0\n}",
	)
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
	store, _ := setup_for_typecheck(
		&ctx,
		"val = match True {\n    True => 1\n    True => 2\n    False => 0\n}",
	)
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

// helper: does the collector have a diagnostic with the given code?
has_diag_code :: proc(collector: ^diagnostics.Diagnostic_Collector, code: string) -> bool {
	for d in collector.diagnostics {
		if d.code == code do return true
	}
	return false
}

// C0502: matching a closed anonymous tag union without covering every
// variant is a non-exhaustive-match error.
@(test)
test_match_non_exhaustive_tag_union :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"x : [Ok(I64) | Err(I64)] = Ok(1)\nval = match x { Ok(v) => v }",
		{with_prelude = true},
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0502"))
}

// C0502: missing branch on a user newtype-owned tag union surfaces the
// newtype name.
@(test)
test_match_non_exhaustive_newtype :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"@Color : pub [Red | Green | Blue]\nc : Color = Red\nval = match c {\n    Red => 1\n    Green => 2\n}",
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0502"))
}

// C0504: exhaustive match on a multi-variant newtype without a wildcard is
// a fragile-match warning.
@(test)
test_match_fragile_newtype :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"@Color : pub [Red | Green | Blue]\nc : Color = Red\nval = match c {\n    Red => 1\n    Green => 2\n    Blue => 3\n}",
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, has_diag_code(&ctx.collector, "C0504"))
}

// C0504: adding a wildcard silences fragile-match.
@(test)
test_match_fragile_silenced_by_wildcard :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"@Color : pub [Red | Green | Blue]\nc : Color = Red\nval = match c {\n    Red => 1\n    Green => 2\n    Blue => 3\n    _ => 4\n}",
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !has_diag_code(&ctx.collector, "C0504"))
}

// C0506: closed record pattern missing a declared field is an error.
@(test)
test_match_missing_field_pattern :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match { x: 1, y: 2 } {\n    { x: a } => a\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0506"))
}

// C0507: record pattern naming a field absent from the record type.
@(test)
test_match_unknown_field_pattern :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"val = match { x: 1, y: 2 } {\n    { x: a, z: b } => a + b\n}",
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0507"))
}

// C0506: open record pattern (`{ .. }`) ignores remaining fields → no error.
@(test)
test_match_open_record_no_missing_field :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match { x: 1, y: 2 } {\n    { x: a, .. } => a\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !has_diag_code(&ctx.collector, "C0506"))
}

// C0508: a name bound twice in the same pattern is a duplicate-binding error.
@(test)
test_match_duplicate_binding :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"val = match { x: 1, y: 2 } {\n    { x: a, y: a } => a\n}",
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0508"))
}

// C0509: a second wildcard arm after an earlier catch-all is a
// wildcard-after-catch-all warning.
@(test)
test_match_wildcard_after_catch_all :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = match 5 {\n    _ => 1\n    _ => 2\n}")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, has_diag_code(&ctx.collector, "C0509"))
}


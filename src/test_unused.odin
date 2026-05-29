package camp

import "camp:analysis"
import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:fmt"
import "core:strings"
import "core:testing"

// setup_for_unused runs parse -> canonicalize -> typecheck and returns
// store, tfile, and cfile for use by unused analysis.
setup_for_unused :: proc(
	ctx: ^build.Compilation_Context,
	source: string,
) -> (
	store: ^semantics.Type_Store,
	tfile: semantics.TFile,
	cfile: semantics.CFile,
) {
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File {
		path     = "<unused-test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	cfile = semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store = new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	tfile = semantics.typecheck_file(cfile, store)
	semantics.check_effect_safety(tfile, store)
	return store, tfile, cfile
}

// has_unused_binding checks for "UNUSED BINDING" diagnostic mentioning name.
has_unused_binding :: proc(collector: ^diagnostics.Diagnostic_Collector, name: string) -> bool {
	for diag in collector.diagnostics {
		if diag.title != "UNUSED BINDING" do continue
		expected := fmt.tprintf("Binding `%s`", name)
		if strings.contains(diag.message, expected) do return true
	}
	return false
}

// count_unused_bindings returns total "UNUSED BINDING" diagnostics.
count_unused_bindings :: proc(collector: ^diagnostics.Diagnostic_Collector) -> int {
	count := 0
	for diag in collector.diagnostics {
		if diag.title == "UNUSED BINDING" do count += 1
	}
	return count
}

@(test)
test_unused_used_function_param :: proc(t: ^testing.T) {
	// Function parameters `x` and `y` are both used in body — no warning.
	// `add` is top-level unused — warning expected.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "add = |x, y| x + y")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, !has_unused_binding(&ctx.collector, "x"),
		"Expected no unused warning for param 'x' (used in body)")
	testing.expectf(t, !has_unused_binding(&ctx.collector, "y"),
		"Expected no unused warning for param 'y' (used in body)")
	testing.expectf(t, has_unused_binding(&ctx.collector, "add"),
		"Expected unused warning for top-level 'add'")
}

@(test)
test_unused_unused_function_param :: proc(t: ^testing.T) {
	// Param `x` unused in body — warning expected.
	// `f` is top-level unused — warning expected.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "f = |x| 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, has_unused_binding(&ctx.collector, "x"),
		"Expected unused warning for param 'x' (unused in body)")
}

@(test)
test_unused_top_level_binding :: proc(t: ^testing.T) {
	// Top-level `x = 42` not referenced — warning expected.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, has_unused_binding(&ctx.collector, "x"),
		"Expected unused warning for top-level 'x'")
	testing.expectf(t, count_unused_bindings(&ctx.collector) == 1,
		"Expected exactly 1 unused binding warning, got %d", count_unused_bindings(&ctx.collector))
}

@(test)
test_unused_underscore_suppresses_warning :: proc(t: ^testing.T) {
	// `_x` is underscore-prefixed — no warning suppressed.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "_x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, !has_unused_binding(&ctx.collector, "_x"),
		"Expected no unused warning for '_x' (underscore prefix)")
	testing.expectf(t, count_unused_bindings(&ctx.collector) == 0,
		"Expected 0 unused binding warnings, got %d", count_unused_bindings(&ctx.collector))
}

@(test)
test_unused_public_binding_no_warning :: proc(t: ^testing.T) {
	// `pub x = 42` is public — no warning (public top-level is exempt).
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "pub x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, !has_unused_binding(&ctx.collector, "x"),
		"Expected no unused warning for 'pub x'")
	testing.expectf(t, count_unused_bindings(&ctx.collector) == 0,
		"Expected 0 unused binding warnings, got %d", count_unused_bindings(&ctx.collector))
}

@(test)
test_unused_local_binding_in_block :: proc(t: ^testing.T) {
	// Local `z = 42` used by `z + 1` as final expression — no warning.
	// `f` is top-level unused — warning expected.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "f = || { z = 42\nz + 1 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, !has_unused_binding(&ctx.collector, "z"),
		"Expected no unused warning for 'z' (used in block)")
}

@(test)
test_unused_local_unused_in_block :: proc(t: ^testing.T) {
	// Local `z = 42` not used — warning expected.
	// `f` is top-level unused — warning expected.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "f = || { z = 42\n42 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, has_unused_binding(&ctx.collector, "z"),
		"Expected unused warning for 'z' (unused in block)")
}

@(test)
test_unused_mixed_used_and_unused :: proc(t: ^testing.T) {
	// Top-level `x` used by `y`'s body — no warning.
	// Top-level `y` unused — warning.
	// Top-level `z` unused — warning.
	ctx: build.Compilation_Context
	store, tfile, cfile := setup_for_unused(&ctx, "x = 42\ny = x + 1\nz = 3")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	analysis.run_unused_analysis(cfile, &ctx.interner, &ctx.collector)

	testing.expectf(t, !has_unused_binding(&ctx.collector, "x"),
		"Expected no unused warning for 'x' (used by 'y')")
	testing.expectf(t, has_unused_binding(&ctx.collector, "y"),
		"Expected unused warning for 'y' (not used)")
	testing.expectf(t, has_unused_binding(&ctx.collector, "z"),
		"Expected unused warning for 'z' (not used)")
}

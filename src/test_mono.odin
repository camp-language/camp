package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:mono"
import "camp:semantics"
import "core:testing"

@(test)
test_mono_annotate_preserves_type_info :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("x = 42\ny = x + 1")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 2)

	for decl in annot_tfile.decls {
		if d, ok := decl.(^semantics.TDecl_Const); ok {
			testing.expect(t, d.type_.wasm_type != {})
		}
	}
}

@(test)
test_mono_annotate_expr_preserves_span :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("val = 42")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
	if d, ok := annot_tfile.decls[0].(^semantics.TDecl_Const); ok {
		testing.expect(t, d.span.file_id == 0)
		testing.expect(t, d.span.start >= 0)
	}
}

@(test)
test_mono_annotate_list_expr :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("l = [1, 2, 3]")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_let_binding :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("r = 1")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_binop_expr :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("result = 1 + 2")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_simple_binding :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("x = 5")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_substitute_ir_type_noop :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("x = 42")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mono_tfile := mono.mono(annot_tfile, store, &ctx.interner)

	testing.expect(t, len(mono_tfile.decls) > 0)

	for decl in mono_tfile.decls {
		if d, ok := decl.(^semantics.TDecl_Const); ok {
			testing.expect(t, d.type_.wasm_type != {})
			testing.expect(t, d.type_.type_id != base.Type_Var_ID(-1))
		}
	}
}

@(test)
test_mono_annotate_if_expr :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("val = if True { 1 } else { 0 }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_block_expr :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("val = { x = 1\nx + 2 }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_value_binding :: proc(t: ^testing.T) {
	store, ctx, annot_tfile := setup_for_typecheck("val = 1")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))


	testing.expect(t, len(annot_tfile.decls) == 1)
}


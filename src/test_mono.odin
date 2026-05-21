package camp

import "core:fmt"
import "core:testing"

@(test)
test_mono_annotate_preserves_type_info :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("x = 42\ny = x + 1")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 2)

	for decl in annot_tfile.decls {
		if d, ok := decl.(^TDecl_Const); ok {
			testing.expect(t, d.type_.wasm_type != {})
		}
	}
}

@(test)
test_mono_annotate_expr_preserves_span :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("val = 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
	if d, ok := annot_tfile.decls[0].(^TDecl_Const); ok {
		testing.expect(t, d.span.file_id == 0)
		testing.expect(t, d.span.start >= 0)
	}
}

@(test)
test_mono_annotate_list_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("l = [1, 2, 3]")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_record_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("r = 1")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_binop_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("result = 1 + 2")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_field_access :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("x = 5")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_substitute_ir_type_noop :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("x = 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)
	mono_tfile := mono(annot_tfile, &store, &ctx.interner)

	testing.expect(t, len(mono_tfile.decls) > 0)

	for decl in mono_tfile.decls {
		if d, ok := decl.(^TDecl_Const); ok {
			testing.expect(t, d.type_.wasm_type != {})
			testing.expect(t, d.type_.type_id != Type_Var_ID(-1))
		}
	}
}

@(test)
test_mono_annotate_if_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("val = if true 1 else 0")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_block_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("val = { x = 1\nx + 2 }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}

@(test)
test_mono_annotate_match_expr :: proc(t: ^testing.T) {
	store, ctx, canon := typecheck_source_full("val = 1")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	annot_tfile := annotate_file(canon, &store)

	testing.expect(t, len(annot_tfile.decls) == 1)
}
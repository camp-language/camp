package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:testing"

@(test)
test_check_decl_const_int :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_check_decl_lambda_pure :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "add = |x, y| x + y")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(tfile.decls) == 1, "expected 1 decl")

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Const:
		_, is_lambda := decl.body.(^semantics.TExpr_Lambda)
		testing.expect(t, is_lambda, "body should be TExpr_Lambda")
	case:
		testing.expect(t, false, "expected TDecl_Const")
	}
}

@(test)
test_check_decl_effectful_fn :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, `crashFn! = || crash "bye"`)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Const:
		testing.expect(t, decl.is_effectful, "effectful fn should have is_effectful true")
	case:
		testing.expect(t, false, "expected TDecl_Const")
	}
}

@(test)
test_check_decl_pub_const :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "pub x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Const:
		testing.expect(t, decl.is_pub, "pub const should have is_pub true")
	case:
		testing.expect(t, false, "expected TDecl_Const")
	}
}

@(test)
test_check_decl_type_annotation_ok :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "x: I64 = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_check_decl_type_annotation_error :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "x: I64 = True")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector), "I64 vs Bool should error")
}

@(test)
test_check_decl_effect :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "TestEff! : { op: || -> I64 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Effect:
		testing.expect(t, len(decl.operations) == 1, "effect should have 1 operation")
		op_name := base.intern(&ctx.interner, "op")
		testing.expect(t, decl.operations[0].name == op_name, "operation should be named 'op'")
	case:
		testing.expect(t, false, "expected TDecl_Effect")
	}
}

@(test)
test_check_decl_newtype_tag_union :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "@Option(a) : [None | Some(a)]")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Newtype:
		testing.expect(t, len(decl.type_params) == 1, "Option should have 1 type param")
	case:
		testing.expect(t, false, "expected TDecl_Newtype")
	}
}

@(test)
test_check_decl_newtype_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "@Age : I64")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	#partial switch decl in tfile.decls[0] {
	case ^semantics.TDecl_Newtype:
		testing.expect(t, len(decl.type_params) == 0, "Age should have 0 type params")
		age_name := base.intern(&ctx.interner, "Age")
		testing.expect(t, decl.name.name == age_name, "newtype name should be Age")
	case:
		testing.expect(t, false, "expected TDecl_Newtype")
	}
}

@(test)
test_check_decl_recursive_fn :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "fact = |n| if n == 0 { 1 } else { n * fact(n - 1) }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector), "recursive fn should typecheck")
}

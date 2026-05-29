package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:testing"

// Helper: find first const decl matching name, return its body TExpr.
find_const_body :: proc(
	tfile: semantics.TFile,
	name: base.Intern_ID,
) -> (
	body: semantics.TExpr,
	ok: bool,
) {
	for decl in tfile.decls {
		d, is_const := decl.(^semantics.TDecl_Const)
		if is_const && d.name.name == name {
			return d.body, true
		}
	}
	return nil, false
}

@(test)
test_check_expr_int_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "x = 42")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	x_name := base.intern(&ctx.interner, "x")
	body, found := find_const_body(tfile, x_name)
	testing.expect(t, found, "decl 'x' should exist")

	int_expr, is_int := body.(^semantics.TExpr_Int)
	testing.expect(t, is_int, "body should be TExpr_Int")
	if is_int {
		testing.expect(t, int_expr.value == 42, "int literal value should be 42")
	}
}

@(test)
test_check_expr_string_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, `x = "hello"`)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	x_name := base.intern(&ctx.interner, "x")
	body, found := find_const_body(tfile, x_name)
	testing.expect(t, found, "decl 'x' should exist")

	_, is_str := body.(^semantics.TExpr_String)
	testing.expect(t, is_str, "body should be TExpr_String")
}

@(test)
test_check_expr_lambda_identity :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "id = |x| x")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	id_name := base.intern(&ctx.interner, "id")
	body, found := find_const_body(tfile, id_name)
	testing.expect(t, found, "decl 'id' should exist")

	lam, is_lam := body.(^semantics.TExpr_Lambda)
	testing.expect(t, is_lam, "body should be TExpr_Lambda")
	if is_lam {
		testing.expect(t, len(lam.params) == 1, "lambda should have 1 param")
		testing.expect(t, lam.body != nil, "lambda body should not be nil")
	}
}

@(test)
test_check_expr_lambda_typed_params :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "add = |x: I64, y: I64| x + y")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	add_name := base.intern(&ctx.interner, "add")
	body, found := find_const_body(tfile, add_name)
	testing.expect(t, found, "decl 'add' should exist")

	lam, is_lam := body.(^semantics.TExpr_Lambda)
	testing.expect(t, is_lam, "body should be TExpr_Lambda")
	if is_lam {
		testing.expect(t, len(lam.params) == 2, "lambda should have 2 params")
	}
}

@(test)
test_check_expr_call :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "id = |x| x\ny = id(42)")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	y_name := base.intern(&ctx.interner, "y")
	body, found := find_const_body(tfile, y_name)
	testing.expect(t, found, "decl 'y' should exist")

	call, is_call := body.(^semantics.TExpr_Call)
	testing.expect(t, is_call, "y's body should be TExpr_Call")
	if is_call {
		testing.expect(t, len(call.args) == 1, "call should have 1 arg")

		_, callee_is_name := call.callee.(^semantics.TExpr_Name)
		testing.expect(t, callee_is_name, "callee should be TExpr_Name")
	}
}

@(test)
test_check_expr_if_same_type :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "val = if True { 1 } else { 2 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	val_name := base.intern(&ctx.interner, "val")
	body, found := find_const_body(tfile, val_name)
	testing.expect(t, found, "decl 'val' should exist")

	if_expr, is_if := body.(^semantics.TExpr_If)
	testing.expect(t, is_if, "body should be TExpr_If")
	if is_if {
		_, cond_is_bool := if_expr.condition.(^semantics.TExpr_Bool)
		testing.expect(t, cond_is_bool, "condition should be TExpr_Bool")

		// If branches are blocks: { 1 } and { 2 }
		then_block, then_is_block := if_expr.then_branch.(^semantics.TExpr_Block)
		testing.expect(t, then_is_block, "then branch should be TExpr_Block")
		if then_is_block {
			testing.expect(
				t,
				len(then_block.statements) == 1,
				"then block should have 1 statement",
			)
			_, inner_is_int := then_block.statements[0].(^semantics.TExpr_Int)
			testing.expect(t, inner_is_int, "then block statement should be TExpr_Int")
		}

		else_block, else_is_block := if_expr.else_branch.(^semantics.TExpr_Block)
		testing.expect(t, else_is_block, "else branch should be TExpr_Block")
		if else_is_block {
			testing.expect(
				t,
				len(else_block.statements) == 1,
				"else block should have 1 statement",
			)
			_, inner_is_int := else_block.statements[0].(^semantics.TExpr_Int)
			testing.expect(t, inner_is_int, "else block statement should be TExpr_Int")
		}
	}
}

@(test)
test_check_expr_if_type_mismatch :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "val = if True { 1 } else { True }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	// I64 vs Bool mismatch inside the branches -> should produce an error
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_check_expr_block :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "val = { 42 }")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	val_name := base.intern(&ctx.interner, "val")
	body, found := find_const_body(tfile, val_name)
	testing.expect(t, found, "decl 'val' should exist")

	block, is_block := body.(^semantics.TExpr_Block)
	testing.expect(t, is_block, "body should be TExpr_Block")
	if is_block {
		testing.expect(t, len(block.statements) == 1, "block should have 1 statement")

		_, inner_is_int := block.statements[0].(^semantics.TExpr_Int)
		testing.expect(t, inner_is_int, "block statement should be TExpr_Int")
	}
}

@(test)
test_check_expr_binary_op :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "x = 1 + 2")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	x_name := base.intern(&ctx.interner, "x")
	body, found := find_const_body(tfile, x_name)
	testing.expect(t, found, "decl 'x' should exist")

	binop, is_binop := body.(^semantics.TExpr_BinOp)
	testing.expect(t, is_binop, "body should be TExpr_BinOp")
	if is_binop {
		testing.expect(t, binop.op == .Plus, "binary op should be Plus")

		_, left_is_int := binop.left.(^semantics.TExpr_Int)
		testing.expect(t, left_is_int, "left operand should be TExpr_Int")

		_, right_is_int := binop.right.(^semantics.TExpr_Int)
		testing.expect(t, right_is_int, "right operand should be TExpr_Int")
	}
}

@(test)
test_check_expr_binary_op_type_mismatch :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(&ctx, "x = 1 + True")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	// I64 + Bool -> type mismatch error
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_check_expr_not_operator :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "x = not True")
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	x_name := base.intern(&ctx.interner, "x")
	body, found := find_const_body(tfile, x_name)
	testing.expect(t, found, "decl 'x' should exist")

	prefix, is_prefix := body.(^semantics.TExpr_PrefixOp)
	testing.expect(t, is_prefix, "body should be TExpr_PrefixOp")
	if is_prefix {
		testing.expect(t, prefix.op == .Kw_Not, "prefix op should be Kw_Not")

		_, operand_is_bool := prefix.operand.(^semantics.TExpr_Bool)
		testing.expect(t, operand_is_bool, "operand should be TExpr_Bool")
	}
}

@(test)
test_check_expr_tag_with_prelude :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, "x = Ok(42)", {with_prelude = true})
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	x_name := base.intern(&ctx.interner, "x")
	body, found := find_const_body(tfile, x_name)
	testing.expect(t, found, "decl 'x' should exist")

	// Ok(42) with prelude may be TExpr_Tag or TExpr_Nominal_Construct
	// Use #partial switch to avoid panic on non-matching type assertion
	is_valid_tag := false
	#partial switch v in body {
	case ^semantics.TExpr_Nominal_Construct:
		is_valid_tag = true
		testing.expect(t, len(v.payload) == 1, "nominal construct should have 1 payload")
	case ^semantics.TExpr_Tag:
		is_valid_tag = true
		testing.expect(t, len(v.payload) == 1, "tag should have 1 payload")
	}
	testing.expect(t, is_valid_tag, "body should be TExpr_Nominal_Construct or TExpr_Tag")
}

@(test)
test_check_expr_record_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(&ctx, `r = { name: "Camp", age: 1 }`)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	r_name := base.intern(&ctx.interner, "r")
	body, found := find_const_body(tfile, r_name)
	testing.expect(t, found, "decl 'r' should exist")

	rec, is_rec := body.(^semantics.TExpr_Record)
	testing.expect(t, is_rec, "body should be TExpr_Record")
	if is_rec {
		testing.expect(t, len(rec.fields) == 2, "record should have 2 fields")

		name_id := base.intern(&ctx.interner, "name")
		age_id := base.intern(&ctx.interner, "age")

		has_name := rec.fields[0].name == name_id || rec.fields[1].name == name_id
		has_age := rec.fields[0].name == age_id || rec.fields[1].name == age_id
		testing.expect(t, has_name, "record should have 'name' field")
		testing.expect(t, has_age, "record should have 'age' field")
	}
}

@(test)
test_check_expr_effectful_naming_error :: proc(t: ^testing.T) {
	// Define an effect and call it from a function whose name doesn't end with !
	ctx: build.Compilation_Context
	store, _ := setup_for_typecheck(
		&ctx,
		"E! : { do_it!: || -> {} }\nf = || { E!.do_it!() }",
		{with_prelude = true},
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_check_expr_effectful_name_ok :: proc(t: ^testing.T) {
	// Function with ! suffix performing effects -> OK
	ctx: build.Compilation_Context
	store, tfile := setup_for_typecheck(
		&ctx,
		"E! : { do_it!: || -> {} }\nf! = || { E!.do_it!() }",
		{with_prelude = true},
	)
	defer build.context_destroy(&ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	f_name := base.intern(&ctx.interner, "f!")
	body, found := find_const_body(tfile, f_name)
	testing.expect(t, found, "decl 'f!' should exist")

	_, is_lam := body.(^semantics.TExpr_Lambda)
	testing.expect(t, is_lam, "body should be TExpr_Lambda")
}


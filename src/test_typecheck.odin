package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:mono"
import "camp:semantics"
import "core:fmt"
import "core:testing"

setup_type_store :: proc() -> (semantics.Type_Store, ^diagnostics.Diagnostic_Collector) {
	store: semantics.Type_Store
	collector: ^diagnostics.Diagnostic_Collector = new(diagnostics.Diagnostic_Collector)
	diagnostics.diag_collector_init(collector)
	intern_table: ^base.Intern_Table = new(base.Intern_Table)
	base.intern_init(intern_table)
	semantics.type_store_init(&store, intern_table, collector)
	return store, collector
}

teardown_type_store :: proc(
	store: ^semantics.Type_Store,
	collector: ^diagnostics.Diagnostic_Collector,
) {
	base.intern_destroy(store.interner)
	free(store.interner)
	semantics.type_store_destroy(store)
	diagnostics.diag_collector_destroy(collector)
	free(collector)
}

@(test)
test_unify_fresh_vars :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)

	ok := semantics.unify(&store, a, b)
	testing.expect(t, ok)

	resolved_a := semantics.resolve_var(&store, a)
	resolved_b := semantics.resolve_var(&store, b)
	testing.expect(t, resolved_a == resolved_b)
}

@(test)
test_unify_level_propagation :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	semantics.enter_level(&store)
	a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.exit_level(&store)

	b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)

	ok := semantics.unify(&store, a, b)
	testing.expect(t, ok)

	va := store.vars[int(semantics.resolve_var(&store, a))]
	vb := store.vars[int(semantics.resolve_var(&store, b))]
	max_level := max(va.level, vb.level)
	testing.expect(t, va.level == max_level)
	testing.expect(t, vb.level == max_level)
}

@(test)
test_generalize_at_level :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	semantics.enter_level(&store)
	a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	level := store.current_level
	semantics.exit_level(&store)

	testing.expect(t, !semantics.is_generic(&store, a))
	semantics.generalize_at_level(&store, level)
	testing.expect(t, semantics.is_generic(&store, a))
}

@(test)
test_unify_primitive_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	str_name := base.intern(store.interner, "Str")

	a := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	b := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)

	ok := semantics.unify(&store, a, b)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(collector))
}

@(test)
test_unify_same_primitive :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")

	a := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	b := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)

	ok := semantics.unify(&store, a, b)
	testing.expect(t, ok)
}

Test_Options :: struct {
	with_prelude: bool,
}

setup_for_typecheck :: proc(
	source: string,
	opts: Test_Options = {},
) -> (
	store: ^semantics.Type_Store,
	ctx: ^build.Compilation_Context,
	tfile: semantics.TFile,
) {
	ctx = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File {
		path     = "<tc-test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store = new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	if opts.with_prelude {
		semantics.inject_prelude(store)
	}
	tfile = semantics.typecheck_file(canon, store)
	return store, ctx, tfile
}

typecheck_into_store :: proc(
	source: string,
	store: ^semantics.Type_Store,
	ctx: ^build.Compilation_Context,
	module_id: base.Intern_ID = base.NO_NAME,
) -> semantics.TFile {
	file := base.Source_File {
		path     = "<tc-test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)
	return semantics.typecheck_file(canon, store, module_id)
}

@(test)
test_typecheck_int_literal :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("x = 42")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_lambda :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("add = |x| x")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_if_same_type :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("val = if True { 1 } else { 2 }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_record :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("r = { name: \"Camp\", age: 1 }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_undefined_name :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("x = undefined_var")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_let_polymorphism :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("id = |x| x\na = id(1)\nb = id(True)")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_annotation_check :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("x = 42")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_binop :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("x = 1 + 2\ny = True and False")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_not :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("x = not True")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_unify_function_same_arity :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	str_name := base.intern(store.interner, "Str")

	param_a := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_a := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	eff_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	params_a := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_a[0] = param_a
	fn_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_a,
		semantics.Inferred_Function{param_ids = params_a, return_id = ret_a, effect_id = eff_a},
	)

	param_b := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_b := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_b[0] = param_b
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_b,
		semantics.Inferred_Function{param_ids = params_b, return_id = ret_b, effect_id = eff_b},
	)

	ok := semantics.unify(&store, fn_a, fn_b)
	testing.expect(t, ok)
}

@(test)
test_unify_function_arity_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	params_a := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_a[0] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_a,
		semantics.Inferred_Function{param_ids = params_a, return_id = ret_a, effect_id = eff_a},
	)

	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 2)
	params_b[0] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	params_b[1] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_b,
		semantics.Inferred_Function{param_ids = params_b, return_id = ret_b, effect_id = eff_b},
	)

	ok := semantics.unify(&store, fn_a, fn_b)
	testing.expect(t, !ok)
}

@(test)
test_unify_function_param_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	str_name := base.intern(store.interner, "Str")

	params_a := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_a[0] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_a,
		semantics.Inferred_Function{param_ids = params_a, return_id = ret_a, effect_id = eff_a},
	)

	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_b[0] = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	ret_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_b,
		semantics.Inferred_Function{param_ids = params_b, return_id = ret_b, effect_id = eff_b},
	)

	ok := semantics.unify(&store, fn_a, fn_b)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(collector))
}

@(test)
test_unify_effect_row_same_effects :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	console_name := base.intern(store.interner, "Console")

	eff_entries_a := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_a[0] = semantics.Effect_Row_Entry {
		name      = console_name,
		type_args = {},
	}
	rest_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		row_a,
		semantics.Inferred_Effect_Row{effects = eff_entries_a, rest_id = rest_a},
	)

	eff_entries_b := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_b[0] = semantics.Effect_Row_Entry {
		name      = console_name,
		type_args = {},
	}
	rest_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		row_b,
		semantics.Inferred_Effect_Row{effects = eff_entries_b, rest_id = rest_b},
	)

	ok := semantics.unify(&store, row_a, row_b)
	testing.expect(t, ok)
}

@(test)
test_unify_effect_row_different_effects :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	console_name := base.intern(store.interner, "Console")
	file_name := base.intern(store.interner, "File")

	eff_entries_a := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_a[0] = semantics.Effect_Row_Entry {
		name      = console_name,
		type_args = {},
	}
	rest_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		row_a,
		semantics.Inferred_Effect_Row{effects = eff_entries_a, rest_id = rest_a},
	)

	eff_entries_b := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_b[0] = semantics.Effect_Row_Entry {
		name      = file_name,
		type_args = {},
	}
	rest_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		row_b,
		semantics.Inferred_Effect_Row{effects = eff_entries_b, rest_id = rest_b},
	)

	ok := semantics.unify(&store, row_a, row_b)
	testing.expect(t, ok)
}

@(test)
test_unify_record_row_same_fields :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	str_name := base.intern(store.interner, "Str")
	x_name := base.intern(store.interner, "x")
	y_name := base.intern(store.interner, "y")

	fields_a := semantics.store_alloc(&store, semantics.Type_Field_Entry, 2)
	fields_a[0] = semantics.Type_Field_Entry {
		name = x_name,
		var  = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
	}
	fields_a[1] = semantics.Type_Field_Entry {
		name = y_name,
		var  = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO),
	}
	rest_a := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		rec_a,
		semantics.Inferred_Record_Row{record_fields = fields_a, record_rest = rest_a},
	)

	fields_b := semantics.store_alloc(&store, semantics.Type_Field_Entry, 2)
	fields_b[0] = semantics.Type_Field_Entry {
		name = x_name,
		var  = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
	}
	fields_b[1] = semantics.Type_Field_Entry {
		name = y_name,
		var  = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO),
	}
	rest_b := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		rec_b,
		semantics.Inferred_Record_Row{record_fields = fields_b, record_rest = rest_b},
	)

	ok := semantics.unify(&store, rec_a, rec_b)
	testing.expect(t, ok)
}

@(test)
test_unify_record_row_field_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	str_name := base.intern(store.interner, "Str")
	x_name := base.intern(store.interner, "x")

	fields_a := semantics.store_alloc(&store, semantics.Type_Field_Entry, 1)
	fields_a[0] = semantics.Type_Field_Entry {
		name = x_name,
		var  = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
	}
	rest_a := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		rec_a,
		semantics.Inferred_Record_Row{record_fields = fields_a, record_rest = rest_a},
	)

	fields_b := semantics.store_alloc(&store, semantics.Type_Field_Entry, 1)
	fields_b[0] = semantics.Type_Field_Entry {
		name = x_name,
		var  = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO),
	}
	rest_b := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		rec_b,
		semantics.Inferred_Record_Row{record_fields = fields_b, record_rest = rest_b},
	)

	ok := semantics.unify(&store, rec_a, rec_b)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(collector))
}

@(test)
test_typecheck_function_application :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("add = |x: I64| -> I64 { x }\nresult = add(1)")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_effectful_naming_enforcement :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"IO! : { println!: || -> Str }\nresult = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }",
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_unhandled_effect_error :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"IO! : { println!: || -> Str }\nval = IO.println(\"hello\")",
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_handled_effect_ok :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hello\") } with { .println!(resume) => resume({}) }",
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_simple :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@UserId : U64")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	uid_name := base.intern(&ctx.interner, "UserId")
	_, ok := store.newtype_decls[uid_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_parameterized :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@Result(a, e) : [Ok(a) | Err(e)]")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	result_name := base.intern(&ctx.interner, "Result")
	info, ok := store.newtype_decls[result_name]
	testing.expect(t, ok)
	testing.expect(t, len(info.type_params) == 2)
	testing.expect(t, len(info.owned_tags) == 2)
}

@(test)
test_newtype_nominal_distinctness :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := base.intern(store.interner, "UserId")
	oid_name := base.intern(store.interner, "OrderId")
	i64_name := base.intern(store.interner, "I64")

	uid_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		uid_var,
		semantics.Inferred_Newtype {
			primitive_name = uid_name,
			arity = 0,
			param_ids = nil,
			inner_id = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
		},
	)

	oid_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		oid_var,
		semantics.Inferred_Newtype {
			primitive_name = oid_name,
			arity = 0,
			param_ids = nil,
			inner_id = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
		},
	)

	ok := semantics.unify(&store, uid_var, oid_var)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(collector))
}

@(test)
test_newtype_no_semantics_unify_with_inner :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := base.intern(store.interner, "UserId")
	i64_name := base.intern(store.interner, "I64")

	i64_var := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)

	uid_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		uid_var,
		semantics.Inferred_Newtype {
			primitive_name = uid_name,
			arity = 0,
			param_ids = nil,
			inner_id = i64_var,
		},
	)

	fresh_i64 := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ok := semantics.unify(&store, uid_var, fresh_i64)
	testing.expect(t, !ok)
}

@(test)
test_newtype_same_name_unifies :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := base.intern(store.interner, "UserId")
	i64_name := base.intern(store.interner, "I64")

	inner := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)

	uid_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		uid_a,
		semantics.Inferred_Newtype {
			primitive_name = uid_name,
			arity = 0,
			param_ids = nil,
			inner_id = inner,
		},
	)

	uid_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		uid_b,
		semantics.Inferred_Newtype {
			primitive_name = uid_name,
			arity = 0,
			param_ids = nil,
			inner_id = inner,
		},
	)

	ok := semantics.unify(&store, uid_a, uid_b)
	testing.expect(t, ok)
}

@(test)
test_newtype_with_trait :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@UserId : U64")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_wrapping_record :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@User : { name: Str, age: U64 }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	user_name := base.intern(&ctx.interner, "User")
	_, ok := store.newtype_decls[user_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_construction :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@UserId : U64\nx = UserId(42)")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_tag_ownership :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@Result(a, e) : [Ok(a) | Err(e)]\nx = Result.Ok(42)")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_inner_access :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@UserId : U64\nuid = UserId(42)\nn = uid.inner()")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_construct_cross_module :: proc(t: ^testing.T) {
	ctx := new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer free(ctx)
	defer build.context_destroy(ctx)

	store := new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(store)
	defer free(store)
	defer semantics.type_store_destroy(store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_into_store("@UserId : U64", store, ctx, mod_a)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_into_store("x = UserId(42)", store, ctx, mod_b)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_pub_variants_cross_module :: proc(t: ^testing.T) {
	ctx := new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer free(ctx)
	defer build.context_destroy(ctx)

	store := new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(store)
	defer free(store)
	defer semantics.type_store_destroy(store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_into_store("@Result(a, e) : pub [Ok(a) | Err(e)]", store, ctx, mod_a)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_into_store("x = Result.Ok(42)", store, ctx, mod_b)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_inner_cross_module :: proc(t: ^testing.T) {
	ctx := new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer free(ctx)
	defer build.context_destroy(ctx)

	store := new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(store)
	defer free(store)
	defer semantics.type_store_destroy(store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_into_store("@UserId : U64\nuid = UserId(42)", store, ctx, mod_a)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_into_store("n = uid.inner()", store, ctx, mod_b)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_signature_mismatch :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"Eq : { eq: (Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x| 42",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_param_mismatch :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x| True",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_orphan_rule :: proc(t: ^testing.T) {
	ctx := new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer free(ctx)
	defer build.context_destroy(ctx)

	store := new(semantics.Type_Store)
	semantics.type_store_init(store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(store)
	defer free(store)
	defer semantics.type_store_destroy(store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_into_store("Eq : { eq: (Self) -> Bool }", store, ctx, mod_a)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_into_store("@UserId is Eq : U64\nUserId_eq = |x| True", store, ctx, mod_b)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_overlapping_instance :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"Eq : { eq: (Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x| True\n@UserId is Eq : U64\nUserId_eq2 = |x| True",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_missing_method :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"Eq : { eq: (Self) -> Bool }\n@UserId is Eq : U64",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

mono_source :: proc(
	source: string,
) -> (
	semantics.TFile,
	^build.Compilation_Context,
	semantics.Type_Store,
) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File {
		path     = "<mono-test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)

	mono_tfile := mono.mono(tfile, &store, &ctx.interner)

	return mono_tfile, ctx, store
}

teardown_mono :: proc(ctx: ^build.Compilation_Context, store: ^semantics.Type_Store) {
	semantics.type_store_destroy(store)
	build.context_destroy(ctx)
	free(ctx)
}

find_tdecl_by_name :: proc(tfile: semantics.TFile, name: base.Intern_ID) -> semantics.TDecl {
	for decl in tfile.decls {
		#partial switch d in decl {
		case ^semantics.TDecl_Const:
			if d.name.name == name {
				return decl
			}
		case:
		}
	}
	return nil
}

@(test)
test_mono_mangle_generic :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source("id = |x: a| -> a { x }\nresult! = id(42)")
	defer teardown_mono(ctx, &store)

	// Generic decls are replaced by specialized versions in mono output
	id_spec_name := base.intern(&ctx.interner, "id$I64")
	id_spec_decl := find_tdecl_by_name(mono_tfile, id_spec_name)
	testing.expect(t, id_spec_decl != nil)

	// The original generic decl should NOT be in the output
	id_name := base.intern(&ctx.interner, "id")
	id_decl := find_tdecl_by_name(mono_tfile, id_name)
	testing.expect(t, id_decl == nil)
}

@(test)
test_mono_generic_multiple_specializations :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source("id = |x: a| -> a { x }\ny = id(42)\nz = id(True)")
	defer teardown_mono(ctx, &store)

	// Both I64 and Bool specializations should exist
	i64_spec_name := base.intern(&ctx.interner, "id$I64")
	i64_spec_decl := find_tdecl_by_name(mono_tfile, i64_spec_name)
	testing.expect(t, i64_spec_decl != nil, "id$I64 specialization should exist")

	bool_spec_name := base.intern(&ctx.interner, "id$Bool")
	bool_spec_decl := find_tdecl_by_name(mono_tfile, bool_spec_name)
	testing.expect(t, bool_spec_decl != nil, "id$Bool specialization should exist")

	// Original generic should be absent
	id_name := base.intern(&ctx.interner, "id")
	id_decl := find_tdecl_by_name(mono_tfile, id_name)
	testing.expect(t, id_decl == nil, "original generic id should be absent from mono output")
}

@(test)
test_mono_generic_call_site_rewritten :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source("id = |x: a| -> a { x }\ny = id(42)")
	defer teardown_mono(ctx, &store)

	y_name := base.intern(&ctx.interner, "y")
	y_decl := find_tdecl_by_name(mono_tfile, y_name)
	testing.expect(t, y_decl != nil, "y decl should exist")

	d, ok := y_decl.(^semantics.TDecl_Const)
	testing.expect(t, ok, "y should be a TDecl_Const")
	if !ok do return

	call, is_call := d.body.(^semantics.TExpr_Call)
	testing.expect(t, is_call, "y's body should be a TExpr_Call")
	if !is_call do return

	name_expr, is_name := call.callee.(^semantics.TExpr_Name)
	testing.expect(t, is_name, "y's callee should be a TExpr_Name")
	if !is_name do return

	id_spec_name := base.intern(&ctx.interner, "id$I64")
	testing.expect(t, name_expr.name.name == id_spec_name, "y should call id$I64, not id")
}

@(test)
test_mono_specialized_decl_has_concrete_types :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source("id = |x: a| -> a { x }\ny = id(42)")
	defer teardown_mono(ctx, &store)

	id_spec_name := base.intern(&ctx.interner, "id$I64")
	id_spec_decl := find_tdecl_by_name(mono_tfile, id_spec_name)
	testing.expect(t, id_spec_decl != nil, "id$I64 specialization should exist")

	if d, ok := id_spec_decl.(^semantics.TDecl_Const); ok {
		if lambda, is_lambda := d.body.(^semantics.TExpr_Lambda); is_lambda {
			testing.expect(t, len(lambda.params) == 1, "id$I64 should have 1 param")
			if len(lambda.params) > 0 {
				param_type_id := lambda.params[0].type_.type_id
				resolved := semantics.resolve_var(&store, param_type_id)
				v := &store.vars[int(resolved)]
				if inf, ok := v.link.(semantics.Inferred_Type); ok {
					if prim, ok := inf.(semantics.Inferred_Primitive); ok {
						i64_name := base.intern(&ctx.interner, "I64")
						testing.expect(
							t,
							prim.primitive_name == i64_name,
							"id$I64 param should be I64",
						)
					}
				}
			}

			ret_type_id := lambda.return_type.type_id
			ret_resolved := semantics.resolve_var(&store, ret_type_id)
			ret_v := &store.vars[int(ret_resolved)]
			if inf, ok := ret_v.link.(semantics.Inferred_Type); ok {
				if prim, ok := inf.(semantics.Inferred_Primitive); ok {
					i64_name := base.intern(&ctx.interner, "I64")
					testing.expect(
						t,
						prim.primitive_name == i64_name,
						"id$I64 return should be I64",
					)
				}
			}
		}
	}
}

@(test)
test_lambda_type_params_in_store_bindings :: proc(t: ^testing.T) {
	// RC1: Lambda type params should be registered in store.bindings
	// so substitute_ir_type can resolve them during monomorphization
	store, ctx, tfile := setup_for_typecheck("id = |x: a| -> a { x }")
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	// The type param 'a' should be in store.bindings
	a_name := base.intern(&ctx.interner, "a")
	_, has_binding := store.bindings[a_name]
	testing.expect(t, has_binding, "type param 'a' should be in store.bindings (RC1)")

	// It should be LEVEL_GENERIC (generalized after typechecking)
	if has_binding {
		tv_id := store.bindings[a_name]
		testing.expect(
			t,
			semantics.is_generic(store, tv_id),
			"type param 'a' should be LEVEL_GENERIC",
		)
	}
}

@(test)
test_mono_non_generic_passes_through :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source("x = 42\ny = x + 1")
	defer teardown_mono(ctx, &store)

	testing.expect(t, len(mono_tfile.decls) == 2, "non-generic code should have 2 decls")

	for decl in mono_tfile.decls {
		if d, ok := decl.(^semantics.TDecl_Const); ok {
			testing.expect(t, d.type_.wasm_type != {}, "all decls should have wasm_type")
			testing.expect(
				t,
				d.type_.type_id != base.Type_Var_ID(-1),
				"all decls should have valid type_id",
			)
		}
	}
}

@(test)
test_display_trait_registered :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	semantics.inject_prelude_effects_typecheck(&store)

	display_name := base.intern(store.interner, "Display")
	_, found := store.trait_registry[display_name]
	testing.expect(t, found, "Display trait should be registered after prelude injection")

	if found {
		info := store.trait_registry[display_name]
		testing.expect(t, len(info.methods) == 1, "Display should have exactly 1 method")
		if len(info.methods) == 1 {
			to_str_name := base.intern(store.interner, "to_str")
			testing.expect(
				t,
				info.methods[0].name == to_str_name,
				"Display method should be 'to_str'",
			)
		}
	}
}

@(test)
test_display_impl_for_primitives :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	semantics.inject_prelude_effects_typecheck(&store)

	display_name := base.intern(store.interner, "Display")

	types := []string{"Str", "I64", "I32", "F64", "Bool"}
	for type_name in types {
		type_id := base.intern(store.interner, type_name)
		_, found := semantics.find_trait_impl(&store, display_name, type_id)
		testing.expect(t, found, fmt.tprintf("Display impl should exist for {}", type_name))
	}
}

@(test)
test_implements_display_helper :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	semantics.inject_prelude_effects_typecheck(&store)

	str_name := base.intern(store.interner, "Str")
	i64_name := base.intern(store.interner, "I64")
	i32_name := base.intern(store.interner, "I32")
	f64_name := base.intern(store.interner, "F64")
	bool_name := base.intern(store.interner, "Bool")
	u64_name := base.intern(store.interner, "U64")
	bytes_name := base.intern(store.interner, "Bytes")

	testing.expect(
		t,
		semantics.implements_display(&store, str_name),
		"Str should implement Display",
	)
	testing.expect(
		t,
		semantics.implements_display(&store, i64_name),
		"I64 should implement Display",
	)
	testing.expect(
		t,
		semantics.implements_display(&store, i32_name),
		"I32 should implement Display",
	)
	testing.expect(
		t,
		semantics.implements_display(&store, f64_name),
		"F64 should implement Display",
	)
	testing.expect(
		t,
		semantics.implements_display(&store, bool_name),
		"Bool should implement Display",
	)
	testing.expect(
		t,
		!semantics.implements_display(&store, u64_name),
		"U64 should NOT implement Display",
	)
	testing.expect(
		t,
		!semantics.implements_display(&store, bytes_name),
		"Bytes should NOT implement Display",
	)
}

check_method_call_resolved :: proc(expr: semantics.TExpr, found: ^bool) {
	#partial switch e in expr {
	case ^semantics.TExpr_Call:
		check_method_call_resolved(e.callee, found)
		for arg in e.args {
			check_method_call_resolved(arg, found)
		}
	case ^semantics.TExpr_Method_Call:
		_ = e
	case ^semantics.TExpr_Lambda:
		check_method_call_resolved(e.body, found)
	case ^semantics.TExpr_Block:
		for stmt in e.statements {
			check_method_call_resolved(stmt, found)
		}
	case ^semantics.TExpr_If:
		check_method_call_resolved(e.condition, found)
		check_method_call_resolved(e.then_branch, found)
		check_method_call_resolved(e.else_branch, found)
	case ^semantics.TExpr_BinOp:
		check_method_call_resolved(e.left, found)
		check_method_call_resolved(e.right, found)
	case ^semantics.TExpr_Match:
		check_method_call_resolved(e.scrutinee, found)
		for arm in e.arms {
			check_method_call_resolved(arm.body, found)
		}
	case:
	}
}

@(test)
test_newtype_wrapping_builtin_type :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck("@Uuid : pub Bytes", {with_prelude = true})
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	uuid_name := base.intern(&ctx.interner, "Uuid")
	_, ok := store.newtype_decls[uuid_name]
	testing.expect(t, ok)
}

@(test)
test_result_with_inline_tag_union_error :: proc(t: ^testing.T) {
	source := "get_age : Result(I64, [Absent]) = Result.Ok(42)\n"
	store, ctx, _ := setup_for_typecheck(source, {with_prelude = true})
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_record_with_result_fields :: proc(t: ^testing.T) {
	source := "@Result(a, e) : pub [Ok(a) | Err(e)]\n@Absent : pub [Absent]\n@Uri : pub { scheme : Str, query : Result(Str, Absent) }\n"
	store, ctx, _ := setup_for_typecheck(source, {with_prelude = true})
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	result_name := base.intern(&ctx.interner, "Result")
	_, result_ok := store.newtype_decls[result_name]
	testing.expect(t, result_ok)
	uri_name := base.intern(&ctx.interner, "Uri")
	_, uri_ok := store.newtype_decls[uri_name]
	testing.expect(t, uri_ok)
}

@(test)
test_effect_declaration_with_effect_row :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"Random! : { bytes! : |I64| -[Random!]-> Bytes }",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_crash_intrinsic_body :: proc(t: ^testing.T) {
	source := "@JsonValue : pub [Null]\n@JsonErr : pub [UnexpectedEnd]\n@Result(a, e) : pub [Ok(a) | Err(e)]\npub decode : |Str| -> Result(JsonValue, JsonErr) = |_s| crash \"intrinsic: Json.decode\"\n"
	store, ctx, _ := setup_for_typecheck(source, {with_prelude = true})
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	json_value_name := base.intern(&ctx.interner, "JsonValue")
	_, jv_ok := store.newtype_decls[json_value_name]
	testing.expect(t, jv_ok)
	json_err_name := base.intern(&ctx.interner, "JsonErr")
	_, je_ok := store.newtype_decls[json_err_name]
	testing.expect(t, je_ok)
}

@(test)
test_tag_union_with_multiple_payloads :: proc(t: ^testing.T) {
	store, ctx, _ := setup_for_typecheck(
		"@JsonNumber : pub [PosInt(U64) | NegInt(I64) | Float(F64)]",
		{with_prelude = true},
	)
	defer free(ctx)
	defer free(store)
	defer build.context_destroy(ctx)
	defer semantics.type_store_destroy(store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	json_number_name := base.intern(&ctx.interner, "JsonNumber")
	info, ok := store.newtype_decls[json_number_name]
	testing.expect(t, ok)
	testing.expect(t, len(info.owned_tags) == 3)
}


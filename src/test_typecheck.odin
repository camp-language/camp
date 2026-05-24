package camp

import "core:fmt"
import "core:testing"
import "camp:base"
import "camp:frontend"
import "camp:semantics"
import "camp:mono"
import "camp:build"
import "camp:diagnostics"

setup_type_store :: proc() -> (semantics.Type_Store, ^diagnostics.Diagnostic_Collector) {
	store: semantics.Type_Store
	collector: ^diagnostics.Diagnostic_Collector = new(diagnostics.Diagnostic_Collector)
	diagnostics.diag_collector_init(collector)
	intern_table: ^base.Intern_Table = new(base.Intern_Table)
	base.intern_init(intern_table)
	semantics.type_store_init(&store, intern_table, collector)
	return store, collector
}

teardown_type_store :: proc(store: ^semantics.Type_Store, collector: ^diagnostics.Diagnostic_Collector) {
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

	va := semantics.get_var(&store, semantics.resolve_var(&store, a))
	vb := semantics.get_var(&store, semantics.resolve_var(&store, b))
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

typecheck_source :: proc(source: string) -> (semantics.Type_Store, ^build.Compilation_Context) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.typecheck_file(canon, &store)
	return store, ctx
}

typecheck_source_full :: proc(source: string) -> (semantics.Type_Store, ^build.Compilation_Context, semantics.CFile, semantics.TFile) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	tfile := semantics.typecheck_file(canon, &store)
	return store, ctx, canon, tfile
}

typecheck_source_with_prelude :: proc(source: string) -> (semantics.Type_Store, ^build.Compilation_Context) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	semantics.typecheck_file(canon, &store)
	return store, ctx
}

typecheck_source_with_module :: proc(source: string, current_module: base.Intern_ID, store: ^semantics.Type_Store, ctx: ^build.Compilation_Context) {
	file := base.Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)
	semantics.typecheck_file(canon, store, current_module)
}

@(test)
test_typecheck_int_literal :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 42")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_lambda :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("add = |x, y| x")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_if_same_type :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("val = if true 1 else 2")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("r = { name: \"Camp\", age: 1 }")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_undefined_name :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = undefined_var")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_let_polymorphism :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("id = |x| x\na = id(1)\nb = id(True)")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_annotation_check :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 42")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_binop :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 1 + 2\ny = true and false")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_not :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = not true")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

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
	semantics.link_var(&store, fn_a, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	param_b := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_b := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_b[0] = param_b
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, fn_b, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

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
	semantics.link_var(&store, fn_a, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 2)
	params_b[0] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	params_b[1] = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, fn_b, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

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
	semantics.link_var(&store, fn_a, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	params_b := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params_b[0] = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	ret_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	eff_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	fn_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, fn_b, semantics.Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

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
	eff_entries_a[0] = semantics.Effect_Row_Entry{name = console_name, type_args = {}}
	rest_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, row_a, semantics.Inferred_Type{
		tag = .Effect_Row,
		effects = eff_entries_a,
		rest_id = rest_a,
	})

	eff_entries_b := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_b[0] = semantics.Effect_Row_Entry{name = console_name, type_args = {}}
	rest_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, row_b, semantics.Inferred_Type{
		tag = .Effect_Row,
		effects = eff_entries_b,
		rest_id = rest_b,
	})

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
	eff_entries_a[0] = semantics.Effect_Row_Entry{name = console_name, type_args = {}}
	rest_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_a := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, row_a, semantics.Inferred_Type{
		tag = .Effect_Row,
		effects = eff_entries_a,
		rest_id = rest_a,
	})

	eff_entries_b := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries_b[0] = semantics.Effect_Row_Entry{name = file_name, type_args = {}}
	rest_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	row_b := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, row_b, semantics.Inferred_Type{
		tag = .Effect_Row,
		effects = eff_entries_b,
		rest_id = rest_b,
	})

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
	fields_a[0] = semantics.Type_Field_Entry{name = x_name, var = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)}
	fields_a[1] = semantics.Type_Field_Entry{name = y_name, var = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)}
	rest_a := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, rec_a, semantics.Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_a,
		record_rest = rest_a,
	})

	fields_b := semantics.store_alloc(&store, semantics.Type_Field_Entry, 2)
	fields_b[0] = semantics.Type_Field_Entry{name = x_name, var = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)}
	fields_b[1] = semantics.Type_Field_Entry{name = y_name, var = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)}
	rest_b := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, rec_b, semantics.Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_b,
		record_rest = rest_b,
	})

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
	fields_a[0] = semantics.Type_Field_Entry{name = x_name, var = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)}
	rest_a := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_a := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, rec_a, semantics.Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_a,
		record_rest = rest_a,
	})

	fields_b := semantics.store_alloc(&store, semantics.Type_Field_Entry, 1)
	fields_b[0] = semantics.Type_Field_Entry{name = x_name, var = semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)}
	rest_b := semantics.fresh_record_row(&store, base.Source_Span_ZERO)
	rec_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, rec_b, semantics.Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_b,
		record_rest = rest_b,
	})

	ok := semantics.unify(&store, rec_a, rec_b)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(collector))
}

@(test)
test_typecheck_function_application :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("add = |x: I64, y: I64| -> I64 { x }\nresult = add(1, 2)")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_effectful_naming_enforcement :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"IO! : { println!: || -> Str }\nresult = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_unhandled_effect_error :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"IO! : { println!: || -> Str }\nval = IO.println(\"hello\")")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_handled_effect_ok :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hello\") } with { .println!(resume) => resume({}) }")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_simple :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@UserId : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	uid_name := base.intern(&ctx.interner, "UserId")
	_, ok := store.newtype_decls[uid_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_parameterized :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@Result(a, e) : [Ok(a) | Err(e)]")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

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
	semantics.link_var(&store, uid_var, semantics.Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
	})

	oid_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, oid_var, semantics.Inferred_Type{
		tag = .Newtype,
		primitive_name = oid_name,
		arity = 0,
		param_ids = nil,
		inner_id = semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO),
	})

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
	semantics.link_var(&store, uid_var, semantics.Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = i64_var,
	})

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
	semantics.link_var(&store, uid_a, semantics.Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = inner,
	})

	uid_b := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(&store, uid_b, semantics.Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = inner,
	})

	ok := semantics.unify(&store, uid_a, uid_b)
	testing.expect(t, ok)
}

@(test)
test_newtype_with_trait :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@UserId : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_wrapping_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@User : { name: Str, age: U64 }")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	user_name := base.intern(&ctx.interner, "User")
	_, ok := store.newtype_decls[user_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_construction :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@UserId : U64\nx = UserId(42)")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_tag_ownership :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@Result(a, e) : [Ok(a) | Err(e)]\nx = Result.Ok(42)")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_inner_access :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@UserId : U64\nuid = UserId(42)\nn = uid.inner()")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_construct_cross_module :: proc(t: ^testing.T) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	defer build.context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	defer semantics.type_store_destroy(&store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@UserId : U64", mod_a, &store, ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("x = UserId(42)", mod_b, &store, ctx)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_pub_variants_cross_module :: proc(t: ^testing.T) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	defer build.context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	defer semantics.type_store_destroy(&store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@Result(a, e) : pub [Ok(a) | Err(e)]", mod_a, &store, ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("x = Result.Ok(42)", mod_b, &store, ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_inner_cross_module :: proc(t: ^testing.T) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	defer build.context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	defer semantics.type_store_destroy(&store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@UserId : U64\nuid = UserId(42)", mod_a, &store, ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("n = uid.inner()", mod_b, &store, ctx)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_signature_match :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	eq_name := base.intern(&ctx.interner, "Eq")
	_, found := store.trait_registry[eq_name]
	testing.expect(t, found)
}

@(test)
test_trait_method_signature_mismatch :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| 42")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_param_mismatch :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x| true")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_orphan_rule :: proc(t: ^testing.T) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	defer build.context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	defer semantics.type_store_destroy(&store)

	mod_a := base.intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("Eq : { eq: (Self, Self) -> Bool }", mod_a, &store, ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	mod_b := base.intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("@UserId is Eq : U64\nUserId_eq = |x, y| true", mod_b, &store, ctx)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_overlapping_instance :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true\n@UserId is Eq : U64\nUserId_eq2 = |x, y| true")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_missing_method :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_derive_eq_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	eq_name := base.intern(&ctx.interner, "Eq")
	uid_name := base.intern(&ctx.interner, "UserId")
	_, found := semantics.find_trait_impl(&store, eq_name, uid_name)
	testing.expect(t, found)
}

@(test)
test_derive_clone_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Clone : { clone: (Self) -> Self }\n@UserId is Clone : U64\nUserId_clone = |x| x")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	clone_name := base.intern(&ctx.interner, "Clone")
	uid_name := base.intern(&ctx.interner, "UserId")
	_, found := semantics.find_trait_impl(&store, clone_name, uid_name)
	testing.expect(t, found)
}

@(test)
test_derive_hash_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Hash : { hash: (Self) -> U64 }\n@UserId is Hash : U64\nUserId_hash = |x| x.inner()")
	defer build.context_destroy(ctx)
	defer free(ctx)
	defer semantics.type_store_destroy(&store)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	hash_name := base.intern(&ctx.interner, "Hash")
	uid_name := base.intern(&ctx.interner, "UserId")
	_, found := semantics.find_trait_impl(&store, hash_name, uid_name)
	testing.expect(t, found)
}

mono_source :: proc(source: string) -> (semantics.TFile, ^build.Compilation_Context, semantics.Type_Store) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File{path = "<mono-test>", contents = source, id = 0}
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
	mono_tfile, ctx, store := mono_source("id = <a>|x: a| -> a { x }\nresult! = id(42)")
	defer teardown_mono(ctx, &store)

	id_name := base.intern(&ctx.interner, "id")
	id_decl := find_tdecl_by_name(mono_tfile, id_name)
	testing.expect(t, id_decl != nil)
}

@(test)
test_mono_method_dispatch :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true\ntest_eq! = UserId.eq(UserId(1), UserId(2))")
	defer teardown_mono(ctx, &store)

	eq_name := base.intern(&ctx.interner, "Eq")
	_, found := store.trait_registry[eq_name]
	testing.expect(t, found)

	uid_name := base.intern(&ctx.interner, "UserId")
	_, impl_found := semantics.find_trait_impl(&store, eq_name, uid_name)
	testing.expect(t, impl_found)
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
			testing.expect(t, info.methods[0].name == to_str_name, "Display method should be 'to_str'")
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

	testing.expect(t, semantics.implements_display(&store, str_name), "Str should implement Display")
	testing.expect(t, semantics.implements_display(&store, i64_name), "I64 should implement Display")
	testing.expect(t, semantics.implements_display(&store, i32_name), "I32 should implement Display")
	testing.expect(t, semantics.implements_display(&store, f64_name), "F64 should implement Display")
	testing.expect(t, semantics.implements_display(&store, bool_name), "Bool should implement Display")
	testing.expect(t, !semantics.implements_display(&store, u64_name), "U64 should NOT implement Display")
	testing.expect(t, !semantics.implements_display(&store, bytes_name), "Bytes should NOT implement Display")
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

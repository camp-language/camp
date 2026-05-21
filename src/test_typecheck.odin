package camp

import "core:fmt"
import "core:testing"

setup_type_store :: proc() -> (Type_Store, ^Diagnostic_Collector) {
	store: Type_Store
	collector: ^Diagnostic_Collector = new(Diagnostic_Collector)
	diag_collector_init(collector)
	intern_table: ^Intern_Table = new(Intern_Table)
	intern_init(intern_table)
	type_store_init(&store, intern_table, collector)
	return store, collector
}

teardown_type_store :: proc(store: ^Type_Store, collector: ^Diagnostic_Collector) {
	intern_destroy(store.interner)
	free(store.interner)
	type_store_destroy(store)
	diag_collector_destroy(collector)
	free(collector)
}

@(test)
test_unify_fresh_vars :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	a := fresh_value_var(&store, Source_Span_ZERO)
	b := fresh_value_var(&store, Source_Span_ZERO)

	ok := unify(&store, a, b)
	testing.expect(t, ok)

	resolved_a := resolve_var(&store, a)
	resolved_b := resolve_var(&store, b)
	testing.expect(t, resolved_a == resolved_b)
}

@(test)
test_unify_level_propagation :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	enter_level(&store)
	a := fresh_value_var(&store, Source_Span_ZERO)
	exit_level(&store)

	b := fresh_value_var(&store, Source_Span_ZERO)

	ok := unify(&store, a, b)
	testing.expect(t, ok)

	va := get_var(&store, resolve_var(&store, a))
	vb := get_var(&store, resolve_var(&store, b))
	max_level := max(va.level, vb.level)
	testing.expect(t, va.level == max_level)
	testing.expect(t, vb.level == max_level)
}

@(test)
test_generalize_at_level :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	enter_level(&store)
	a := fresh_value_var(&store, Source_Span_ZERO)
	level := store.current_level
	exit_level(&store)

	testing.expect(t, !is_generic(&store, a))
	generalize_at_level(&store, level)
	testing.expect(t, is_generic(&store, a))
}

@(test)
test_unify_primitive_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	str_name := intern(store.interner, "Str")

	a := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	b := make_primitive_type(&store, str_name, Source_Span_ZERO)

	ok := unify(&store, a, b)
	testing.expect(t, !ok)
	testing.expect(t, diag_collector_has_errors(collector))
}

@(test)
test_unify_same_primitive :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")

	a := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	b := make_primitive_type(&store, i64_name, Source_Span_ZERO)

	ok := unify(&store, a, b)
	testing.expect(t, ok)
}

typecheck_source :: proc(source: string) -> (Type_Store, ^Compilation_Context) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	context.allocator = alloc

	file := Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	typecheck_file(canon, &store)
	return store, ctx
}

typecheck_source_full :: proc(source: string) -> (Type_Store, ^Compilation_Context, CFile) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	context.allocator = alloc

	file := Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	typecheck_file(canon, &store)
	return store, ctx, canon
}

@(test)
test_typecheck_int_literal :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_lambda :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("add = |x, y| x")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_if_same_type :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("val = if true 1 else 2")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("r = { name: \"Camp\", age: 1 }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_undefined_name :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = undefined_var")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_let_polymorphism :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("id = |x| x\na = id(1)\nb = id(True)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_annotation_check :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_binop :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 1 + 2\ny = true and false")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_not :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = not true")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_unify_function_same_arity :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	str_name := intern(store.interner, "Str")

	param_a := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ret_a := make_primitive_type(&store, str_name, Source_Span_ZERO)
	eff_a := fresh_effect_row(&store, Source_Span_ZERO)
	params_a := store_alloc(&store, Type_Var_ID, 1)
	params_a[0] = param_a
	fn_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_a, Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	param_b := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ret_b := make_primitive_type(&store, str_name, Source_Span_ZERO)
	eff_b := fresh_effect_row(&store, Source_Span_ZERO)
	params_b := store_alloc(&store, Type_Var_ID, 1)
	params_b[0] = param_b
	fn_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_b, Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

	ok := unify(&store, fn_a, fn_b)
	testing.expect(t, ok)
}

@(test)
test_unify_function_arity_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	params_a := store_alloc(&store, Type_Var_ID, 1)
	params_a[0] = make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ret_a := fresh_value_var(&store, Source_Span_ZERO)
	eff_a := fresh_effect_row(&store, Source_Span_ZERO)
	fn_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_a, Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	params_b := store_alloc(&store, Type_Var_ID, 2)
	params_b[0] = make_primitive_type(&store, i64_name, Source_Span_ZERO)
	params_b[1] = make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ret_b := fresh_value_var(&store, Source_Span_ZERO)
	eff_b := fresh_effect_row(&store, Source_Span_ZERO)
	fn_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_b, Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

	ok := unify(&store, fn_a, fn_b)
	testing.expect(t, !ok)
}

@(test)
test_unify_function_param_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	str_name := intern(store.interner, "Str")

	params_a := store_alloc(&store, Type_Var_ID, 1)
	params_a[0] = make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ret_a := fresh_value_var(&store, Source_Span_ZERO)
	eff_a := fresh_effect_row(&store, Source_Span_ZERO)
	fn_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_a, Inferred_Type{
		tag = .Function,
		param_ids = params_a,
		return_id = ret_a,
		effect_id = eff_a,
	})

	params_b := store_alloc(&store, Type_Var_ID, 1)
	params_b[0] = make_primitive_type(&store, str_name, Source_Span_ZERO)
	ret_b := fresh_value_var(&store, Source_Span_ZERO)
	eff_b := fresh_effect_row(&store, Source_Span_ZERO)
	fn_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, fn_b, Inferred_Type{
		tag = .Function,
		param_ids = params_b,
		return_id = ret_b,
		effect_id = eff_b,
	})

	ok := unify(&store, fn_a, fn_b)
	testing.expect(t, !ok)
	testing.expect(t, diag_collector_has_errors(collector))
}

@(test)
test_unify_effect_row_same_effects :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	console_name := intern(store.interner, "Console")

	eff_names_a := store_alloc(&store, Intern_ID, 1)
	eff_names_a[0] = console_name
	rest_a := fresh_effect_row(&store, Source_Span_ZERO)
	row_a := fresh_effect_row(&store, Source_Span_ZERO)
	link_var(&store, row_a, Inferred_Type{
		tag = .Effect_Row,
		effect_names = eff_names_a,
		rest_id = rest_a,
	})

	eff_names_b := store_alloc(&store, Intern_ID, 1)
	eff_names_b[0] = console_name
	rest_b := fresh_effect_row(&store, Source_Span_ZERO)
	row_b := fresh_effect_row(&store, Source_Span_ZERO)
	link_var(&store, row_b, Inferred_Type{
		tag = .Effect_Row,
		effect_names = eff_names_b,
		rest_id = rest_b,
	})

	ok := unify(&store, row_a, row_b)
	testing.expect(t, ok)
}

@(test)
test_unify_effect_row_different_effects :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	console_name := intern(store.interner, "Console")
	file_name := intern(store.interner, "File")

	eff_names_a := store_alloc(&store, Intern_ID, 1)
	eff_names_a[0] = console_name
	rest_a := fresh_effect_row(&store, Source_Span_ZERO)
	row_a := fresh_effect_row(&store, Source_Span_ZERO)
	link_var(&store, row_a, Inferred_Type{
		tag = .Effect_Row,
		effect_names = eff_names_a,
		rest_id = rest_a,
	})

	eff_names_b := store_alloc(&store, Intern_ID, 1)
	eff_names_b[0] = file_name
	rest_b := fresh_effect_row(&store, Source_Span_ZERO)
	row_b := fresh_effect_row(&store, Source_Span_ZERO)
	link_var(&store, row_b, Inferred_Type{
		tag = .Effect_Row,
		effect_names = eff_names_b,
		rest_id = rest_b,
	})

	ok := unify(&store, row_a, row_b)
	testing.expect(t, ok)
}

@(test)
test_unify_record_row_same_fields :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	str_name := intern(store.interner, "Str")
	x_name := intern(store.interner, "x")
	y_name := intern(store.interner, "y")

	fields_a := store_alloc(&store, Type_Field_Entry, 2)
	fields_a[0] = Type_Field_Entry{name = x_name, var = make_primitive_type(&store, i64_name, Source_Span_ZERO)}
	fields_a[1] = Type_Field_Entry{name = y_name, var = make_primitive_type(&store, str_name, Source_Span_ZERO)}
	rest_a := fresh_record_row(&store, Source_Span_ZERO)
	rec_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, rec_a, Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_a,
		record_rest = rest_a,
	})

	fields_b := store_alloc(&store, Type_Field_Entry, 2)
	fields_b[0] = Type_Field_Entry{name = x_name, var = make_primitive_type(&store, i64_name, Source_Span_ZERO)}
	fields_b[1] = Type_Field_Entry{name = y_name, var = make_primitive_type(&store, str_name, Source_Span_ZERO)}
	rest_b := fresh_record_row(&store, Source_Span_ZERO)
	rec_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, rec_b, Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_b,
		record_rest = rest_b,
	})

	ok := unify(&store, rec_a, rec_b)
	testing.expect(t, ok)
}

@(test)
test_unify_record_row_field_mismatch :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")
	str_name := intern(store.interner, "Str")
	x_name := intern(store.interner, "x")

	fields_a := store_alloc(&store, Type_Field_Entry, 1)
	fields_a[0] = Type_Field_Entry{name = x_name, var = make_primitive_type(&store, i64_name, Source_Span_ZERO)}
	rest_a := fresh_record_row(&store, Source_Span_ZERO)
	rec_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, rec_a, Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_a,
		record_rest = rest_a,
	})

	fields_b := store_alloc(&store, Type_Field_Entry, 1)
	fields_b[0] = Type_Field_Entry{name = x_name, var = make_primitive_type(&store, str_name, Source_Span_ZERO)}
	rest_b := fresh_record_row(&store, Source_Span_ZERO)
	rec_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, rec_b, Inferred_Type{
		tag = .Record_Row,
		record_fields = fields_b,
		record_rest = rest_b,
	})

	ok := unify(&store, rec_a, rec_b)
	testing.expect(t, !ok)
	testing.expect(t, diag_collector_has_errors(collector))
}

@(test)
test_typecheck_function_application :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("add = |x: I64, y: I64| -> I64 { x }\nresult = add(1, 2)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_effectful_naming_enforcement :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"effect IO { println: Str }\nresult = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_unhandled_effect_error :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"effect IO { println: Str }\nval = IO.println(\"hello\")")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, ctx.collector.error_count > 0, fmt.tprintf("error_count = {}, diagnostics len = {}", ctx.collector.error_count, len(ctx.collector.diagnostics)))
	for d in ctx.collector.diagnostics {
		fmt.printfln("Error: {} at {}", d.message, d.span)
	}
}

@(test)
test_handled_effect_ok :: proc(t: ^testing.T) {
	store, ctx := typecheck_source(
		"effect IO { println: Str }\nmain! = handle IO in { IO.println(\"hello\") } with { .println!(resume) => resume({}) }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_simple :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("UserId := U64")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	uid_name := intern(&ctx.interner, "UserId")
	_, ok := store.newtype_decls[uid_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_parameterized :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("Result(a, e) := [Ok(a) | Err(e)]")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	result_name := intern(&ctx.interner, "Result")
	info, ok := store.newtype_decls[result_name]
	testing.expect(t, ok)
	testing.expect(t, len(info.type_params) == 2)
	testing.expect(t, len(info.owned_tags) == 2)
}

@(test)
test_newtype_nominal_distinctness :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := intern(store.interner, "UserId")
	oid_name := intern(store.interner, "OrderId")
	i64_name := intern(store.interner, "I64")

	uid_var := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, uid_var, Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = make_primitive_type(&store, i64_name, Source_Span_ZERO),
	})

	oid_var := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, oid_var, Inferred_Type{
		tag = .Newtype,
		primitive_name = oid_name,
		arity = 0,
		param_ids = nil,
		inner_id = make_primitive_type(&store, i64_name, Source_Span_ZERO),
	})

	ok := unify(&store, uid_var, oid_var)
	testing.expect(t, !ok)
	testing.expect(t, diag_collector_has_errors(collector))
}

@(test)
test_newtype_no_unify_with_inner :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := intern(store.interner, "UserId")
	i64_name := intern(store.interner, "I64")

	i64_var := make_primitive_type(&store, i64_name, Source_Span_ZERO)

	uid_var := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, uid_var, Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = i64_var,
	})

	fresh_i64 := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	ok := unify(&store, uid_var, fresh_i64)
	testing.expect(t, !ok)
}

@(test)
test_newtype_same_name_unifies :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := intern(store.interner, "UserId")
	i64_name := intern(store.interner, "I64")

	inner := make_primitive_type(&store, i64_name, Source_Span_ZERO)

	uid_a := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, uid_a, Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = inner,
	})

	uid_b := fresh_value_var(&store, Source_Span_ZERO)
	link_var(&store, uid_b, Inferred_Type{
		tag = .Newtype,
		primitive_name = uid_name,
		arity = 0,
		param_ids = nil,
		inner_id = inner,
	})

	ok := unify(&store, uid_a, uid_b)
	testing.expect(t, ok)
}

@(test)
test_newtype_with_trait :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("UserId := U64")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_wrapping_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("User := { name: Str, age: U64 }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	user_name := intern(&ctx.interner, "User")
	_, ok := store.newtype_decls[user_name]
	testing.expect(t, ok)
}

@(test)
test_newtype_construction :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("UserId := U64\nx = UserId(42)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_tag_ownership :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("Result(a, e) := [Ok(a) | Err(e)]\nx = Result.Ok(42)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_inner_access :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("UserId := U64\nuid = UserId(42)\nn = uid.inner()")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

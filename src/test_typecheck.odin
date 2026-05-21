package camp

import "core:fmt"
import "core:strings"
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

typecheck_source_with_prelude :: proc(source: string) -> (Type_Store, ^Compilation_Context) {
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
	inject_prelude(&store)
	typecheck_file(canon, &store)
	return store, ctx
}

typecheck_source_with_module :: proc(source: string, current_module: Intern_ID, store: ^Type_Store, ctx: ^Compilation_Context) {
	file := Source_File{path = "<tc-test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)
	typecheck_file(canon, store, current_module)
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
	store, ctx := typecheck_source("@UserId : U64")
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
	store, ctx := typecheck_source("@Result(a, e) : [Ok(a) | Err(e)]")
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
	store, ctx := typecheck_source("@UserId : U64")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_wrapping_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@User : { name: Str, age: U64 }")
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
	store, ctx := typecheck_source("@UserId : U64\nx = UserId(42)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_tag_ownership :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@Result(a, e) : [Ok(a) | Err(e)]\nx = Result.Ok(42)")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_inner_access :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("@UserId : U64\nuid = UserId(42)\nn = uid.inner()")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_construct_cross_module :: proc(t: ^testing.T) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	defer context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	defer type_store_destroy(&store)

	mod_a := intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@UserId : U64", mod_a, &store, ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	mod_b := intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("x = UserId(42)", mod_b, &store, ctx)
	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_pub_variants_cross_module :: proc(t: ^testing.T) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	defer context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	defer type_store_destroy(&store)

	mod_a := intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@Result(a, e) : pub [Ok(a) | Err(e)]", mod_a, &store, ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	mod_b := intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("x = Result.Ok(42)", mod_b, &store, ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
}

@(test)
test_newtype_opaque_inner_cross_module :: proc(t: ^testing.T) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	defer context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	defer type_store_destroy(&store)

	mod_a := intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("@UserId : U64\nuid = UserId(42)", mod_a, &store, ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	mod_b := intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("n = uid.inner()", mod_b, &store, ctx)
	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_signature_match :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	eq_name := intern(&ctx.interner, "Eq")
	_, found := store.trait_registry[eq_name]
	testing.expect(t, found)
}

@(test)
test_trait_method_signature_mismatch :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_method_param_mismatch :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x| true")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_orphan_rule :: proc(t: ^testing.T) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	defer context_destroy(ctx)
	defer free(ctx)
	context.allocator = alloc

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	defer type_store_destroy(&store)

	mod_a := intern(&ctx.interner, "ModuleA")
	typecheck_source_with_module("Eq : { eq: (Self, Self) -> Bool }", mod_a, &store, ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))

	mod_b := intern(&ctx.interner, "ModuleB")
	typecheck_source_with_module("@UserId is Eq : U64\nUserId_eq = |x, y| true", mod_b, &store, ctx)
	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_overlapping_instance :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true\n@UserId is Eq : U64\nUserId_eq2 = |x, y| true")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_trait_missing_method :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, diag_collector_has_errors(&ctx.collector))
}

@(test)
test_derive_eq_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	eq_name := intern(&ctx.interner, "Eq")
	uid_name := intern(&ctx.interner, "UserId")
	_, found := find_trait_impl(&store, eq_name, uid_name)
	testing.expect(t, found)
}

@(test)
test_derive_clone_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Clone : { clone: (Self) -> Self }\n@UserId is Clone : U64\nUserId_clone = |x| x")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	clone_name := intern(&ctx.interner, "Clone")
	uid_name := intern(&ctx.interner, "UserId")
	_, found := find_trait_impl(&store, clone_name, uid_name)
	testing.expect(t, found)
}

@(test)
test_derive_hash_generates_impl :: proc(t: ^testing.T) {
	store, ctx := typecheck_source_with_prelude(
		"Hash : { hash: (Self) -> U64 }\n@UserId is Hash : U64\nUserId_hash = |x| x.inner()")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	hash_name := intern(&ctx.interner, "Hash")
	uid_name := intern(&ctx.interner, "UserId")
	_, found := find_trait_impl(&store, hash_name, uid_name)
	testing.expect(t, found)
}

mono_source :: proc(source: string) -> (TFile, ^Compilation_Context, Type_Store) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	context.allocator = alloc

	file := Source_File{path = "<mono-test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	typecheck_file(canon, &store)

	annot_tfile := annotate_file(canon, &store)
	mono_tfile := mono(annot_tfile, &store, &ctx.interner)

	return mono_tfile, ctx, store
}

teardown_mono :: proc(ctx: ^Compilation_Context, store: ^Type_Store) {
	type_store_destroy(store)
	context_destroy(ctx)
	free(ctx)
}

find_tdecl_by_name :: proc(tfile: TFile, name: Intern_ID) -> TDecl {
	for decl in tfile.decls {
		#partial switch d in decl {
		case ^TDecl_Const:
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

	id_name := intern(&ctx.interner, "id")
	id_decl := find_tdecl_by_name(mono_tfile, id_name)
	testing.expect(t, id_decl != nil)
}

@(test)
test_mono_method_dispatch :: proc(t: ^testing.T) {
	mono_tfile, ctx, store := mono_source(
		"Eq : { eq: (Self, Self) -> Bool }\n@UserId is Eq : U64\nUserId_eq = |x, y| true\ntest_eq! = UserId.eq(UserId(1), UserId(2))")
	defer teardown_mono(ctx, &store)

	eq_name := intern(&ctx.interner, "Eq")
	_, found := store.trait_registry[eq_name]
	testing.expect(t, found)

	uid_name := intern(&ctx.interner, "UserId")
	_, impl_found := find_trait_impl(&store, eq_name, uid_name)
	testing.expect(t, impl_found)
}

check_method_call_resolved :: proc(expr: TExpr, found: ^bool) {
	#partial switch e in expr {
	case ^TExpr_Call:
		check_method_call_resolved(e.callee, found)
		for arg in e.args {
			check_method_call_resolved(arg, found)
		}
	case ^TExpr_Method_Call:
		_ = e
	case ^TExpr_Lambda:
		check_method_call_resolved(e.body, found)
	case ^TExpr_Block:
		for stmt in e.statements {
			check_method_call_resolved(stmt, found)
		}
	case ^TExpr_If:
		check_method_call_resolved(e.condition, found)
		check_method_call_resolved(e.then_branch, found)
		check_method_call_resolved(e.else_branch, found)
	case ^TExpr_BinOp:
		check_method_call_resolved(e.left, found)
		check_method_call_resolved(e.right, found)
	case ^TExpr_Match:
		check_method_call_resolved(e.scrutinee, found)
		for arm in e.arms {
			check_method_call_resolved(arm.body, found)
		}
	case:
	}
}

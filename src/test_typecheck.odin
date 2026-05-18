package camp

import "core:testing"

setup_type_store :: proc() -> (Type_Store, ^Error_Collector) {
	store: Type_Store
	collector: ^Error_Collector = new(Error_Collector)
	collector_init(collector)
	intern_table: ^Intern_Table = new(Intern_Table)
	intern_init(intern_table)
	type_store_init(&store, intern_table, collector)
	return store, collector
}

teardown_type_store :: proc(store: ^Type_Store, collector: ^Error_Collector) {
	intern_destroy(store.interner)
	free(store.interner)
	type_store_destroy(store)
	collector_destroy(collector)
	free(collector)
}

@(test)
test_unify_fresh_vars :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	a := fresh_value_var(&store, Source_Span_ZERO)
	b := fresh_value_var(&store, Source_Span_ZERO)

	err := unify(&store, a, b)
	testing.expect(t, err == nil)

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

	err := unify(&store, a, b)
	testing.expect(t, err == nil)

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

	err := unify(&store, a, b)
	testing.expect(t, err != nil)
	testing.expect(t, collector_has_errors(collector))
}

@(test)
test_unify_same_primitive :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := intern(store.interner, "I64")

	a := make_primitive_type(&store, i64_name, Source_Span_ZERO)
	b := make_primitive_type(&store, i64_name, Source_Span_ZERO)

	err := unify(&store, a, b)
	testing.expect(t, err == nil)
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

@(test)
test_typecheck_int_literal :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = 42")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_lambda :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("add = |x, y| x")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_if_same_type :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("val = if True 1 else 2")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_record :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("r = { name: \"Camp\", age: 1 }")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_typecheck_undefined_name :: proc(t: ^testing.T) {
	store, ctx := typecheck_source("x = undefined_var")
	defer context_destroy(ctx)
	defer free(ctx)
	defer type_store_destroy(&store)

	testing.expect(t, collector_has_errors(&ctx.collector))
}

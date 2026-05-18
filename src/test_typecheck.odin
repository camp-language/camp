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

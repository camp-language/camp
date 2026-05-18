package camp

import "core:testing"

@(test)
test_collector_add_warning :: proc(t: ^testing.T) {
	collector: Error_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	collector_add(&collector, .Warning, "unused variable", Source_Span_ZERO)
	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 0)
	testing.expect(t, !collector_has_errors(&collector))
}

@(test)
test_collector_add_error :: proc(t: ^testing.T) {
	collector: Error_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	collector_add(&collector, .Error, "type mismatch", Source_Span_ZERO)
	testing.expect(t, collector.warning_count == 0)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector_has_errors(&collector))
}

@(test)
test_collector_add_internal :: proc(t: ^testing.T) {
	collector: Error_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	collector_add(&collector, .Internal, "impossible type after typecheck", Source_Span_ZERO)
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, collector_has_errors(&collector))
}

@(test)
test_intern_same_string :: proc(t: ^testing.T) {
	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	id1 := intern(&table, "hello")
	id2 := intern(&table, "hello")
	testing.expect(t, id1 == id2)
}

@(test)
test_intern_different_strings :: proc(t: ^testing.T) {
	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	id1 := intern(&table, "hello")
	id2 := intern(&table, "world")
	testing.expect(t, id1 != id2)
}

@(test)
test_intern_roundtrip :: proc(t: ^testing.T) {
	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	id := intern(&table, "test_string")
	testing.expect(t, intern_get(&table, id) == "test_string")
}

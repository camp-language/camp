package camp

import "core:testing"

@(test)
test_collector_add_warning :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	collector_add_diag(&collector, diag_init(.Warning, "TEST", Source_Span_ZERO, "unused variable"))
	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 0)
	testing.expect(t, !diag_collector_has_errors(&collector))
}

@(test)
test_collector_add_error :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	collector_add_diag(&collector, diag_init(.Error, "TEST", Source_Span_ZERO, "type mismatch"))
	testing.expect(t, collector.warning_count == 0)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, diag_collector_has_errors(&collector))
}

@(test)
test_collector_add_internal :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	collector_add_diag(&collector, diag_init(.Internal, "TEST", Source_Span_ZERO, "impossible type after typecheck"))
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, diag_collector_has_errors(&collector))
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

package camp

import "core:testing"

import "camp:base"
import "camp:diagnostics"

@(test)
test_collector_add_warning :: proc(t: ^testing.T) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	diagnostics.collector_add_diag(&collector, diagnostics.diag_init(.Warning, "TEST", base.Source_Span_ZERO, "unused variable"))
	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 0)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&collector))
}

@(test)
test_collector_add_error :: proc(t: ^testing.T) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	diagnostics.collector_add_diag(&collector, diagnostics.diag_init(.Error, "TEST", base.Source_Span_ZERO, "type mismatch"))
	testing.expect(t, collector.warning_count == 0)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, diagnostics.diag_collector_has_errors(&collector))
}

@(test)
test_collector_add_internal :: proc(t: ^testing.T) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	diagnostics.collector_add_diag(&collector, diagnostics.diag_init(.Internal, "TEST", base.Source_Span_ZERO, "impossible type after typecheck"))
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, diagnostics.diag_collector_has_errors(&collector))
}

@(test)
test_intern_same_string :: proc(t: ^testing.T) {
	table: base.Intern_Table
	base.intern_init(&table)
	defer base.intern_destroy(&table)

	id1 := base.intern(&table, "hello")
	id2 := base.intern(&table, "hello")
	testing.expect(t, id1 == id2)
}

@(test)
test_intern_different_strings :: proc(t: ^testing.T) {
	table: base.Intern_Table
	base.intern_init(&table)
	defer base.intern_destroy(&table)

	id1 := base.intern(&table, "hello")
	id2 := base.intern(&table, "world")
	testing.expect(t, id1 != id2)
}

@(test)
test_intern_roundtrip :: proc(t: ^testing.T) {
	table: base.Intern_Table
	base.intern_init(&table)
	defer base.intern_destroy(&table)

	id := base.intern(&table, "test_string")
	testing.expect(t, base.intern_get(&table, id) == "test_string")
}

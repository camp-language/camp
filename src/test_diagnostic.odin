package camp

import "core:testing"
import "camp:base"
import "camp:diagnostics"

@(test)
test_diag_unexpected_char :: proc(t: ^testing.T) {
	d := diagnostics.diag_unexpected_char('@', base.Source_Span{file_id = 0, start = 4, end = 5})
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNEXPECTED CHARACTER")
	testing.expect(t, len(d.hints) == 0)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_unterminated_string :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 5}
	d := diagnostics.diag_unterminated_string(span)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNTERMINATED STRING")
}

@(test)
test_diag_undefined_name_with_hint :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 3}
	d := diagnostics.diag_undefined_name("foo", []string{"bar"}, span)
	testing.expect(t, d.title == "UNDEFINED NAME")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_undefined_name_no_hint :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 3}
	d := diagnostics.diag_undefined_name("foo", nil, span)
	testing.expect(t, len(d.hints) == 0)
}

@(test)
test_diag_type_mismatch_multi_span :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 3}
	span_b := base.Source_Span{file_id = 0, start = 10, end = 13}
	d := diagnostics.diag_type_mismatch("I64", "String", span_a, span_b)
	testing.expect(t, d.title == "TYPE MISMATCH")
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_diag_type_mismatch_no_secondary :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 3}
	d := diagnostics.diag_type_mismatch("I64", "String", span_a, base.Source_Span_ZERO)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_effectful_naming :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 5}
	d := diagnostics.diag_effectful_naming("main", "{IO}", span)
	testing.expect(t, d.title == "EFFECTFUL FUNCTION NAMING")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_warning :: proc(t: ^testing.T) {
	d := diagnostics.diag_init(.Warning, "UNUSED VARIABLE", base.Source_Span_ZERO, "x is unused")
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "UNUSED VARIABLE")
}

@(test)
test_diag_internal :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 1}
	d := diagnostics.diag_internal("impossible type", span)
	testing.expect(t, d.category == .Internal)
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_span_to_line_col :: proc(t: ^testing.T) {
	source := "abc\ndef\nghi"
	span := base.Source_Span{file_id = 0, start = 4, end = 7}
	line, col := diagnostics.diag_span_to_line_col(source, span)
	testing.expect(t, line == 2)
	testing.expect(t, col == 1)
}

@(test)
test_diag_char_display :: proc(t: ^testing.T) {
	testing.expect(t, diagnostics.char_display('\n') == "\\n")
	testing.expect(t, diagnostics.char_display(' ') == "space")
	testing.expect(t, diagnostics.char_display('a') == "a")
}

@(test)
test_diag_plural_s :: proc(t: ^testing.T) {
	testing.expect(t, diagnostics.plural_s(1) == "")
	testing.expect(t, diagnostics.plural_s(0) == "s")
	testing.expect(t, diagnostics.plural_s(2) == "s")
}

@(test)
test_diag_collector :: proc(t: ^testing.T) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	diagnostics.collector_add_diag(&collector, diagnostics.diag_init(.Warning, "TEST", base.Source_Span_ZERO, "warn"))
	diagnostics.collector_add_diag(&collector, diagnostics.diag_init(.Error, "TEST", base.Source_Span_ZERO, "err"))
	diagnostics.collector_add_diag(&collector, diagnostics.diag_internal("bug", base.Source_Span_ZERO))

	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, diagnostics.diag_collector_has_errors(&collector))
	testing.expect(t, len(collector.diagnostics) == 3)
}

@(test)
test_diag_arity_mismatch :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 3}
	span_b := base.Source_Span{file_id = 0, start = 10, end = 13}
	d := diagnostics.diag_arity_mismatch(2, 1, span_a, span_b)
	testing.expect(t, d.title == "ARITY MISMATCH")
	testing.expect(t, len(d.labels) == 1)
}

@(test)
test_diag_unknown_command :: proc(t: ^testing.T) {
	d := diagnostics.diag_unknown_command("foo")
	testing.expect(t, d.title == "UNKNOWN COMMAND")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_invalid_extension :: proc(t: ^testing.T) {
	d := diagnostics.diag_invalid_extension("test.txt", ".txt")
	testing.expect(t, d.title == "INVALID FILE EXTENSION")
	testing.expect(t, d.span == base.Source_Span_ZERO)
}

@(test)
test_diag_file_not_found :: proc(t: ^testing.T) {
	d := diagnostics.diag_file_not_found("/no.camp", "No such file")
	testing.expect(t, d.title == "FILE NOT FOUND")
	testing.expect(t, d.span == base.Source_Span_ZERO)
}


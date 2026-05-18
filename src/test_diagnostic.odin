package camp

import "core:testing"

@(test)
test_diag_unexpected_char :: proc(t: ^testing.T) {
	d := diag_unexpected_char('@', Source_Span{file_id = 0, start = 4, end = 5})
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNEXPECTED CHARACTER")
	testing.expect(t, len(d.hints) == 0)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_unterminated_string :: proc(t: ^testing.T) {
	span := Source_Span{file_id = 0, start = 0, end = 5}
	d := diag_unterminated_string(span)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNTERMINATED STRING")
}

@(test)
test_diag_undefined_name_with_hint :: proc(t: ^testing.T) {
	span := Source_Span{file_id = 0, start = 0, end = 3}
	d := diag_undefined_name("foo", []string{"bar"}, span)
	testing.expect(t, d.title == "UNDEFINED NAME")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_undefined_name_no_hint :: proc(t: ^testing.T) {
	span := Source_Span{file_id = 0, start = 0, end = 3}
	d := diag_undefined_name("foo", nil, span)
	testing.expect(t, len(d.hints) == 0)
}

@(test)
test_diag_type_mismatch_multi_span :: proc(t: ^testing.T) {
	span_a := Source_Span{file_id = 0, start = 0, end = 3}
	span_b := Source_Span{file_id = 0, start = 10, end = 13}
	d := diag_type_mismatch("I64", "String", span_a, span_b)
	testing.expect(t, d.title == "TYPE MISMATCH")
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_diag_type_mismatch_no_secondary :: proc(t: ^testing.T) {
	span_a := Source_Span{file_id = 0, start = 0, end = 3}
	d := diag_type_mismatch("I64", "String", span_a, Source_Span_ZERO)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_effectful_naming :: proc(t: ^testing.T) {
	span := Source_Span{file_id = 0, start = 0, end = 5}
	d := diag_effectful_naming("main", "{IO}", span)
	testing.expect(t, d.title == "EFFECTFUL FUNCTION NAMING")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_warning :: proc(t: ^testing.T) {
	d := diag_init(.Warning, "UNUSED VARIABLE", Source_Span_ZERO, "x is unused")
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "UNUSED VARIABLE")
}

@(test)
test_diag_internal :: proc(t: ^testing.T) {
	span := Source_Span{file_id = 0, start = 0, end = 1}
	d := diag_internal("impossible type", span)
	testing.expect(t, d.category == .Internal)
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_span_to_line_col :: proc(t: ^testing.T) {
	source := "abc\ndef\nghi"
	span := Source_Span{file_id = 0, start = 4, end = 7}
	line, col := diag_span_to_line_col(source, span)
	testing.expect(t, line == 2)
	testing.expect(t, col == 1)
}

@(test)
test_diag_char_display :: proc(t: ^testing.T) {
	testing.expect(t, char_display('\n') == "\\n")
	testing.expect(t, char_display(' ') == "space")
	testing.expect(t, char_display('a') == "a")
}

@(test)
test_diag_plural_s :: proc(t: ^testing.T) {
	testing.expect(t, plural_s(1) == "")
	testing.expect(t, plural_s(0) == "s")
	testing.expect(t, plural_s(2) == "s")
}

@(test)
test_diag_collector :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	collector_add_diag(&collector, diag_init(.Warning, "TEST", Source_Span_ZERO, "warn"))
	collector_add_diag(&collector, diag_init(.Error, "TEST", Source_Span_ZERO, "err"))
	collector_add_diag(&collector, diag_internal("bug", Source_Span_ZERO))

	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, diag_collector_has_errors(&collector))
	testing.expect(t, len(collector.diagnostics) == 3)
}

@(test)
test_diag_arity_mismatch :: proc(t: ^testing.T) {
	span_a := Source_Span{file_id = 0, start = 0, end = 3}
	span_b := Source_Span{file_id = 0, start = 10, end = 13}
	d := diag_arity_mismatch(2, 1, span_a, span_b)
	testing.expect(t, d.title == "ARITY MISMATCH")
	testing.expect(t, len(d.labels) == 1)
}

@(test)
test_diag_unknown_command :: proc(t: ^testing.T) {
	d := diag_unknown_command("foo")
	testing.expect(t, d.title == "UNKNOWN COMMAND")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_invalid_extension :: proc(t: ^testing.T) {
	d := diag_invalid_extension("test.txt", ".txt")
	testing.expect(t, d.title == "INVALID FILE EXTENSION")
	testing.expect(t, d.span == Source_Span_ZERO)
}

@(test)
test_diag_file_not_found :: proc(t: ^testing.T) {
	d := diag_file_not_found("/no.camp", "No such file")
	testing.expect(t, d.title == "FILE NOT FOUND")
	testing.expect(t, d.span == Source_Span_ZERO)
}

@(test)
test_levenshtein_distance :: proc(t: ^testing.T) {
	testing.expect(t, levenshtein_distance("", "") == 0)
	testing.expect(t, levenshtein_distance("abc", "") == 3)
	testing.expect(t, levenshtein_distance("", "abc") == 3)
	testing.expect(t, levenshtein_distance("kitten", "sitting") == 3)
	testing.expect(t, levenshtein_distance("foo", "bar") == 3)
	testing.expect(t, levenshtein_distance("foo", "foo") == 0)
	testing.expect(t, levenshtein_distance("add", "add!") == 1)
}

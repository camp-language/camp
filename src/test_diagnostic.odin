package camp

import "camp:base"
import "camp:diagnostics"
import "core:testing"

@(test)
test_diag_unexpected_char :: proc(t: ^testing.T) {
	d := diagnostics.diag_unexpected_char('@', base.Source_Span{file_id = 0, start = 4, end = 5})
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNEXPECTED CHARACTER")
	testing.expect(t, len(d.hints) == 0)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_unterminated_string :: proc(t: ^testing.T) {
	span := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 5,
	}
	d := diagnostics.diag_unterminated_string(span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNTERMINATED STRING")
}

@(test)
test_diag_undefined_name_with_hint :: proc(t: ^testing.T) {
	span := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 3,
	}
	d := diagnostics.diag_undefined_name("foo", []string{"bar"}, span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "UNDEFINED NAME")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_undefined_name_no_hint :: proc(t: ^testing.T) {
	span := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 3,
	}
	d := diagnostics.diag_undefined_name("foo", nil, span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, len(d.hints) == 0)
}

@(test)
test_diag_type_mismatch_multi_span :: proc(t: ^testing.T) {
	span_a := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 3,
	}
	span_b := base.Source_Span {
		file_id = 0,
		start   = 10,
		end     = 13,
	}
	d := diagnostics.diag_type_mismatch("I64", "String", span_a, span_b)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "TYPE MISMATCH")
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_diag_type_mismatch_no_secondary :: proc(t: ^testing.T) {
	span_a := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 3,
	}
	d := diagnostics.diag_type_mismatch("I64", "String", span_a, base.Source_Span_ZERO)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_effectful_naming :: proc(t: ^testing.T) {
	span := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 5,
	}
	d := diagnostics.diag_effectful_naming("main", "{IO}", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "EFFECTFUL FUNCTION NAMING")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_warning :: proc(t: ^testing.T) {
	d := diagnostics.diag_init(
		.Warning,
		"C0900",
		"UNUSED VARIABLE",
		base.Source_Span_ZERO,
		"x is unused",
	)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "UNUSED VARIABLE")
}

@(test)
test_diag_internal :: proc(t: ^testing.T) {
	span := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 1,
	}
	d := diagnostics.diag_internal("impossible type", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Internal)
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_span_to_line_col :: proc(t: ^testing.T) {
	source := "abc\ndef\nghi"
	span := base.Source_Span {
		file_id = 0,
		start   = 4,
		end     = 7,
	}
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

	diagnostics.collector_add_diag(
		&collector,
		diagnostics.diag_init(.Warning, "C0000", "TEST", base.Source_Span_ZERO, "warn"),
	)
	diagnostics.collector_add_diag(
		&collector,
		diagnostics.diag_init(.Error, "C0000", "TEST", base.Source_Span_ZERO, "err"),
	)
	diagnostics.collector_add_diag(
		&collector,
		diagnostics.diag_internal("bug", base.Source_Span_ZERO),
	)

	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, diagnostics.diag_collector_has_errors(&collector))
	testing.expect(t, len(collector.diagnostics) == 3)
}

@(test)
test_diag_arity_mismatch :: proc(t: ^testing.T) {
	span_a := base.Source_Span {
		file_id = 0,
		start   = 0,
		end     = 3,
	}
	span_b := base.Source_Span {
		file_id = 0,
		start   = 10,
		end     = 13,
	}
	d := diagnostics.diag_arity_mismatch(2, 1, span_a, span_b)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "ARITY MISMATCH")
	testing.expect(t, len(d.labels) == 1)
}

@(test)
test_diag_unknown_command :: proc(t: ^testing.T) {
	d := diagnostics.diag_unknown_command("foo")
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "UNKNOWN COMMAND")
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_diag_invalid_extension :: proc(t: ^testing.T) {
	d := diagnostics.diag_invalid_extension("test.txt", ".txt")
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "INVALID FILE EXTENSION")
	testing.expect(t, d.span == base.Source_Span_ZERO)
}

@(test)
test_diag_file_not_found :: proc(t: ^testing.T) {
	d := diagnostics.diag_file_not_found("/no.camp", "No such file")
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.title == "FILE NOT FOUND")
	testing.expect(t, d.span == base.Source_Span_ZERO)
}

@(test)
test_diag_expected_token :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 5, end = 8}
	tok := base.Token{
		kind = .Identifier,
		text = "foo",
		span = span,
	}
	d := diagnostics.diag_expected_token(.Kw_If, tok, span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "SYNTAX ERROR")
	testing.expect(t, d.code == "C0100")
	testing.expect(t, d.span == span)
}

@(test)
test_diag_unexpected_token :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 3, end = 4}
	tok := base.Token{
		kind = .Pipe,
		text = "|",
		span = span,
	}
	d := diagnostics.diag_unexpected_token(tok)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "SYNTAX ERROR")
	testing.expect(t, d.code == "C0101")
	testing.expect(t, d.span == span)
	testing.expect(t, len(d.hints) >= 1)
}

@(test)
test_diag_expected_type :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 10, end = 15}
	tok := base.Token{
		kind = .Int_Literal,
		text = "42",
		span = span,
	}
	d := diagnostics.diag_expected_type(tok, span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "SYNTAX ERROR")
	testing.expect(t, d.code == "C0102")
	testing.expect(t, d.span == span)
}

@(test)
test_diag_unhandled_effect :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 10}
	d := diagnostics.diag_unhandled_effect("Console", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNHANDLED EFFECT")
	testing.expect(t, d.code == "C0401")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.span == span)
}

@(test)
test_diag_primitive_mismatch :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 3}
	span_b := base.Source_Span{file_id = 0, start = 10, end = 15}
	d := diagnostics.diag_primitive_mismatch("I64", "String", span_a, span_b)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "TYPE MISMATCH")
	testing.expect(t, d.code == "C0301")
	testing.expect(t, d.span == span_a)
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_diag_primitive_mismatch_no_secondary :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 3}
	d := diagnostics.diag_primitive_mismatch("I64", "String", span_a, base.Source_Span_ZERO)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_infinite_type :: proc(t: ^testing.T) {
	span_a := base.Source_Span{file_id = 0, start = 0, end = 10}
	span_b := base.Source_Span{file_id = 0, start = 20, end = 25}
	d := diagnostics.diag_infinite_type("List", span_a, span_b)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "INFINITE TYPE")
	testing.expect(t, d.code == "C0303")
	testing.expect(t, d.span == span_a)
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_diag_infinite_type_no_secondary :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 10}
	d := diagnostics.diag_infinite_type("List", span, base.Source_Span_ZERO)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, len(d.labels) == 0)
}

@(test)
test_diag_module_not_found :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 7, end = 20}
	d := diagnostics.diag_module_not_found("io", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "MODULE NOT FOUND")
	testing.expect(t, d.code == "C0800")
	testing.expect(t, d.span == span)
}

@(test)
test_diag_cyclic_dependency :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 5}
	d := diagnostics.diag_cyclic_dependency("A -> B -> C -> A", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "CYCLIC DEPENDENCY")
	testing.expect(t, d.code == "C0801")
	testing.expect(t, d.span == span)
}

@(test)
test_diag_entry_point_not_found :: proc(t: ^testing.T) {
	d := diagnostics.diag_entry_point_not_found()
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "ENTRY POINT NOT FOUND")
	testing.expect(t, d.code == "C0805")
	testing.expect(t, d.span == base.Source_Span_ZERO)
}

@(test)
test_diag_unjoined_spawn :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 5, end = 15}
	d := diagnostics.diag_unjoined_spawn(span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "UNJOINED SPAWN")
	testing.expect(t, d.code == "C0905")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.span == span)
}

@(test)
test_diag_redundant_pattern :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 10, end = 20}
	d := diagnostics.diag_redundant_pattern(span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "REDUNDANT PATTERN")
	testing.expect(t, d.code == "C0503")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.span == span)
}

@(test)
test_diag_non_exhaustive_bool :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 20}
	d := diagnostics.diag_non_exhaustive_bool("false", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "NON-EXHAUSTIVE MATCH")
	testing.expect(t, d.code == "C0500")
	testing.expect(t, d.span == span)
}

@(test)
test_diag_shadow :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 3}
	shadow_id := base.Intern_ID(42)
	d := diagnostics.diag_shadow(shadow_id, "x", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "SHADOWING")
	testing.expect(t, d.code == "C0201")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.shadowed_name == shadow_id)
	testing.expect(t, d.span == span)
}

@(test)
test_diag_unused_binding :: proc(t: ^testing.T) {
	span := base.Source_Span{file_id = 0, start = 0, end = 3}
	d := diagnostics.diag_unused_binding("x", "Use _x to suppress", span)
	defer diagnostics.diag_destroy(&d)
	testing.expect(t, d.category == .Warning)
	testing.expect(t, d.title == "UNUSED BINDING")
	testing.expect(t, d.code == "C0900")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.span == span)
}


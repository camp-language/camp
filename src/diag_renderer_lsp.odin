package camp

import "core:fmt"

LSP_Position :: struct {
	line:      uint,
	character: uint,
}

LSP_Range :: struct {
	start: LSP_Position,
	end:   LSP_Position,
}

LSP_Location :: struct {
	uri:   string,
	range: LSP_Range,
}

LSP_DiagnosticSeverity :: enum int {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

LSP_DiagnosticRelatedInfo :: struct {
	location: LSP_Location,
	message:  string,
}

LSP_Diagnostic :: struct {
	range:    LSP_Range,
	severity: LSP_DiagnosticSeverity,
	message:  string,
	related:  [dynamic]LSP_DiagnosticRelatedInfo,
}

lsp_from_diagnostic :: proc(d: Diagnostic, source: string, uri: string) -> LSP_Diagnostic {
	line, col := diag_span_to_line_col(source, d.span)
	end_line, end_col := span_end_to_line_col(source, d.span)
	result: LSP_Diagnostic
	result.range.start = LSP_Position{line = uint(line - 1), character = uint(col - 1)}
	result.range.end = LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)}
	switch d.category {
	case .Error:    result.severity = .Error
	case .Warning:  result.severity = .Warning
	case .Internal: result.severity = .Error
	}
	msg := d.message
	for hint in d.hints {
		msg = fmt.tprintf("{}\n\n{}", msg, hint)
	}
	result.message = msg
	result.related = make([dynamic]LSP_DiagnosticRelatedInfo, 0, len(d.labels))
	for label in d.labels {
		ll, lc := diag_span_to_line_col(source, label.span)
		el, ec := span_end_to_line_col(source, label.span)
		append(&result.related, LSP_DiagnosticRelatedInfo{
			location = LSP_Location{
				uri = uri,
				range = LSP_Range{
					start = LSP_Position{line = uint(ll - 1), character = uint(lc - 1)},
					end   = LSP_Position{line = uint(el - 1), character = uint(ec - 1)},
				},
			},
			message = label.label,
		})
	}
	return result
}

span_end_to_line_col :: proc(source: string, span: Source_Span) -> (int, int) {
	line := 1
	col := 1
	for i in 0..<span.end {
		if i >= len(source) { break }
		if source[i] == '\n' {
			line += 1
			col = 1
		} else {
			col += 1
		}
	}
	return line, col
}

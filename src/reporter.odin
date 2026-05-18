package camp

import "core:fmt"

report_error :: proc(collector: ^Error_Collector, file_path: string, source: string, error: Error) {
	line, col := span_to_line_col(source, error.span)

	prefix: string
	switch error.category {
	case .Warning:  prefix = "warning"
	case .Error:    prefix = "error"
	case .Internal: prefix = "internal error"
	}

	fmt.printfln("{}:{}:{}: {}: {}", file_path, line, col, prefix, error.message)
}

span_to_line_col :: proc(source: string, span: Source_Span) -> (int, int) {
	line := 1
	col := 1
	for i in 0..<span.start {
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

package diagnostics

import "camp:base"

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

ANSI_RESET :: "\x1b[0m"
ANSI_BOLD_RED :: "\x1b[1;31m"
ANSI_BOLD_YELLOW :: "\x1b[1;33m"
ANSI_BOLD_MAGENTA :: "\x1b[1;35m"
ANSI_DIM :: "\x1b[2m"
ANSI_UNDERLINE :: "\x1b[4m"
ANSI_CYAN :: "\x1b[36m"
ANSI_GREEN :: "\x1b[32m"

is_color_tty :: proc() -> bool {
	no_color_val := os.get_env("NO_COLOR", context.allocator)
	defer delete(no_color_val, context.allocator)
	if no_color_val != "" do return false
	if os.is_tty(os.stderr) do return true
	return false
}

Color_Scheme :: struct {
	header_title:   string,
	header_dash:     string,
	file_path:       string,
	primary_caret:   string,
	secondary_tilde: string,
	hint_text:       string,
	line_number:     string,
	reset:           string,
}

no_color_scheme :: Color_Scheme{}

color_scheme_for :: proc(category: Diagnostic_Category, use_color: bool) -> Color_Scheme {
	if !use_color do return no_color_scheme
	switch category {
	case .Error:
		return Color_Scheme{
			header_title = ANSI_BOLD_RED,
			header_dash = ANSI_DIM,
			file_path = ANSI_UNDERLINE,
			primary_caret = ANSI_BOLD_RED,
			secondary_tilde = ANSI_CYAN,
			hint_text = ANSI_GREEN,
			line_number = ANSI_DIM,
			reset = ANSI_RESET,
		}
	case .Warning:
		return Color_Scheme{
			header_title = ANSI_BOLD_YELLOW,
			header_dash = ANSI_DIM,
			file_path = ANSI_UNDERLINE,
			primary_caret = ANSI_BOLD_YELLOW,
			secondary_tilde = ANSI_CYAN,
			hint_text = ANSI_GREEN,
			line_number = ANSI_DIM,
			reset = ANSI_RESET,
		}
	case .Internal:
		return Color_Scheme{
			header_title = ANSI_BOLD_MAGENTA,
			header_dash = ANSI_DIM,
			file_path = ANSI_UNDERLINE,
			primary_caret = ANSI_BOLD_MAGENTA,
			secondary_tilde = ANSI_CYAN,
			hint_text = ANSI_GREEN,
			line_number = ANSI_DIM,
			reset = ANSI_RESET,
		}
	}
	return no_color_scheme
}

render_all :: proc(collector: ^Diagnostic_Collector, file_path: string, source: string) {
	use_color := is_color_tty()
	for d, i in collector.diagnostics {
		if i > 0 do fmt.println()
		render_diagnostic(d, file_path, source, use_color)
	}
	if diag_collector_has_errors(collector) {
		total := collector.error_count + collector.internal_count
		fmt.printfln("compilation failed with {} error(s)", total)
	} else if collector.warning_count > 0 {
		fmt.printfln("{} warning(s) found", collector.warning_count)
	}
}

render_diagnostic :: proc(d: Diagnostic, file_path: string, source: string, use_color: bool) {
	colors := color_scheme_for(d.category, use_color)

	render_header(d.code, d.title, file_path, colors)
	fmt.println()

	message := word_wrap(d.message, 80)
	fmt.println(message)

	if d.span.file_id >= 0 {
		render_snippet(source, d.span, "^", "", colors, colors.primary_caret)
	}

	for label in d.labels {
		if label.span.file_id >= 0 {
			render_snippet(source, label.span, "~", label.label, colors, colors.secondary_tilde)
		}
	}

	for hint in d.hints {
		fmt.print(colors.hint_text)
		fmt.printfln("  {}", hint)
		fmt.print(colors.reset)
	}
}

render_header :: proc(code: string, title: string, file_path: string, colors: Color_Scheme) {
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, 256)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, colors.header_dash)
	strings.write_string(&builder, "-- ")
	strings.write_string(&builder, colors.header_title)
	if len(code) > 0 {
		strings.write_string(&builder, code)
		strings.write_string(&builder, ": ")
	}
	strings.write_string(&builder, title)
	strings.write_string(&builder, colors.header_dash)

	content_len := 3 + len(code) + 2 + len(title) + 1 + len(file_path)
	dash_count := 60 - content_len
	if dash_count < 3 do dash_count = 3

	strings.write_rune(&builder, ' ')
	for i in 0..<dash_count {
		strings.write_rune(&builder, '-')
	}
	strings.write_rune(&builder, ' ')
	strings.write_string(&builder, colors.file_path)
	strings.write_string(&builder, file_path)
	strings.write_string(&builder, colors.reset)

	fmt.println(strings.to_string(builder))
}

diag_span_to_line_col :: proc(source: string, span: base.Source_Span) -> (int, int) {
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

get_source_line :: proc(source: string, line_num: int) -> string {
	current_line := 1
	line_start := 0
	found := false
	for i in 0..<len(source) {
		if current_line == line_num {
			line_start = i
			found = true
			break
		}
		if source[i] == '\n' {
			current_line += 1
		}
	}
	if !found do return ""
	end := line_start
	for end < len(source) && source[end] != '\n' {
		end += 1
	}
	return source[line_start:end]
}

render_snippet :: proc(source: string, span: base.Source_Span, marker: string, label: string, colors: Color_Scheme, marker_color: string) {
	line, col := diag_span_to_line_col(source, span)
	line_text := get_source_line(source, line)

	gutter_width := 4
	if line >= 1000 do gutter_width = 6
	else if line >= 100 do gutter_width = 5

	line_num_str := fmt.tprintf("{}", line)
	padding := gutter_width - len(line_num_str)
	fmt.print(colors.line_number)
	for i in 0..<padding {
		fmt.print(" ")
	}
	fmt.print(line_num_str)
	fmt.print(colors.reset)
	fmt.print(" | ")
	fmt.println(line_text)

	span_len := span.end - span.start
	if span_len < 1 do span_len = 1

	fmt.print(char_repeat(" ", gutter_width + 3 + col - 1))
	fmt.print(marker_color)
	for i in 0..<span_len {
		fmt.print(marker)
	}
	if len(label) > 0 {
		fmt.print(" ")
		fmt.print(label)
	}
	fmt.println(colors.reset)
}

char_repeat :: proc(s: string, count: int) -> string {
	if count <= 0 do return ""
	result := make([]u8, count)
	for i in 0..<count {
		result[i] = s[0]
	}
	return string(result)
}

word_wrap :: proc(text: string, width: int) -> string {
	if len(text) <= width do return text
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, len(text) + 32)

	line_len := 0
	word_start := 0
	for i in 0..<len(text) + 1 {
		if i == len(text) || text[i] == ' ' {
			word := text[word_start:i]
			if line_len + len(word) + 1 > width && line_len > 0 {
				strings.write_rune(&builder, '\n')
				line_len = 0
			} else if line_len > 0 {
				strings.write_rune(&builder, ' ')
				line_len += 1
			}
			strings.write_string(&builder, word)
			line_len += len(word)
			word_start = i + 1
		}
	}

	return strings.to_string(builder)
}

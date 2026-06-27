#+feature dynamic-literals
package frontend

import "base:intrinsics"
import "camp:base"
import "camp:diagnostics"
import "core:fmt"
import "core:simd"
import "core:strconv"

KEYWORDS: map[string]base.Token_Kind = {
	"if"      = .Kw_If,
	"else"    = .Kw_Else,
	"match"   = .Kw_Match,
	"is"      = .Kw_Is,
	"derives" = .Kw_Derives,
	"handle"  = .Kw_Handle,
	"in"      = .Kw_In,
	"with"    = .Kw_With,
	"import"  = .Kw_Import,
	"as"      = .Kw_As,
	"for"     = .Kw_For,
	"and"     = .Kw_And,
	"or"      = .Kw_Or,
	"expect"  = .Kw_Expect,
	"test"    = .Kw_Test,
	"not"     = .Kw_Not,
	"pub"     = .Kw_Pub,
	"Self"    = .Kw_Self,
	"par"     = .Kw_Par,
	"where"   = .Kw_Where,
	"return"  = .Kw_Return,
	"crash"   = .Kw_Crash,
	"todo"    = .Kw_Todo,
	"deps"    = .Kw_Deps,
}

Lexer :: struct {
	source:          string,
	pos:             int,
	collector:       ^diagnostics.Diagnostic_Collector,
	intern:          ^base.Intern_Table,
	file_id:         int,
	at_line_start:   bool,
	shebang_skipped: bool,
	saw_blank_line:  bool,
}

lexer_init :: proc(
	l: ^Lexer,
	file: base.Source_File,
	collector: ^diagnostics.Diagnostic_Collector,
	table: ^base.Intern_Table,
) {
	l.source = file.contents
	l.pos = 0
	l.collector = collector
	l.intern = table
	l.file_id = file.id
	l.shebang_skipped = false
	l.at_line_start = true
}

lexer_peek :: proc(l: ^Lexer) -> u8 {
	if l.pos >= len(l.source) {return 0}
	return l.source[l.pos]
}

lexer_advance :: proc(l: ^Lexer) -> u8 {
	if l.pos >= len(l.source) {return 0}
	ch := l.source[l.pos]
	l.pos += 1
	return ch
}

lexer_skip_whitespace :: proc(l: ^Lexer) {
	when simd.HAS_HARDWARE_SIMD {
		lexer_skip_whitespace_simd(l)
	}
	lexer_skip_whitespace_scalar(l)
}

when simd.HAS_HARDWARE_SIMD {

	lexer_skip_whitespace_simd :: proc(l: ^Lexer) {
		source_len := len(l.source)
		for l.pos + 16 <= source_len {
			chunk := load_chunk(l.source, l.pos)
			ws_bits := extract_mask(is_whitespace_simd(chunk))
			nl_bits := extract_mask(is_newline_simd(chunk))
			all_ws_bits := ws_bits | nl_bits

			not_ws_bits := ~all_ws_bits
			if not_ws_bits == 0 {
				// All 16 bytes are whitespace
				if nl_bits != 0 {l.at_line_start = true}
				l.pos += 16
				continue
			}

			// Found non-whitespace within this chunk
			first_non_ws := int(intrinsics.count_trailing_zeros(not_ws_bits))
			prefix_mask := u16(1 << u16(first_non_ws)) - 1
			if (nl_bits & prefix_mask) != 0 {l.at_line_start = true}
			l.pos += first_non_ws
			// Check for // or //# comments (but not /// doc comments) - if found, skip to end of line and continue
			if l.source[l.pos] == '/' &&
			   l.pos + 1 < source_len &&
			   (l.source[l.pos + 1] == '/' || l.source[l.pos + 1] == '#') {
				// Don't skip /// doc comments (they're handled in lexer_next)
				is_doc_comment :=
					l.pos + 2 < source_len &&
					l.source[l.pos + 1] == '/' &&
					l.source[l.pos + 2] == '/'
				if !is_doc_comment {
					for l.pos < source_len && l.source[l.pos] != '\n' {
						l.pos += 1
					}
					l.at_line_start = true
					continue
				}
			}

			return
		}
	}

}

lexer_skip_whitespace_scalar :: proc(l: ^Lexer) {
	prev_was_newline := false
	for l.pos < len(l.source) {
		ch := l.source[l.pos]
		if ch == ' ' || ch == '\t' || ch == '\r' {
			l.pos += 1
			prev_was_newline = false
		} else if ch == '\n' {
			if prev_was_newline {
				l.saw_blank_line = true
			}
			prev_was_newline = true
			l.pos += 1
			l.at_line_start = true
		} else if ch == '/' &&
		   l.pos + 2 < len(l.source) &&
		   l.source[l.pos + 1] == '/' &&
		   l.source[l.pos + 2] == '/' {
			break
		} else if ch == '/' &&
		   l.pos + 2 < len(l.source) &&
		   l.source[l.pos + 1] == '/' &&
		   l.source[l.pos + 2] == '#' {
			break
		} else if ch == '/' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '/' {
			l.pos += 2
			prev_was_newline = false
			for l.pos < len(l.source) && l.source[l.pos] != '\n' {
				l.pos += 1
			}
		} else if ch == '\\' && l.at_line_start {
			break
		} else {
			l.at_line_start = false
			prev_was_newline = false
			break
		}
	}
}

lexer_had_blank_line :: proc(l: ^Lexer) -> bool {
	result := l.saw_blank_line
	l.saw_blank_line = false
	return result
}

lexer_make_span :: proc(l: ^Lexer, start: int) -> base.Source_Span {
	return base.Source_Span{file_id = l.file_id, start = start, end = l.pos}
}

lexer_make_token :: proc(
	l: ^Lexer,
	kind: base.Token_Kind,
	start: int,
	text: string,
) -> base.Token {
	return base.Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

lexer_next :: proc(l: ^Lexer) -> base.Token {
	lexer_skip_whitespace(l)

	if l.pos >= len(l.source) {
		return base.Token{kind = .Eof, span = lexer_make_span(l, l.pos)}
	}

	// Skip shebang line (#!) at file start
	if !l.shebang_skipped && l.pos == 0 {
		l.shebang_skipped = true
		if l.pos + 1 < len(l.source) && l.source[0] == '#' && l.source[1] == '!' {
			for l.pos < len(l.source) && l.source[l.pos] != '\n' {l.pos += 1}
			if l.pos < len(l.source) {l.pos += 1} 	// skip newline
			l.at_line_start = true
			return lexer_next(l)
		}
	}

	start := l.pos
	ch := l.source[l.pos]

	// /// doc comment
	if ch == '/' &&
	   l.pos + 2 < len(l.source) &&
	   l.source[l.pos + 1] == '/' &&
	   l.source[l.pos + 2] == '/' {
		l.pos += 3
		if l.pos < len(l.source) && l.source[l.pos] == ' ' {
			l.pos += 1
		}
		content_start := l.pos
		for l.pos < len(l.source) && l.source[l.pos] != '\n' {
			l.pos += 1
		}
		return lexer_make_token(l, .Doc_Comment, start, l.source[content_start:l.pos])
	}

	// //# hidden line in doc code block
	if ch == '/' &&
	   l.pos + 2 < len(l.source) &&
	   l.source[l.pos + 1] == '/' &&
	   l.source[l.pos + 2] == '#' {
		l.pos += 3
		if l.pos < len(l.source) && l.source[l.pos] == ' ' {
			l.pos += 1
		}
		content_start := l.pos
		for l.pos < len(l.source) && l.source[l.pos] != '\n' {
			l.pos += 1
		}
		return lexer_make_token(l, .Hidden_Line, start, l.source[content_start:l.pos])
	}

	// \ per-line string prefix (only at line start, and only if followed by content)
	if ch == '\\' && l.at_line_start {
		// Lookahead: if \ is followed by a newline or EOF, it's a line-continuation backslash
		// If followed by content (space + text, or text directly), it's a per-line string
		lookahead := l.pos + 1
		// Skip optional space after \
		if lookahead < len(l.source) && l.source[lookahead] == ' ' {
			lookahead += 1
		}
		if lookahead < len(l.source) &&
		   l.source[lookahead] != '\n' &&
		   l.source[lookahead] != '\r' {
			// Content after \ — this is a per-line string
			return lexer_lex_perline_string(l, start)
		}
		// Otherwise fall through to normal \ token handling
	}

	if ch >= '0' && ch <= '9' {
		return lexer_lex_number(l, start)
	}

	if ch == '"' {
		return lexer_lex_string(l, start)
	}

	if ch == '\'' {
		return lexer_lex_char(l, start)
	}

	if ch == '$' {
		l.pos += 1
		return lexer_make_token(l, .Dollar, start, l.source[start:l.pos])
	}

	if ch == '`' {
		l.pos += 1
		for l.pos < len(l.source) && l.source[l.pos] != '`' {
			l.pos += 1
		}
		if l.pos >= len(l.source) {
			diagnostics.collector_add_diag(
				l.collector,
				diagnostics.diag_unexpected_char('`', lexer_make_span(l, start)),
			)
			return lexer_next(l)
		}
		l.pos += 1 // skip closing backtick
		// Extract the identifier text without the backticks
		inner_text := l.source[start + 1:l.pos - 1]
		// Return as a regular Identifier token
		return base.Token{kind = .Identifier, text = inner_text, span = lexer_make_span(l, start)}
	}

	if is_identifier_start(ch) {
		return lexer_lex_identifier(l, start)
	}

	if ch == '-' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '>' {
			l.pos += 1
			return lexer_make_token(l, .Arrow, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Minus, start, l.source[start:l.pos])
	}

	if ch == '=' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '=' {
			l.pos += 1
			return lexer_make_token(l, .Eq_Eq, start, l.source[start:l.pos])
		}
		if l.pos < len(l.source) && l.source[l.pos] == '>' {
			l.pos += 1
			return lexer_make_token(l, .Fat_Arrow, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Eq, start, l.source[start:l.pos])
	}

	if ch == '<' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '=' {
			l.pos += 1
			return lexer_make_token(l, .Lt_Eq, start, l.source[start:l.pos])
		}
		if l.pos < len(l.source) && l.source[l.pos] == '<' {
			l.pos += 1
			return lexer_make_token(l, .Lt_Lt, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Lt, start, l.source[start:l.pos])
	}

	if ch == '>' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '>' {
			l.pos += 1
			return lexer_make_token(l, .Gt_Gt, start, l.source[start:l.pos])
		}
		if l.pos < len(l.source) && l.source[l.pos] == '=' {
			l.pos += 1
			return lexer_make_token(l, .Gt_Eq, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Gt, start, l.source[start:l.pos])
	}

	if ch == '!' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '=' {
			l.pos += 1
			return lexer_make_token(l, .Bang_Eq, start, l.source[start:l.pos])
		}
		// ! without = is an error — not a valid token
		diagnostics.collector_add_diag(
			l.collector,
			diagnostics.diag_unexpected_char('!', lexer_make_span(l, start)),
		)
		return lexer_next(l)
	}

	if ch == '.' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '.' {
			l.pos += 1
			return lexer_make_token(l, .Dot_Dot, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Dot, start, l.source[start:l.pos])
	}

	if ch == ':' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '=' {
			l.pos += 1
			return lexer_make_token(l, .Colon_Eq, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Colon, start, l.source[start:l.pos])
	}

	if kind := SINGLE_CHAR_TOKEN[ch]; kind != base.Token_Kind(0) {
		l.pos += 1
		return lexer_make_token(l, kind, start, l.source[start:l.pos])
	}

	l.pos += 1
	diagnostics.collector_add_diag(
		l.collector,
		diagnostics.diag_unexpected_char(ch, lexer_make_span(l, start)),
	)
	return lexer_next(l)
}

lexer_lex_number :: proc(l: ^Lexer, start: int) -> base.Token {
	is_float := false

	if pos := start; pos + 1 < len(l.source) && l.source[pos] == '0' {
		next := l.source[pos + 1]
		switch next {
		case 'x':
			return lexer_lex_hex_number(l, start)
		case 'o':
			return lexer_lex_octal_number(l, start)
		case 'b':
			return lexer_lex_binary_number(l, start)
		}
	}

	when simd.HAS_HARDWARE_SIMD {
		scan_number_simd(l, &is_float)
	} else {
		for l.pos < len(l.source) {
			ch := l.source[l.pos]
			if ch >= '0' && ch <= '9' {
				l.pos += 1
			} else if ch == '.' && !is_float {
				if l.pos + 1 < len(l.source) &&
				   l.source[l.pos + 1] >= '0' &&
				   l.source[l.pos + 1] <= '9' {
					is_float = true
					l.pos += 1
				} else {
					break
				}
			} else if ch == '_' {
				l.pos += 1
			} else {
				break
			}
		}
	}

	text := l.source[start:l.pos]
	tok := lexer_make_token(l, .Int_Literal, start, text)

	if is_float {
		tok.kind = .Float_Literal
		tok.f64_value, _ = strconv.parse_f64(text)
	} else {
		tok.int_value, _ = strconv.parse_i64(text)
	}

	return tok
}

lexer_lex_hex_number :: proc(l: ^Lexer, start: int) -> base.Token {
	// Skip '0x'
	l.pos += 2
	digit_start := l.pos
	hex_scan: for l.pos < len(l.source) {
		ch := l.source[l.pos]
		switch {
		case (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'):
			l.pos += 1
		case ch == '_':
			l.pos += 1
		case:
			break hex_scan
		}
	}

	// A hex literal must have at least one digit after `0x`.
	if l.pos == digit_start && l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		return lexer_report_invalid_numeric(
			l,
			start,
			"Hexadecimal literals need at least one digit after `0x`.",
		)
	}

	// Trailing alphanumerics out of base range (e.g. `0xGH`) malformed the literal.
	if l.pos < len(l.source) && (is_identifier_continue(l.source[l.pos])) {
		return lexer_report_invalid_numeric(
			l,
			start,
			"Hexadecimal literals only allow digits 0-9 and A-F (or a-f).",
		)
	}

	text := l.source[start:l.pos]
	tok := lexer_make_token(l, .Int_Literal, start, text)
	// skip '0x' prefix for parsing
	if len(text) > 2 {
		tok.int_value, _ = strconv.parse_i64_of_base(text[2:], 16)
	}
	return tok
}

lexer_lex_octal_number :: proc(l: ^Lexer, start: int) -> base.Token {
	// Skip '0o'
	l.pos += 2
	digit_start := l.pos
	oct_scan: for l.pos < len(l.source) {
		ch := l.source[l.pos]
		switch {
		case ch >= '0' && ch <= '7':
			l.pos += 1
		case ch == '_':
			l.pos += 1
		case:
			break oct_scan
		}
	}

	// An octal literal must have at least one digit after `0o`.
	if l.pos == digit_start && l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		return lexer_report_invalid_numeric(
			l,
			start,
			"Octal literals need at least one digit after `0o`.",
		)
	}

	// Trailing alphanumerics out of base range (e.g. `0o78`) malformed the literal.
	if l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		return lexer_report_invalid_numeric(
			l,
			start,
			"Octal literals only allow digits 0 through 7.",
		)
	}

	text := l.source[start:l.pos]
	tok := lexer_make_token(l, .Int_Literal, start, text)
	if len(text) > 2 {
		tok.int_value, _ = strconv.parse_i64_of_base(text[2:], 8)
	}
	return tok
}

lexer_lex_binary_number :: proc(l: ^Lexer, start: int) -> base.Token {
	// Skip '0b'
	l.pos += 2
	digit_start := l.pos
	bin_scan: for l.pos < len(l.source) {
		ch := l.source[l.pos]
		switch {
		case ch == '0' || ch == '1':
			l.pos += 1
		case ch == '_':
			l.pos += 1
		case:
			break bin_scan
		}
	}

	// A binary literal must have at least one digit after `0b`.
	if l.pos == digit_start && l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		return lexer_report_invalid_numeric(
			l,
			start,
			"Binary literals need at least one digit after `0b`.",
		)
	}

	// Trailing alphanumerics out of base range (e.g. `0b102`) malformed the literal.
	if l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		return lexer_report_invalid_numeric(l, start, "Binary literals only allow digits 0 and 1.")
	}

	text := l.source[start:l.pos]
	tok := lexer_make_token(l, .Int_Literal, start, text)
	if len(text) > 2 {
		tok.int_value, _ = strconv.parse_i64_of_base(text[2:], 2)
	}
	return tok
}

when simd.HAS_HARDWARE_SIMD {

	scan_number_simd :: proc(l: ^Lexer, is_float: ^bool) {
		source_len := len(l.source)
		for {
			for l.pos + 16 <= source_len {
				chunk := load_chunk(l.source, l.pos)
				num_bits := extract_mask(is_number_continue_simd(chunk))

				if num_bits == 0 {
					return
				}

				not_num_bits := ~num_bits
				if not_num_bits == 0 {
					// All 16 bytes are number-continue chars — check for dots
					dot_bits := extract_mask(simd.lanes_eq(chunk, simd.u8x16('.')))
					if dot_bits != 0 {
						dot_pos := int(intrinsics.count_trailing_zeros(dot_bits))
						abs_dot := l.pos + dot_pos
						if abs_dot + 1 < source_len &&
						   l.source[abs_dot + 1] >= '0' &&
						   l.source[abs_dot + 1] <= '9' {
							is_float^ = true
							l.pos = abs_dot + 1
							continue
						} else {
							l.pos += dot_pos
							return
						}
					}
					l.pos += 16
					continue
				}

				first_non_num := int(intrinsics.count_trailing_zeros(not_num_bits))
				if first_non_num == 0 {
					return
				}

				// Check for '.' in the matched region
				prefix_mask := u16(1) << u16(first_non_num) - 1
				dot_bits := extract_mask(simd.lanes_eq(chunk, simd.u8x16('.')))
				dot_in_prefix := dot_bits & prefix_mask

				if dot_in_prefix != 0 {
					dot_pos := int(intrinsics.count_trailing_zeros(dot_in_prefix))
					abs_dot := l.pos + dot_pos
					if abs_dot + 1 < source_len &&
					   l.source[abs_dot + 1] >= '0' &&
					   l.source[abs_dot + 1] <= '9' {
						is_float^ = true
						l.pos = abs_dot + 1
						continue
					} else {
						l.pos += dot_pos
						return
					}
				}

				l.pos += first_non_num
				return
			}

			// Scalar fallback for remaining bytes
			for l.pos < source_len {
				ch := l.source[l.pos]
				if ch >= '0' && ch <= '9' {
					l.pos += 1
				} else if ch == '.' && !is_float^ {
					if l.pos + 1 < source_len &&
					   l.source[l.pos + 1] >= '0' &&
					   l.source[l.pos + 1] <= '9' {
						is_float^ = true
						l.pos += 1
					} else {
						break
					}
				} else if ch == '_' {
					l.pos += 1
				} else {
					break
				}
			}
			return
		}
	}

}

lexer_lex_string :: proc(l: ^Lexer, start: int) -> base.Token {
	l.pos += 1

	has_interpolation := false

	when simd.HAS_HARDWARE_SIMD {
		scan_string_body_simd(l, &has_interpolation)
	} else {
		for l.pos < len(l.source) && l.source[l.pos] != '"' {
			if l.source[l.pos] == '\\' {
				l.pos += 1
				if l.pos < len(l.source) {
					lexer_validate_string_escape(l, l.pos)
					l.pos += 1
				}
			} else if l.source[l.pos] == '$' &&
			   l.pos + 1 < len(l.source) &&
			   l.source[l.pos + 1] == '{' {
				has_interpolation = true
				l.pos += 1
			}
			l.pos += 1
		}
	}

	if l.pos < len(l.source) {
		l.pos += 1
	} else {
		diagnostics.collector_add_diag(
			l.collector,
			diagnostics.diag_unterminated_string(lexer_make_span(l, start)),
		)
	}

	text := l.source[start:l.pos]
	kind := base.Token_Kind.String_Literal
	if has_interpolation {
		kind = .Interpolated_String_Literal
	}
	return base.Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

when simd.HAS_HARDWARE_SIMD {

	scan_string_body_simd :: proc(l: ^Lexer, has_interpolation: ^bool) {
		source_len := len(l.source)
		for {
			// SIMD scan for ", \, $
			for l.pos + 16 <= source_len {
				chunk := load_chunk(l.source, l.pos)
				interesting_bits := extract_mask(is_string_interesting_simd(chunk))

				if interesting_bits == 0 {
					l.pos += 16
					continue
				}

				// Found interesting byte within this chunk
				first := int(intrinsics.count_trailing_zeros(interesting_bits))
				l.pos += first
				break
			}

			// Handle the interesting byte (or scalar tail)
			if l.pos >= source_len {return}
			ch := l.source[l.pos]

			if ch == '"' {
				return
			} else if ch == '\\' {
				l.pos += 1 // skip escape char
				if l.pos < source_len {
					lexer_validate_string_escape(l, l.pos)
					l.pos += 1 // skip escaped char
				}
				continue
			} else if ch == '$' && l.pos + 1 < source_len && l.source[l.pos + 1] == '{' {
				has_interpolation^ = true
				l.pos += 1
				continue
			} else {
				l.pos += 1
				continue
			}
		}
	}

	scan_perline_content_simd :: proc(l: ^Lexer, has_interpolation: ^bool) {
		source_len := len(l.source)
		for {
			for l.pos + 16 <= source_len {
				chunk := load_chunk(l.source, l.pos)
				interesting_bits := extract_mask(is_perline_interesting_simd(chunk))

				if interesting_bits == 0 {
					l.pos += 16
					continue
				}

				first := int(intrinsics.count_trailing_zeros(interesting_bits))
				l.pos += first
				break
			}

			if l.pos >= source_len {return}
			ch := l.source[l.pos]

			if ch == '\n' {
				return
			} else if ch == '\\' {
				l.pos += 1
				if l.pos < source_len {l.pos += 1}
				continue
			} else if ch == '$' && l.pos + 1 < source_len && l.source[l.pos + 1] == '{' {
				has_interpolation^ = true
				l.pos += 1
				continue
			} else {
				l.pos += 1
				continue
			}
		}
	}

}

lexer_lex_char :: proc(l: ^Lexer, start: int) -> base.Token {
	l.pos += 1 // skip opening '

	if l.pos < len(l.source) && l.source[l.pos] == '\\' {
		// Escaped char
		l.pos += 1
		if l.pos < len(l.source) {
			l.pos += 1
		}
	} else if l.pos < len(l.source) {
		// Regular char
		l.pos += 1
	}

	if l.pos < len(l.source) && l.source[l.pos] == '\'' {
		l.pos += 1
	} else {
		diagnostics.collector_add_diag(
			l.collector,
			diagnostics.diag_unterminated_string(lexer_make_span(l, start)),
		)
	}

	text := l.source[start:l.pos]
	return lexer_make_token(l, .Char_Literal, start, text)
}

lexer_lex_perline_string :: proc(l: ^Lexer, start: int) -> base.Token {
	has_interpolation := false

	// Collect all \-prefixed lines into a single string token
	// The token text includes the \ prefixes for the parser to process
	for l.at_line_start && l.pos < len(l.source) && l.source[l.pos] == '\\' {
		l.pos += 1 // skip the \ prefix

		// Skip optional space after \
		if l.pos < len(l.source) && l.source[l.pos] == ' ' {
			l.pos += 1
		}

		// Read content until end of line
		when simd.HAS_HARDWARE_SIMD {
			scan_perline_content_simd(l, &has_interpolation)
		} else {
			for l.pos < len(l.source) && l.source[l.pos] != '\n' {
				if l.source[l.pos] == '$' &&
				   l.pos + 1 < len(l.source) &&
				   l.source[l.pos + 1] == '{' {
					has_interpolation = true
				}
				l.pos += 1
			}
		}

		// Consume the newline (it becomes part of the string content)
		if l.pos < len(l.source) && l.source[l.pos] == '\n' {
			l.pos += 1
			l.at_line_start = true
		} else if l.pos >= len(l.source) {
			// Reached EOF before the closing newline of this \-line.
			diagnostics.collector_add_diag(
				l.collector,
				diagnostics.diag_unterminated_per_line_string(lexer_make_span(l, start)),
			)
			break
		}

		// Skip whitespace at start of next line to check for another \
		for l.pos < len(l.source) {
			ch := l.source[l.pos]
			if ch == ' ' || ch == '\t' || ch == '\r' {
				l.pos += 1
			} else if ch == '/' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '/' {
				// Skip comment lines between \ lines
				l.pos += 2
				for l.pos < len(l.source) && l.source[l.pos] != '\n' {
					l.pos += 1
				}
				if l.pos < len(l.source) && l.source[l.pos] == '\n' {
					l.pos += 1
					l.at_line_start = true
				}
			} else {
				break
			}
		}
	}

	text := l.source[start:l.pos]
	kind := base.Token_Kind.Perline_String_Literal
	if has_interpolation {
		kind = .Interpolated_String_Literal
	}
	return base.Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

lexer_lex_identifier :: proc(l: ^Lexer, start: int) -> base.Token {
	is_upper := l.source[l.pos] >= 'A' && l.source[l.pos] <= 'Z'

	l.pos += 1 // consume identifier-start byte

	when simd.HAS_HARDWARE_SIMD {
		scan_identifier_simd(l)
	} else {
		for l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
			l.pos += 1
		}
	}

	base_text := l.source[start:l.pos]

	// Absorb trailing ! (only 1) for non-keyword identifiers
	if _, is_keyword := KEYWORDS[base_text]; !is_keyword {
		bang_count := 0
		for l.pos < len(l.source) && l.source[l.pos] == '!' && bang_count < 1 {
			// Don't absorb ! if followed by = (that's the != operator)
			if l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '=' {
				break
			}
			l.pos += 1
			bang_count += 1
		}
		// Double ! suffix is not allowed (e.g. main!! is invalid)
		// Only check if we already absorbed one ! (bang_count > 0)
		if bang_count > 0 && l.pos < len(l.source) && l.source[l.pos] == '!' {
			diagnostics.collector_add_diag(
				l.collector,
				diagnostics.diag_double_bang_suffix(lexer_make_span(l, l.pos)),
			)
			l.pos += 1 // skip the extra ! to avoid cascading errors
		}
	}

	text := l.source[start:l.pos]

	if kind, ok := KEYWORDS[text]; ok {
		return lexer_make_token(l, kind, start, text)
	}

	if is_upper {
		return lexer_make_token(l, .Upper_Id, start, text)
	}

	return lexer_make_token(l, .Identifier, start, text)
}

when simd.HAS_HARDWARE_SIMD {

	scan_identifier_simd :: proc(l: ^Lexer) {
		source_len := len(l.source)
		for l.pos + 16 <= source_len {
			chunk := load_chunk(l.source, l.pos)
			ident_bits := extract_mask(is_identifier_continue_simd(chunk))

			not_ident_bits := ~ident_bits
			if not_ident_bits == 0 {
				// All 16 bytes are identifier-continue chars
				l.pos += 16
				continue
			}

			// Found non-identifier byte within this chunk
			first_non_ident := int(intrinsics.count_trailing_zeros(not_ident_bits))
			l.pos += first_non_ident
			return
		}

		// Scalar fallback for remaining bytes
		for l.pos < source_len && is_identifier_continue(l.source[l.pos]) {
			l.pos += 1
		}
	}

}

is_identifier_start :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_identifier_continue :: proc(ch: u8) -> bool {
	return is_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

// Valid escape sequences inside `"..."` string literals.
// Mirrors docs/language-spec.md §1 (`\n \t \r \\ \" \$`) plus `\0`
// (kept for compatibility with the C0003 constructor hint).
is_valid_string_escape :: proc(ch: u8) -> bool {
	switch ch {
	case 'n', 't', 'r', '\\', '"', '$', '0':
		return true
	case:
		return false
	}
}

// Reports a malformed numeric literal (C0005). Consumes the trailing run of
// identifier-continue characters so the malformed text is reported as one
// token and does not cascade into spurious follow-on tokens.
lexer_report_invalid_numeric :: proc(l: ^Lexer, start: int, hint: string) -> base.Token {
	for l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		l.pos += 1
	}
	text := l.source[start:l.pos]
	diagnostics.collector_add_diag(
		l.collector,
		diagnostics.diag_invalid_numeric_literal(text, hint, lexer_make_span(l, start)),
	)
	return lexer_make_token(l, .Int_Literal, start, text)
}

// Reports an invalid escape sequence inside a `"..."` string literal.
// `escape_pos` is the offset of the character following the `\`.
lexer_validate_string_escape :: proc(l: ^Lexer, escape_pos: int) {
	if escape_pos >= len(l.source) {
		return
	}
	escape_ch := l.source[escape_pos]
	if is_valid_string_escape(escape_ch) {
		return
	}
	span := base.Source_Span {
		file_id = l.file_id,
		start   = escape_pos,
		end     = escape_pos + 1,
	}
	buf: [1]u8
	buf[0] = escape_ch
	diagnostics.collector_add_diag(
		l.collector,
		diagnostics.diag_invalid_escape(string(buf[:]), span),
	)
}


#+feature dynamic-literals
package frontend

import "core:fmt"
import "core:simd"
import "core:strconv"
import "base:intrinsics"
import "camp:base"
import "camp:diagnostics"

KEYWORDS :map[string]base.Token_Kind = {
	"if"        = .Kw_If,
	"else"      = .Kw_Else,
	"match"     = .Kw_Match,
	"is"        = .Kw_Is,
	"derives"   = .Kw_Derives,
	"handle"    = .Kw_Handle,
	"in"        = .Kw_In,
	"with"      = .Kw_With,
	"import"    = .Kw_Import,
	"as"        = .Kw_As,
	"for"       = .Kw_For,
	"and"       = .Kw_And,
	"or"        = .Kw_Or,
	"expect"    = .Kw_Expect,
	"test"      = .Kw_Test,
	"not"       = .Kw_Not,
	"pub"       = .Kw_Pub,
	"Self"      = .Kw_Self,
	"par"       = .Kw_Par,
	"where"     = .Kw_Where,
	"return"    = .Kw_Return,
	"crash"    = .Kw_Crash,
	"todo"     = .Kw_Todo,
}

Lexer :: struct {
	source:    string,
	pos:       int,
	collector: ^diagnostics.Diagnostic_Collector,
	intern:    ^base.Intern_Table,
	file_id:   int,
	at_line_start: bool,  // true when pos is at the start of a new line
}

lexer_init :: proc(l: ^Lexer, file: base.Source_File, collector: ^diagnostics.Diagnostic_Collector, table: ^base.Intern_Table) {
	l.source = file.contents
	l.pos = 0
	l.collector = collector
	l.intern = table
	l.file_id = file.id
	l.at_line_start = true
}

lexer_peek :: proc(l: ^Lexer) -> u8 {
	if l.pos >= len(l.source) { return 0 }
	return l.source[l.pos]
}

lexer_advance :: proc(l: ^Lexer) -> u8 {
	if l.pos >= len(l.source) { return 0 }
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
			if nl_bits != 0 { l.at_line_start = true }
			l.pos += 16
			continue
		}

		// Found non-whitespace within this chunk
		first_non_ws := int(intrinsics.count_trailing_zeros(not_ws_bits))
		prefix_mask := u16(1 << u16(first_non_ws)) - 1
		if (nl_bits & prefix_mask) != 0 { l.at_line_start = true }
		l.pos += first_non_ws
		return
	}
}

}

lexer_skip_whitespace_scalar :: proc(l: ^Lexer) {
	for l.pos < len(l.source) {
		ch := l.source[l.pos]
		if ch == ' ' || ch == '\t' || ch == '\r' {
			l.pos += 1
		} else if ch == '\n' {
			l.pos += 1
			l.at_line_start = true
		} else if ch == '/' && l.pos + 2 < len(l.source) && l.source[l.pos + 1] == '/' && l.source[l.pos + 2] == '/' {
			// /// doc comment — stop so lexer_next can produce a Doc_Comment token
			break
		} else if ch == '/' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '/' {
			// // regular comment — skip
			l.pos += 2
			for l.pos < len(l.source) && l.source[l.pos] != '\n' {
				l.pos += 1
			}
		} else if ch == '\\' && l.at_line_start {
			// \ at line start = per-line string — stop so lexer_next can handle it
			break
		} else {
			l.at_line_start = false
			break
		}
	}
}

lexer_make_span :: proc(l: ^Lexer, start: int) -> base.Source_Span {
	return base.Source_Span{file_id = l.file_id, start = start, end = l.pos}
}

lexer_make_token :: proc(l: ^Lexer, kind: base.Token_Kind, start: int, text: string) -> base.Token {
	return base.Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

lexer_next :: proc(l: ^Lexer) -> base.Token {
	lexer_skip_whitespace(l)

	if l.pos >= len(l.source) {
		return base.Token{kind = .Eof, span = lexer_make_span(l, l.pos)}
	}

	start := l.pos
	ch := l.source[l.pos]

	// /// doc comment
	if ch == '/' && l.pos + 2 < len(l.source) && l.source[l.pos + 1] == '/' && l.source[l.pos + 2] == '/' {
		l.pos += 3
		// Skip optional space after ///
		if l.pos < len(l.source) && l.source[l.pos] == ' ' {
			l.pos += 1
		}
		content_start := l.pos
		for l.pos < len(l.source) && l.source[l.pos] != '\n' {
			l.pos += 1
		}
		return lexer_make_token(l, .Doc_Comment, start, l.source[content_start:l.pos])
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
		if lookahead < len(l.source) && l.source[lookahead] != '\n' && l.source[lookahead] != '\r' {
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
			diagnostics.collector_add_diag(l.collector, diagnostics.diag_unexpected_char('`', lexer_make_span(l, start)))
			return lexer_next(l)
		}
		l.pos += 1 // skip closing backtick
		// Extract the identifier text without the backticks
		inner_text := l.source[start+1:l.pos-1]
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
		return lexer_make_token(l, .Lt, start, l.source[start:l.pos])
	}

	if ch == '>' {
		l.pos += 1
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
		diagnostics.collector_add_diag(l.collector, diagnostics.diag_unexpected_char('!', lexer_make_span(l, start)))
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
	diagnostics.collector_add_diag(l.collector, diagnostics.diag_unexpected_char(ch, lexer_make_span(l, start)))
	return lexer_next(l)
}

lexer_lex_number :: proc(l: ^Lexer, start: int) -> base.Token {
	is_float := false
	for l.pos < len(l.source) {
		ch := l.source[l.pos]
		if ch >= '0' && ch <= '9' {
			l.pos += 1
		} else if ch == '.' && !is_float {
			if l.pos + 1 < len(l.source) && l.source[l.pos + 1] >= '0' && l.source[l.pos + 1] <= '9' {
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

lexer_lex_string :: proc(l: ^Lexer, start: int) -> base.Token {
	l.pos += 1

	has_interpolation := false

	for l.pos < len(l.source) && l.source[l.pos] != '"' {
		if l.source[l.pos] == '\\' {
			l.pos += 1
		} else if l.source[l.pos] == '$' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '{' {
			has_interpolation = true
		}
		l.pos += 1
	}

	if l.pos < len(l.source) {
		l.pos += 1
	} else {
		diagnostics.collector_add_diag(l.collector, diagnostics.diag_unterminated_string(lexer_make_span(l, start)))
	}

	text := l.source[start:l.pos]
	kind := base.Token_Kind.String_Literal
	if has_interpolation {
		kind = .Interpolated_String_Literal
	}
	return base.Token{kind = kind, text = text, span = lexer_make_span(l, start)}
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
		diagnostics.collector_add_diag(l.collector, diagnostics.diag_unterminated_string(lexer_make_span(l, start)))
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
		for l.pos < len(l.source) && l.source[l.pos] != '\n' {
			if l.source[l.pos] == '$' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '{' {
				has_interpolation = true
			}
			l.pos += 1
		}

		// Consume the newline (it becomes part of the string content)
		if l.pos < len(l.source) && l.source[l.pos] == '\n' {
			l.pos += 1
			l.at_line_start = true
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

	for l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		l.pos += 1
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

is_identifier_start :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_identifier_continue :: proc(ch: u8) -> bool {
	return is_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

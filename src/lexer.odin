#+feature dynamic-literals
package camp

import "core:fmt"
import "core:strconv"

KEYWORDS :map[string]Token_Kind = {
	"if"        = .Kw_If,
	"else"      = .Kw_Else,
	"match"     = .Kw_Match,
	"effect"    = .Kw_Effect,
	"trait"     = .Kw_Trait,
	"is"        = .Kw_Is,
	"alias"     = .Kw_Alias,
	"handle"    = .Kw_Handle,
	"intercept" = .Kw_Intercept,
	"in"        = .Kw_In,
	"with"      = .Kw_With,
	"import"    = .Kw_Import,
	"exposing"  = .Kw_Exposing,
	"as"        = .Kw_As,
	"unsafe"    = .Kw_Unsafe,
	"for"       = .Kw_For,
	"and"       = .Kw_And,
	"or"        = .Kw_Or,
	"true"      = .Kw_True,
	"false"     = .Kw_False,
	"expect"    = .Kw_Expect,
	"test"      = .Kw_Test,
	"not"       = .Kw_Not,
}

Lexer :: struct {
	source:    string,
	pos:       int,
	collector: ^Error_Collector,
	intern:    ^Intern_Table,
	file_id:   int,
}

lexer_init :: proc(l: ^Lexer, file: Source_File, collector: ^Error_Collector, table: ^Intern_Table) {
	l.source = file.contents
	l.pos = 0
	l.collector = collector
	l.intern = table
	l.file_id = file.id
}

lexer_peek :: proc(l: ^Lexer) -> u8 {
	if l.pos >= len(l.source) { return 0 }
	return l.source[l.pos]
}

lexer_advance :: proc(l: ^Lexer) -> u8 {
	ch := l.source[l.pos]
	l.pos += 1
	return ch
}

lexer_skip_whitespace :: proc(l: ^Lexer) {
	for l.pos < len(l.source) {
		ch := l.source[l.pos]
		if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
			l.pos += 1
		} else if ch == '-' && l.pos + 1 < len(l.source) && l.source[l.pos + 1] == '-' {
			l.pos += 2
			for l.pos < len(l.source) && l.source[l.pos] != '\n' {
				l.pos += 1
			}
		} else {
			break
		}
	}
}

lexer_make_span :: proc(l: ^Lexer, start: int) -> Source_Span {
	return Source_Span{file_id = l.file_id, start = start, end = l.pos}
}

lexer_make_token :: proc(l: ^Lexer, kind: Token_Kind, start: int, text: string) -> Token {
	return Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

lexer_next :: proc(l: ^Lexer) -> Token {
	lexer_skip_whitespace(l)

	if l.pos >= len(l.source) {
		return Token{kind = .Eof, span = lexer_make_span(l, l.pos)}
	}

	start := l.pos
	ch := l.source[l.pos]

	if ch >= '0' && ch <= '9' {
		return lexer_lex_number(l, start)
	}

	if ch == '"' {
		return lexer_lex_string(l, start)
	}

	if ch == '$' {
		l.pos += 1
		return lexer_make_token(l, .Dollar, start, l.source[start:l.pos])
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
		return lexer_make_token(l, .Bang, start, l.source[start:l.pos])
	}

	if ch == '.' {
		l.pos += 1
		if l.pos < len(l.source) && l.source[l.pos] == '.' {
			l.pos += 1
			return lexer_make_token(l, .Dot_Dot, start, l.source[start:l.pos])
		}
		return lexer_make_token(l, .Dot, start, l.source[start:l.pos])
	}

	single_char_tokens :map[u8]Token_Kind = {
		'|'  = .Pipe,
		':'  = .Colon,
		','  = .Comma,
		'#'  = .Hash,
		'@'  = .At,
		'+'  = .Plus,
		'*'  = .Star,
		'/'  = .Slash,
		'%'  = .Percent,
		'&'  = .Amp,
		'^'  = .Caret,
		'~'  = .Tilde,
		'('  = .LParen,
		')'  = .RParen,
		'['  = .LBrack,
		']'  = .RBrack,
		'{'  = .LBrace,
		'}'  = .RBrace,
	}

	if kind, ok := single_char_tokens[ch]; ok {
		l.pos += 1
		return lexer_make_token(l, kind, start, l.source[start:l.pos])
	}

	l.pos += 1
	collector_add(l.collector, .Error, "unexpected character", lexer_make_span(l, start))
	return lexer_next(l)
}

lexer_lex_number :: proc(l: ^Lexer, start: int) -> Token {
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

lexer_lex_string :: proc(l: ^Lexer, start: int) -> Token {
	l.pos += 1

	for l.pos < len(l.source) && l.source[l.pos] != '"' {
		if l.source[l.pos] == '\\' {
			l.pos += 1
		}
		l.pos += 1
	}

	if l.pos < len(l.source) {
		l.pos += 1
	} else {
		collector_add(l.collector, .Error, "unterminated string literal", lexer_make_span(l, start))
	}

	text := l.source[start:l.pos]
	return Token{kind = .String_Literal, text = text, span = lexer_make_span(l, start)}
}

lexer_lex_identifier :: proc(l: ^Lexer, start: int) -> Token {
	is_upper := l.source[l.pos] >= 'A' && l.source[l.pos] <= 'Z'

	for l.pos < len(l.source) && is_identifier_continue(l.source[l.pos]) {
		l.pos += 1
	}

	text := l.source[start:l.pos]

	if !is_upper {
		if kind, ok := KEYWORDS[text]; ok {
			return lexer_make_token(l, kind, start, text)
		}
		return lexer_make_token(l, .Identifier, start, text)
	}

	return lexer_make_token(l, .Upper_Id, start, text)
}

is_identifier_start :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_identifier_continue :: proc(ch: u8) -> bool {
	return is_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

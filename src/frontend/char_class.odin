package frontend

import "base:intrinsics"
import "camp:base"
import "core:simd"

Char_Flag :: enum {
	Whitespace,
	Newline,
	Ident_Start,
	Ident_Continue,
	Digit,
	Hex_Digit,
	Operator_Start,
	Delimiter,
}

Char_Class :: bit_set[Char_Flag]

@(private)
build_char_class_table :: proc "contextless" () -> [256]Char_Class {
	table: [256]Char_Class

	table[' '] = {.Whitespace}
	table['\t'] = {.Whitespace}
	table['\r'] = {.Whitespace}
	table['\n'] = {.Newline}

	for c in 'a' ..= 'z' {
		table[c] = {.Ident_Start, .Ident_Continue}
		if c <= 'f' {table[c] |= {.Hex_Digit}}
	}
	for c in 'A' ..= 'Z' {
		table[c] = {.Ident_Start, .Ident_Continue}
		if c <= 'F' {table[c] |= {.Hex_Digit}}
	}
	table['_'] = {.Ident_Start, .Ident_Continue}

	for c in '0' ..= '9' {
		table[c] = {.Ident_Continue, .Digit, .Hex_Digit}
	}

	table['+'] = {.Operator_Start}
	table['-'] = {.Operator_Start}
	table['*'] = {.Operator_Start}
	table['/'] = {.Operator_Start}
	table['%'] = {.Operator_Start}
	table['&'] = {.Operator_Start}
	table['|'] = {.Operator_Start}
	table['^'] = {.Operator_Start}
	table['~'] = {.Operator_Start}
	table['='] = {.Operator_Start}
	table['<'] = {.Operator_Start}
	table['>'] = {.Operator_Start}
	table['!'] = {.Operator_Start}
	table['.'] = {.Operator_Start}
	table[':'] = {.Operator_Start}

	table['('] = {.Delimiter}
	table[')'] = {.Delimiter}
	table['['] = {.Delimiter}
	table[']'] = {.Delimiter}
	table['{'] = {.Delimiter}
	table['}'] = {.Delimiter}

	return table
}

@(private)
build_single_char_token_table :: proc "contextless" () -> [256]base.Token_Kind {
	table: [256]base.Token_Kind

	table['|'] = .Pipe
	table[','] = .Comma
	table['#'] = .Hash
	table['@'] = .At
	table['+'] = .Plus
	table['*'] = .Star
	table['/'] = .Slash
	table['%'] = .Percent
	table['&'] = .Amp
	table['^'] = .Caret
	table['~'] = .Tilde
	table['\\'] = .Backslash
	table['('] = .LParen
	table[')'] = .RParen
	table['['] = .LBrack
	table[']'] = .RBrack
	table['{'] = .LBrace
	table['}'] = .RBrace

	return table
}

CHAR_CLASS: [256]Char_Class = build_char_class_table()
SINGLE_CHAR_TOKEN: [256]base.Token_Kind = build_single_char_token_table()

// SIMD helpers — only compiled when hardware SIMD is available

when simd.HAS_HARDWARE_SIMD {

	is_identifier_continue_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		lo_alpha := simd.lanes_ge(chunk, simd.u8x16('a')) & simd.lanes_le(chunk, simd.u8x16('z'))
		hi_alpha := simd.lanes_ge(chunk, simd.u8x16('A')) & simd.lanes_le(chunk, simd.u8x16('Z'))
		digits := simd.lanes_ge(chunk, simd.u8x16('0')) & simd.lanes_le(chunk, simd.u8x16('9'))
		unders := simd.lanes_eq(chunk, simd.u8x16('_'))
		return lo_alpha | hi_alpha | digits | unders
	}

	is_whitespace_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		spaces := simd.lanes_eq(chunk, simd.u8x16(' '))
		tabs := simd.lanes_eq(chunk, simd.u8x16('\t'))
		crs := simd.lanes_eq(chunk, simd.u8x16('\r'))
		return spaces | tabs | crs
	}

	is_newline_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		return simd.lanes_eq(chunk, simd.u8x16('\n'))
	}

	// Find interesting bytes in string bodies: ", \, $
	is_string_interesting_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		quotes := simd.lanes_eq(chunk, simd.u8x16('"'))
		slashes := simd.lanes_eq(chunk, simd.u8x16('\\'))
		dollars := simd.lanes_eq(chunk, simd.u8x16('$'))
		return quotes | slashes | dollars
	}

	// Find interesting bytes in per-line string content: \n, \, $
	is_perline_interesting_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		newlines := simd.lanes_eq(chunk, simd.u8x16('\n'))
		slashes := simd.lanes_eq(chunk, simd.u8x16('\\'))
		dollars := simd.lanes_eq(chunk, simd.u8x16('$'))
		return newlines | slashes | dollars
	}

	// Find number-continue bytes: 0-9, _, .
	is_number_continue_simd :: proc(chunk: simd.u8x16) -> simd.u8x16 {
		digits := simd.lanes_ge(chunk, simd.u8x16('0')) & simd.lanes_le(chunk, simd.u8x16('9'))
		unders := simd.lanes_eq(chunk, simd.u8x16('_'))
		dots := simd.lanes_eq(chunk, simd.u8x16('.'))
		return digits | unders | dots
	}

	// Extract bitmask from u8x16 comparison result as u16 for ctz/popcount
	extract_mask :: proc(v: simd.u8x16) -> u16 {
		return transmute(u16)simd.extract_msbs(v)
	}

	// Load 16 bytes from source at pos (unaligned)
	load_chunk :: proc(source: string, pos: int) -> simd.u8x16 {
		return intrinsics.unaligned_load(cast(^simd.u8x16)raw_data(source[pos:]))
	}

}


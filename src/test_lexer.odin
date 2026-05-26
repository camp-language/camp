package camp

import "camp:base"
import "camp:build"
import "camp:frontend"
import "core:testing"

lex_all :: proc(source: string, ctx: ^build.Compilation_Context) -> []base.Token {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator
	file := base.Source_File {
		path     = "<test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	tokens: [dynamic]base.Token
	for {
		tok := frontend.lexer_next(&lexer)
		append(&tokens, tok)
		if tok.kind == .Eof {break}
	}

	return tokens[:]
}

@(test)
test_lexer_integer_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_lexer_string_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"hello\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_upper_identifier :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("Ok", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Upper_Id)
}

@(test)
test_lexer_lower_identifier :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("add", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
}

@(test)
test_lexer_dollar_identifier :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("$count", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Dollar)
	testing.expect(t, tokens[1].kind == .Identifier)
}

@(test)
test_lexer_keyword :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("if else match", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 4)
	testing.expect(t, tokens[0].kind == .Kw_If)
	testing.expect(t, tokens[1].kind == .Kw_Else)
	testing.expect(t, tokens[2].kind == .Kw_Match)
}

@(test)
test_lexer_arrow :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("->", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Arrow)
}

@(test)
test_lexer_dot_dot :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("..", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Dot_Dot)
}

@(test)
test_lexer_comment :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("42 // this is a comment\n43", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].int_value == 42)
	testing.expect(t, tokens[1].int_value == 43)
}

@(test)
test_lexer_float_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("3.14", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Float_Literal)
}

@(test)
test_lexer_handle :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("handle Async in { } with { }", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 9)
	testing.expect(t, tokens[0].kind == .Kw_Handle)
	testing.expect(t, tokens[1].kind == .Upper_Id)
	testing.expect(t, tokens[2].kind == .Kw_In)
	testing.expect(t, tokens[3].kind == .LBrace)
	testing.expect(t, tokens[4].kind == .RBrace)
	testing.expect(t, tokens[5].kind == .Kw_With)
	testing.expect(t, tokens[6].kind == .LBrace)
	testing.expect(t, tokens[7].kind == .RBrace)
	testing.expect(t, tokens[8].kind == .Eof)
}

@(test)
test_lexer_backslash :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\\", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Backslash)
}

@(test)
test_lexer_backslash_in_string :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"hello\\nworld\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_backslash_after_comma :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("1,\\ 2", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 5)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[1].kind == .Comma)
	testing.expect(t, tokens[2].kind == .Backslash)
	testing.expect(t, tokens[3].kind == .Int_Literal)
	testing.expect(t, tokens[4].kind == .Eof)
}

@(test)
test_lexer_colon_eq :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all(":=", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Colon_Eq)
}

@(test)
test_lexer_colon_vs_colon_eq :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all(": :=", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Colon)
	testing.expect(t, tokens[1].kind == .Colon_Eq)
}

@(test)
test_interpolated_string_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"Hello ${name}!\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Interpolated_String_Literal)
}

@(test)
test_plain_string_no_interpolation :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"Hello world\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_escaped_dollar_in_string :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"Var: \\${HOME}\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_dollar_without_brace :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"Price: $5\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

// ─── Tier 2: SIMD edge-case tests ──────────────────────────────────────────

// Whitespace SIMD edge cases

@(test)
test_simd_empty_source :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 1)
	testing.expect(t, tokens[0].kind == .Eof)
}

@(test)
test_simd_whitespace_only :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("   \t  \r\n  ", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 1)
	testing.expect(t, tokens[0].kind == .Eof)
}

@(test)
test_simd_32_consecutive_spaces :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	src := "                                " + "42"
	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_simd_crlf :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("42\r\n43", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].int_value == 42)
	testing.expect(t, tokens[1].int_value == 43)
}

@(test)
test_simd_chunk_boundary_15 :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	src := "               " + "42" // 15 spaces
	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_simd_chunk_boundary_16 :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	src := "                " + "42" // 16 spaces
	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_simd_chunk_boundary_17 :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	src := "                 " + "42" // 17 spaces
	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_simd_comment_at_chunk_boundary :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	src := "              " + "// comment\n" + "42" // 14 spaces
	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_simd_doc_comment :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("/// doc\n42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Doc_Comment)
	testing.expect(t, tokens[1].int_value == 42)
}

// at_line_start edge cases

@(test)
test_simd_backslash_at_line_start :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	// Camp source: \ + newline + 42
	tokens := lex_all("\\\n42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Backslash)
	testing.expect(t, tokens[1].int_value == 42)
}

@(test)
test_simd_backslash_with_leading_whitespace :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	// Camp source: spaces + \ + newline + 42
	tokens := lex_all("  \\\n42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Backslash)
	testing.expect(t, tokens[1].int_value == 42)
}

@(test)
test_simd_multiple_blank_lines_before_backslash :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	// Camp source: two blank lines then \ + newline + 42
	tokens := lex_all("\n\n\\\n42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Backslash)
	testing.expect(t, tokens[1].int_value == 42)
}

// Identifier SIMD edge cases

@(test)
test_simd_identifier_16_chars :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("abcdefghijklmnop", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
	testing.expect(t, tokens[0].text == "abcdefghijklmnop")
}

@(test)
test_simd_identifier_32_chars :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("abcdefghijklmnopqrstuvwxyz123456", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
	testing.expect(t, tokens[0].text == "abcdefghijklmnopqrstuvwxyz123456")
}

@(test)
test_simd_upper_id :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("MyType", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Upper_Id)
}

@(test)
test_simd_bang_suffix :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("foo!", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
	testing.expect(t, tokens[0].text == "foo!")
}

@(test)
test_simd_bang_suffix_before_eq :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("foo!=", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Identifier)
	testing.expect(t, tokens[0].text == "foo")
	testing.expect(t, tokens[1].kind == .Bang_Eq)
}

@(test)
test_simd_keyword_boundary :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("ifx", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
}

// String SIMD edge cases

@(test)
test_simd_long_string :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	// Build a quoted string with 120 'a' characters
	buf: [130]u8
	i := 0
	buf[i] = '"'; i += 1
	for _ in 0 ..< 120 {
		buf[i] = 'a'; i += 1
	}
	buf[i] = '"'; i += 1
	src := string(buf[:i])

	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_simd_string_with_escapes :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"hello\\nworld\\t!\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_simd_interpolation :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"${x}\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Interpolated_String_Literal)
}

@(test)
test_simd_string_dollar_no_brace :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("\"$5\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

// Number SIMD edge cases

@(test)
test_simd_float :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("3.14", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Float_Literal)
	testing.expect(t, tokens[0].f64_value == 3.14)
}

@(test)
test_simd_underscored_number :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("1_000_000", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 1000000)
}

@(test)
test_simd_number_then_dot_method :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all("42.foo", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 4)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 42)
	testing.expect(t, tokens[1].kind == .Dot)
	testing.expect(t, tokens[2].kind == .Identifier)
	testing.expect(t, tokens[2].text == "foo")
}

// ─── Tier 1: Token-stream equivalence test ─────────────────────────────────

@(test)
test_simd_token_stream_equivalence :: proc(t: ^testing.T) {
	src :=
		"/// Module documentation\n" +
		"pub main! = || -[Console! | Throw!([..])]-> I64 {\n" +
		"    // This is a comment block to test comment handling in the lexer\n" +
		"    x := 42\n" +
		"    y := 3.14\n" +
		"    name := \"hello world with extra text for length testing purposes\"\n" +
		"    result := match x {\n" +
		"        0 => Ok{value = 1}\n" +
		"        _ => Err{msg = \"not zero\"}\n" +
		"    }\n" +
		"    z := x + y * 2 - 1 / 3 % 4\n" +
		"    b := x == 42 and y != 0.0 or not false\n" +
		"    Console.println!(\"value: ${x}\")\n" +
		"    \\ multi line content with extra text for testing perline strings\n" +
		"    return x\n" +
		"}\n"

	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	tokens := lex_all(src, &ctx)
	defer delete(tokens)

	// Verify token count is reasonable (at least 60 tokens including Eof)
	testing.expect(t, len(tokens) >= 60)

	// Iterate through all tokens and verify key kinds appear
	found_pub := false
	found_int_42 := false
	found_float := false
	found_string := false
	found_interpolation := false
	found_perline := false
	found_arrow := false
	found_fat_arrow := false
	found_eq_eq := false
	found_bang_eq := false
	found_and := false
	found_or := false
	found_not := false
	found_return := false
	found_match := false
	found_doc_comment := false

	for tok in tokens {
		#partial switch tok.kind {
		case .Kw_Pub:
			found_pub = true
		case .Int_Literal:
			if tok.int_value == 42 {found_int_42 = true}
		case .Float_Literal:
			found_float = true
		case .String_Literal:
			found_string = true
		case .Interpolated_String_Literal:
			found_interpolation = true
		case .Perline_String_Literal:
			found_perline = true
		case .Arrow:
			found_arrow = true
		case .Fat_Arrow:
			found_fat_arrow = true
		case .Eq_Eq:
			found_eq_eq = true
		case .Bang_Eq:
			found_bang_eq = true
		case .Kw_And:
			found_and = true
		case .Kw_Or:
			found_or = true
		case .Kw_Not:
			found_not = true
		case .Kw_Return:
			found_return = true
		case .Kw_Match:
			found_match = true
		case .Doc_Comment:
			found_doc_comment = true
		}
	}

	testing.expect(t, found_pub)
	testing.expect(t, found_int_42)
	testing.expect(t, found_float)
	testing.expect(t, found_string)
	testing.expect(t, found_interpolation)
	testing.expect(t, found_perline)
	testing.expect(t, found_arrow)
	testing.expect(t, found_fat_arrow)
	testing.expect(t, found_eq_eq)
	testing.expect(t, found_bang_eq)
	testing.expect(t, found_and)
	testing.expect(t, found_or)
	testing.expect(t, found_not)
	testing.expect(t, found_return)
	testing.expect(t, found_match)
	testing.expect(t, found_doc_comment)

	// Last non-EOF token should be the closing brace
	testing.expect(t, len(tokens) >= 2)
	testing.expect(t, tokens[len(tokens) - 2].kind == .RBrace)
}


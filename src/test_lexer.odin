package camp

import "core:testing"

lex_all :: proc(source: string, ctx: ^Compilation_Context) -> []Token {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	tokens: [dynamic]Token
	for {
		tok := lexer_next(&lexer)
		append(&tokens, tok)
		if tok.kind == .Eof { break }
	}

	return tokens[:]
}

@(test)
test_lexer_integer_literal :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("42", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_lexer_string_literal :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("\"hello\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_upper_identifier :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("Ok", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Upper_Id)
}

@(test)
test_lexer_lower_identifier :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("add", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
}

@(test)
test_lexer_dollar_identifier :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("$count", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Dollar)
	testing.expect(t, tokens[1].kind == .Identifier)
}

@(test)
test_lexer_keyword :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("if else match", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 4)
	testing.expect(t, tokens[0].kind == .Kw_If)
	testing.expect(t, tokens[1].kind == .Kw_Else)
	testing.expect(t, tokens[2].kind == .Kw_Match)
}

@(test)
test_lexer_arrow :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("->", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Arrow)
}

@(test)
test_lexer_dot_dot :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("..", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Dot_Dot)
}

@(test)
test_lexer_comment :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("42 -- this is a comment\n43", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].int_value == 42)
	testing.expect(t, tokens[1].int_value == 43)
}

@(test)
test_lexer_float_literal :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("3.14", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Float_Literal)
}

@(test)
test_lexer_handle :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

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
test_lexer_intercept :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("intercept Async in { } with { }", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 9)
	testing.expect(t, tokens[0].kind == .Kw_Intercept)
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
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("\\", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Backslash)
}

@(test)
test_lexer_backslash_in_string :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("\"hello\\nworld\"", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_backslash_after_comma :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	tokens := lex_all("1,\\ 2", &ctx)
	defer delete(tokens)

	testing.expect(t, len(tokens) == 5)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[1].kind == .Comma)
	testing.expect(t, tokens[2].kind == .Backslash)
	testing.expect(t, tokens[3].kind == .Int_Literal)
	testing.expect(t, tokens[4].kind == .Eof)
}

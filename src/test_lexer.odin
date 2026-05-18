package camp

import "core:testing"

lex_all :: proc(source: string) -> ([]Token, ^Error_Collector) {
	collector: ^Error_Collector = new(Error_Collector)
	collector_init(collector)

	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, collector, &table)

	tokens: [dynamic]Token
	for {
		tok := lexer_next(&lexer)
		append(&tokens, tok)
		if tok.kind == .Eof { break }
	}

	return tokens[:], collector
}

@(test)
test_lexer_integer_literal :: proc(t: ^testing.T) {
	tokens, collector := lex_all("42")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Int_Literal)
	testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_lexer_string_literal :: proc(t: ^testing.T) {
	tokens, collector := lex_all("\"hello\"")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_upper_identifier :: proc(t: ^testing.T) {
	tokens, collector := lex_all("Ok")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Upper_Id)
}

@(test)
test_lexer_lower_identifier :: proc(t: ^testing.T) {
	tokens, collector := lex_all("add")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Identifier)
}

@(test)
test_lexer_dollar_identifier :: proc(t: ^testing.T) {
	tokens, collector := lex_all("$count")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].kind == .Dollar)
	testing.expect(t, tokens[1].kind == .Identifier)
}

@(test)
test_lexer_keyword :: proc(t: ^testing.T) {
	tokens, collector := lex_all("if else match")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 4)
	testing.expect(t, tokens[0].kind == .Kw_If)
	testing.expect(t, tokens[1].kind == .Kw_Else)
	testing.expect(t, tokens[2].kind == .Kw_Match)
}

@(test)
test_lexer_arrow :: proc(t: ^testing.T) {
	tokens, collector := lex_all("->")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Arrow)
}

@(test)
test_lexer_dot_dot :: proc(t: ^testing.T) {
	tokens, collector := lex_all("..")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Dot_Dot)
}

@(test)
test_lexer_comment :: proc(t: ^testing.T) {
	tokens, collector := lex_all("42 -- this is a comment\n43")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 3)
	testing.expect(t, tokens[0].int_value == 42)
	testing.expect(t, tokens[1].int_value == 43)
}

@(test)
test_lexer_float_literal :: proc(t: ^testing.T) {
	tokens, collector := lex_all("3.14")
	defer delete(tokens)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, len(tokens) == 2)
	testing.expect(t, tokens[0].kind == .Float_Literal)
}

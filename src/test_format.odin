package camp

import "core:testing"
import "core:strings"

@(test)
test_doc_text :: proc(t: ^testing.T) {
	d := doc_text("let")
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == "let")
}

@(test)
test_doc_empty :: proc(t: ^testing.T) {
	d := doc_empty()
	testing.expect(t, d.kind == .Empty)
}

@(test)
test_doc_line :: proc(t: ^testing.T) {
	d := doc_line()
	testing.expect(t, d.kind == .Line)
}

@(test)
test_doc_soft_line :: proc(t: ^testing.T) {
	d := doc_soft_line()
	testing.expect(t, d.kind == .Soft_Line)
}

@(test)
test_doc_concat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_text("b")}
	d := doc_concat(children)
	testing.expect(t, d.kind == .Concat)
	testing.expect(t, len(d.children) == 2)
	testing.expect(t, d.children[0].text == "a")
	testing.expect(t, d.children[1].text == "b")
}

@(test)
test_doc_group :: proc(t: ^testing.T) {
	children := []Doc{doc_text("hello"), doc_text("world")}
	d := doc_group(children)
	testing.expect(t, d.kind == .Group)
	testing.expect(t, len(d.children) == 2)
}

@(test)
test_doc_nest :: proc(t: ^testing.T) {
	inner := doc_text("body")
	d := doc_nest(4, inner)
	testing.expect(t, d.kind == .Nest)
	testing.expect(t, d.indent == 4)
	testing.expect(t, len(d.children) == 1)
}

@(test)
test_doc_backslash_break :: proc(t: ^testing.T) {
	d := doc_backslash_break()
	testing.expect(t, d.kind == .Backslash_Break)
}

@(test)
test_doc_space :: proc(t: ^testing.T) {
	d := doc_space()
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == " ")
}

@(test)
test_resolve_text :: proc(t: ^testing.T) {
	result := doc_resolve(doc_text("hello"), 0)
	defer delete(result)
	testing.expect(t, result == "hello")
}

@(test)
test_resolve_empty :: proc(t: ^testing.T) {
	result := doc_resolve(doc_empty(), 0)
	defer delete(result)
	testing.expect(t, result == "")
}

@(test)
test_resolve_group_flat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_soft_line(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_group_broken :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_line(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_nest_indent :: proc(t: ^testing.T) {
	inner_children := []Doc{doc_text("b"), doc_line(), doc_text("c")}
	inner := doc_group(inner_children)
	nested := doc_nest(4, inner)
	outer_children := []Doc{doc_text("a"), doc_line(), nested}
	d := doc_group(outer_children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\n    c")
}

@(test)
test_resolve_soft_line_flat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("x"), doc_soft_line(), doc_text("y")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "x y")
}

@(test)
test_resolve_group_nested_break :: proc(t: ^testing.T) {
	inner_children := []Doc{doc_text("b"), doc_line(), doc_text("c")}
	inner := doc_group(inner_children)
	outer_children := []Doc{doc_text("a"), doc_soft_line(), inner, doc_soft_line(), doc_text("d")}
	d := doc_group(outer_children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\nc\nd")
}

@(test)
test_resolve_nest_no_line :: proc(t: ^testing.T) {
	inner := doc_nest(4, doc_text("b"))
	children := []Doc{doc_text("a"), doc_soft_line(), inner}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_backslash_break :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_backslash_break(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_concat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("foo"), doc_text("bar")}
	d := doc_concat(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "foobar")
}

// --- Source Analysis Tests ---

tokenize_source :: proc(source: string, tokens: ^[dynamic]Token) {
	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	itable: Intern_Table
	intern_init(&itable)
	defer intern_destroy(&itable)

	file := Source_File{contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &collector, &itable)

	for {
		tok := lexer_next(&lexer)
		append(tokens, tok)
		if tok.kind == .Eof {
			break
		}
	}
}

@(test)
test_analyze_single_line_call :: proc(t: ^testing.T) {
	source := "foo(1, 2, 3)"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// Expect exactly one separator (the first comma) tracked
	testing.expectf(t, len(info.first_separator_break) == 1, "expected 1 separator break entry, got %d", len(info.first_separator_break))

	for pos, has_break in info.first_separator_break {
		testing.expectf(t, !has_break, "expected no break after separator at position %d in single-line call %q", pos, source)
		_ = pos
	}
}

@(test)
test_analyze_multi_line_list :: proc(t: ^testing.T) {
	source := "[\n\t1,\n\t2,\n]"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	testing.expectf(t, len(info.first_separator_break) > 0, "expected at least one separator break entry in multi-line list")

	for pos, has_break in info.first_separator_break {
		testing.expectf(t, has_break, "expected break after separator at position %d in multi-line list", pos)
	}
}

@(test)
test_analyze_nested_groups :: proc(t: ^testing.T) {
	source := "[foo(1, 2), bar(3, 4)]"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// With 3 groups (outer list + 2 calls), we expect 3 first-separator entries
	// All should be false since everything is on one line
	testing.expectf(t, len(info.first_separator_break) == 3,
		"expected 3 first-separator entries (list + 2 calls), got %d",
		len(info.first_separator_break))

	for pos, has_break in info.first_separator_break {
		testing.expectf(t, !has_break, "expected no break at position %d in single-line nested groups", pos)
	}
}

@(test)
test_analyze_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	found := false
	for _, has_blank in info.blank_line_after {
		// The blank line should be recorded after the last token before the gap
		// source[5:7] is "\n\n" between Int(1) and Identifier(y)
		// Int(1) starts at position 4
		if has_blank {
			found = true
			break
		}
	}
	testing.expectf(t, found, "expected a blank line entry in %q", source)
}

@(test)
test_analyze_trailing_comment :: proc(t: ^testing.T) {
	source := "x -- trailing\nZ"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	testing.expectf(t, len(info.trailing_comments) == 1,
		"expected 1 trailing comment, got %d", len(info.trailing_comments))

	for _, ci in info.trailing_comments {
		testing.expectf(t, ci.text == "trailing",
			"expected comment text 'trailing', got %q", ci.text)
	}
}

@(test)
test_analyze_comment_before :: proc(t: ^testing.T) {
	source := "x\n-- comment\ny\nZ"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// The comment before y should be recorded as comments_before for y's position
	found := false
	for _, comments in info.comments_before {
		for ci in comments {
			if ci.text == "comment" {
				found = true
			}
		}
	}
	testing.expectf(t, found, "expected a 'comment' in comments_before in %q", source)
}

@(test)
test_analyze_doc_comment :: proc(t: ^testing.T) {
	source := "--- doc comment\ny"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	found_doc := false
	for _, comments in info.comments_before {
		for ci in comments {
			if ci.is_doc && ci.text == "doc comment" {
				found_doc = true
			}
		}
	}
	testing.expectf(t, found_doc, "expected a doc comment 'doc comment' in comments_before in %q", source)
}

@(test)
test_analyze_multiple_separators :: proc(t: ^testing.T) {
	source := "a + b + c"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// No delimiters → depth never > 0 → no separators tracked
	testing.expectf(t, len(info.first_separator_break) == 0,
		"expected 0 separators (no grouping delimiters), got %d",
		len(info.first_separator_break))
}

@(test)
test_analyze_pipe_separator :: proc(t: ^testing.T) {
	source := "match x {\n\t| 1 -> \"one\"\n\t| 2 -> \"two\"\n}"
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// At depth 1 (inside {}), the first Pipe is the first separator
	// There should be a newline after this pipe (before the next pipe-arm)
	// Actually the pipe starts its arm, so the newline is between the pipe-arm
	// and the next arm. The first pipe at depth 1 should have a break.
	testing.expectf(t, len(info.first_separator_break) >= 1,
		"expected at least 1 separator (pipe) in match expression, got %d",
		len(info.first_separator_break))
}

@(test)
test_analyze_empty_source :: proc(t: ^testing.T) {
	source := ""
	tokens: [dynamic]Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	testing.expectf(t, len(info.first_separator_break) == 0, "expected no separators in empty source")
	testing.expectf(t, len(info.blank_line_after) == 0, "expected no blank lines in empty source")
	testing.expectf(t, len(info.comments_before) == 0, "expected no comments before in empty source")
	testing.expectf(t, len(info.trailing_comments) == 0, "expected no trailing comments in empty source")
}

package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:format"
import "camp:frontend"
import "core:strings"
import "core:testing"

@(test)
test_doc_text :: proc(t: ^testing.T) {
	d := format.doc_text("let")
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == "let")
}

@(test)
test_doc_empty :: proc(t: ^testing.T) {
	d := format.doc_empty()
	testing.expect(t, d.kind == .Empty)
}

@(test)
test_doc_line :: proc(t: ^testing.T) {
	d := format.doc_line()
	testing.expect(t, d.kind == .Line)
}

@(test)
test_doc_soft_line :: proc(t: ^testing.T) {
	d := format.doc_soft_line()
	testing.expect(t, d.kind == .Soft_Line)
}

@(test)
test_doc_concat :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("a"), format.doc_text("b")}
	d := format.doc_concat(children)
	defer format.doc_destroy(d)
	testing.expect(t, d.kind == .Concat)
	testing.expect(t, len(d.children) == 2)
	testing.expect(t, d.children[0].text == "a")
	testing.expect(t, d.children[1].text == "b")
}

@(test)
test_doc_group :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("hello"), format.doc_text("world")}
	d := format.doc_group(children)
	defer format.doc_destroy(d)
	testing.expect(t, d.kind == .Group)
	testing.expect(t, len(d.children) == 2)
}

@(test)
test_doc_nest :: proc(t: ^testing.T) {
	inner := format.doc_text("body")
	d := format.doc_nest(4, inner)
	defer format.doc_destroy(d)
	testing.expect(t, d.kind == .Nest)
	testing.expect(t, d.indent == 4)
	testing.expect(t, len(d.children) == 1)
}

@(test)
test_doc_backslash_break :: proc(t: ^testing.T) {
	d := format.doc_backslash_break()
	testing.expect(t, d.kind == .Backslash_Break)
}

@(test)
test_doc_space :: proc(t: ^testing.T) {
	d := format.doc_space()
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == " ")
}

@(test)
test_resolve_text :: proc(t: ^testing.T) {
	result := format.doc_resolve(format.doc_text("hello"), 0)
	defer delete(result)
	testing.expect(t, result == "hello")
}

@(test)
test_resolve_empty :: proc(t: ^testing.T) {
	result := format.doc_resolve(format.doc_empty(), 0)
	defer delete(result)
	testing.expect(t, result == "")
}

@(test)
test_resolve_group_flat :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("a"), format.doc_soft_line(), format.doc_text("b")}
	d := format.doc_group(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_group_broken :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("a"), format.doc_line(), format.doc_text("b")}
	d := format.doc_group(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_nest_indent :: proc(t: ^testing.T) {
	inner_children := []format.Doc{format.doc_text("b"), format.doc_line(), format.doc_text("c")}
	inner := format.doc_group(inner_children)
	nested := format.doc_nest(4, inner)
	outer_children := []format.Doc{format.doc_text("a"), format.doc_line(), nested}
	d := format.doc_group(outer_children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\n    c")
}

@(test)
test_resolve_soft_line_flat :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("x"), format.doc_soft_line(), format.doc_text("y")}
	d := format.doc_group(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "x y")
}

@(test)
test_resolve_group_nested_break :: proc(t: ^testing.T) {
	inner_children := []format.Doc{format.doc_text("b"), format.doc_line(), format.doc_text("c")}
	inner := format.doc_group(inner_children)
	outer_children := []format.Doc {
		format.doc_text("a"),
		format.doc_soft_line(),
		inner,
		format.doc_soft_line(),
		format.doc_text("d"),
	}
	d := format.doc_group(outer_children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\nc\nd")
}

@(test)
test_resolve_nest_no_line :: proc(t: ^testing.T) {
	inner := format.doc_nest(4, format.doc_text("b"))
	children := []format.Doc{format.doc_text("a"), format.doc_soft_line(), inner}
	d := format.doc_group(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_backslash_break :: proc(t: ^testing.T) {
	children := []format.Doc {
		format.doc_text("a"),
		format.doc_backslash_break(),
		format.doc_text("b"),
	}
	d := format.doc_group(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_concat :: proc(t: ^testing.T) {
	children := []format.Doc{format.doc_text("foo"), format.doc_text("bar")}
	d := format.doc_concat(children)
	result := format.doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "foobar")
}

// --- Source Analysis Tests ---

tokenize_source :: proc(source: string, tokens: ^[dynamic]base.Token) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	itable: base.Intern_Table
	base.intern_init(&itable)
	defer base.intern_destroy(&itable)

	file := base.Source_File {
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &collector, &itable)

	for {
		tok := frontend.lexer_next(&lexer)
		append(tokens, tok)
		if tok.kind == .Eof {
			break
		}
	}
}

@(test)
test_analyze_single_line_call :: proc(t: ^testing.T) {
	source := "foo(1, 2, 3)"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	// Expect exactly one separator (the first comma) tracked
	testing.expectf(
		t,
		len(info.first_separator_break) == 1,
		"expected 1 separator break entry, got {}",
		len(info.first_separator_break),
	)

	for pos, has_break in info.first_separator_break {
		testing.expectf(
			t,
			!has_break,
			"expected no break after separator at position {} in single-line call {}",
			pos,
			source,
		)
		_ = pos
	}
}

@(test)
test_analyze_multi_line_list :: proc(t: ^testing.T) {
	source := "[\n\t1,\n\t2,\n]"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	testing.expectf(
		t,
		len(info.first_separator_break) > 0,
		"expected at least one separator break entry in multi-line list",
	)

	for pos, has_break in info.first_separator_break {
		testing.expectf(
			t,
			has_break,
			"expected break after separator at position {} in multi-line list",
			pos,
		)
	}
}

@(test)
test_analyze_nested_groups :: proc(t: ^testing.T) {
	source := "[foo(1, 2), bar(3, 4)]"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	// With 3 groups (outer list + 2 calls), we expect 3 first-separator entries
	// All should be false since everything is on one line
	testing.expectf(
		t,
		len(info.first_separator_break) == 3,
		"expected 3 first-separator entries (list + 2 calls), got {}",
		len(info.first_separator_break),
	)

	for pos, has_break in info.first_separator_break {
		testing.expectf(
			t,
			!has_break,
			"expected no break at position {} in single-line nested groups",
			pos,
		)
	}
}

@(test)
test_analyze_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

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
	testing.expectf(t, found, "expected a blank line entry in {}", source)
}

@(test)
test_analyze_trailing_comment :: proc(t: ^testing.T) {
	source := "x -- trailing\nZ"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	testing.expectf(
		t,
		len(info.trailing_comments) == 1,
		"expected 1 trailing comment, got {}",
		len(info.trailing_comments),
	)

	for _, ci in info.trailing_comments {
		testing.expectf(
			t,
			ci.text == "trailing",
			"expected comment text 'trailing', got {}",
			ci.text,
		)
	}
}

@(test)
test_analyze_comment_before :: proc(t: ^testing.T) {
	source := "x\n-- comment\ny\nZ"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	// The comment before y should be recorded as comments_before for y's position
	found := false
	for _, comments in info.comments_before {
		for ci in comments {
			if ci.text == "comment" {
				found = true
			}
		}
	}
	testing.expectf(t, found, "expected a 'comment' in comments_before in {}", source)
}

@(test)
test_analyze_doc_comment :: proc(t: ^testing.T) {
	source := "--- doc comment\ny"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	found_doc := false
	for _, comments in info.comments_before {
		for ci in comments {
			if ci.is_doc && ci.text == "doc comment" {
				found_doc = true
			}
		}
	}
	testing.expectf(
		t,
		found_doc,
		"expected a doc comment 'doc comment' in comments_before in {}",
		source,
	)
}

@(test)
test_analyze_multiple_separators :: proc(t: ^testing.T) {
	source := "a + b + c"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	// No delimiters → depth never > 0 → no separators tracked
	testing.expectf(
		t,
		len(info.first_separator_break) == 0,
		"expected 0 separators (no grouping delimiters), got {}",
		len(info.first_separator_break),
	)
}

@(test)
test_analyze_pipe_separator :: proc(t: ^testing.T) {
	source := "match x {\n\t| 1 -> \"one\"\n\t| 2 -> \"two\"\n}"
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	// At depth 1 (inside {}), the first Pipe is the first separator
	// There should be a newline after this pipe (before the next pipe-arm)
	// Actually the pipe starts its arm, so the newline is between the pipe-arm
	// and the next arm. The first pipe at depth 1 should have a break.
	testing.expectf(
		t,
		len(info.first_separator_break) >= 1,
		"expected at least 1 separator (pipe) in match expression, got {}",
		len(info.first_separator_break),
	)
}

@(test)
test_analyze_empty_source :: proc(t: ^testing.T) {
	source := ""
	tokens: [dynamic]base.Token
	defer delete(tokens)
	tokenize_source(source, &tokens)

	info := format.analyze_source(source, tokens[:])
	defer format.destroy_format_source_info(&info)

	testing.expectf(
		t,
		len(info.first_separator_break) == 0,
		"expected no separators in empty source",
	)
	testing.expectf(t, len(info.blank_line_after) == 0, "expected no blank lines in empty source")
	testing.expectf(
		t,
		len(info.comments_before) == 0,
		"expected no comments before in empty source",
	)
	testing.expectf(
		t,
		len(info.trailing_comments) == 0,
		"expected no trailing comments in empty source",
	)
}

// --- Type Formatting Tests ---

@(test)
test_format_type_primitive :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name := base.intern(&ctx.interner, "Int")

	prim := new(frontend.Type_Primitive)
	prim.name = name
	prim.span = base.Source_Span_ZERO

	type_val := frontend.Type(prim)

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "Int", "expected {}, got {}", "Int", result)
}

@(test)
test_format_type_applied_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	list_name := base.intern(&ctx.interner, "List")
	a_name := base.intern(&ctx.interner, "a")

	a_prim := new(frontend.Type_Primitive)
	a_prim.name = a_name
	a_prim.span = base.Source_Span_ZERO

	applied := new(frontend.Type_Applied)
	applied.name = list_name
	applied.args = make([dynamic]frontend.Type)
	append(&applied.args, frontend.Type(a_prim))
	applied.span = base.Source_Span_ZERO

	type_val := frontend.Type(applied)

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "List(a)", "expected {}, got {}", "List(a)", result)
}

@(test)
test_format_type_tag_union_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	ok_name := base.intern(&ctx.interner, "Ok")
	err_name := base.intern(&ctx.interner, "Err")
	a_name := base.intern(&ctx.interner, "a")
	e_name := base.intern(&ctx.interner, "e")

	a_prim := new(frontend.Type_Primitive)
	a_prim.name = a_name
	a_prim.span = base.Source_Span_ZERO

	e_prim := new(frontend.Type_Primitive)
	e_prim.name = e_name
	e_prim.span = base.Source_Span_ZERO

	ok_payload := make([dynamic]frontend.Type)
	append(&ok_payload, frontend.Type(a_prim))

	err_payload := make([dynamic]frontend.Type)
	append(&err_payload, frontend.Type(e_prim))

	ok_tag := new(frontend.Type_Tag)
	ok_tag.name = ok_name
	ok_tag.payload = ok_payload
	ok_tag.span = base.Source_Span_ZERO

	err_tag := new(frontend.Type_Tag)
	err_tag.name = err_name
	err_tag.payload = err_payload
	err_tag.span = base.Source_Span_ZERO

	tags := make([dynamic]frontend.Type_Tag)
	append(&tags, ok_tag^)
	append(&tags, err_tag^)

	tag_union := new(frontend.Type_Tag_Union)
	tag_union.tags = tags
	tag_union.span = base.Source_Span_ZERO

	type_val := frontend.Type(tag_union)

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "[Ok(a) | Err(e)]",
		"expected {}, got {}",
		"[Ok(a) | Err(e)]",
		result,
	)
}

@(test)
test_format_type_record_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "name")
	age_id := base.intern(&ctx.interner, "age")
	str_id := base.intern(&ctx.interner, "Str")
	u64_id := base.intern(&ctx.interner, "U64")

	str_prim := new(frontend.Type_Primitive)
	str_prim.name = str_id
	str_prim.span = base.Source_Span_ZERO

	u64_prim := new(frontend.Type_Primitive)
	u64_prim.name = u64_id
	u64_prim.span = base.Source_Span_ZERO

	field1 := frontend.Type_Field {
		name = name_id,
		type = frontend.Type(str_prim),
		span = base.Source_Span_ZERO,
	}

	field2 := frontend.Type_Field {
		name = age_id,
		type = frontend.Type(u64_prim),
		span = base.Source_Span_ZERO,
	}

	fields := make([dynamic]frontend.Type_Field)
	append(&fields, field1)
	append(&fields, field2)

	rec := new(frontend.Type_Record)
	rec.fields = fields
	rec.span = base.Source_Span_ZERO

	type_val := frontend.Type(rec)

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "{ name: Str, age: U64 }",
		"expected {}, got {}",
		"{ name: Str, age: U64 }",
		result,
	)
}

// --- Expression Formatting Tests ---

@(test)
test_format_expr_int :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	e := new(frontend.Expr_Int)
	e.value = 42
	e.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "42", "expected {}, got {}", "42", result)
}

@(test)
test_format_expr_string :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	e := new(frontend.Expr_String)
	e.value = "hello"
	e.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "hello", "expected {}, got {}", "hello", result)
}

@(test)
test_format_expr_bool :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	e := new(frontend.Expr_Bool)
	e.value = true
	e.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "True", "expected {}, got {}", "True", result)

	e2 := new(frontend.Expr_Bool)
	e2.value = false
	e2.span = base.Source_Span_ZERO

	result2 := format.doc_resolve(format.format_expr(frontend.Expr(e2), &info, &ctx.interner), 0)
	defer delete(result2)

	testing.expectf(t, result2 == "False", "expected {}, got {}", "False", result2)
}

@(test)
test_format_expr_identifier :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "myVar")

	e := new(frontend.Expr_Identifier)
	e.name = name_id
	e.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "myVar", "expected {}, got {}", "myVar", result)
}

@(test)
test_format_expr_call_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	f_id := base.intern(&ctx.interner, "f")
	a_id := base.intern(&ctx.interner, "a")
	b_id := base.intern(&ctx.interner, "b")

	f_expr := new(frontend.Expr_Identifier)
	f_expr.name = f_id
	f_expr.span = base.Source_Span_ZERO

	a_expr := new(frontend.Expr_Identifier)
	a_expr.name = a_id
	a_expr.span = base.Source_Span_ZERO

	b_expr := new(frontend.Expr_Identifier)
	b_expr.name = b_id
	b_expr.span = base.Source_Span_ZERO

	call := new(frontend.Expr_Call)
	call.callee = frontend.Expr(f_expr)
	call.args = make([dynamic]frontend.Expr)
	append(&call.args, frontend.Expr(a_expr))
	append(&call.args, frontend.Expr(b_expr))
	call.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(call), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "f(a, b)", "expected {}, got {}", "f(a, b)", result)
}

@(test)
test_format_expr_record_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "name")
	age_id := base.intern(&ctx.interner, "age")

	name_val := new(frontend.Expr_String)
	name_val.value = "\"Camp\""
	name_val.span = base.Source_Span_ZERO

	age_val := new(frontend.Expr_Int)
	age_val.value = 1
	age_val.span = base.Source_Span_ZERO

	field1 := frontend.Record_Field {
		name  = name_id,
		value = frontend.Expr(name_val),
		span  = base.Source_Span_ZERO,
	}
	field2 := frontend.Record_Field {
		name  = age_id,
		value = frontend.Expr(age_val),
		span  = base.Source_Span_ZERO,
	}

	rec := new(frontend.Expr_Record)
	rec.fields = make([dynamic]frontend.Record_Field)
	append(&rec.fields, field1)
	append(&rec.fields, field2)
	rec.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(rec), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "{ name: \"Camp\", age: 1 }",
		"expected {}, got {}",
		"{ name: \"Camp\", age: 1 }",
		result,
	)
}

@(test)
test_format_expr_list_single_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	one := new(frontend.Expr_Int)
	one.value = 1
	one.span = base.Source_Span_ZERO

	two := new(frontend.Expr_Int)
	two.value = 2
	two.span = base.Source_Span_ZERO

	three := new(frontend.Expr_Int)
	three.value = 3
	three.span = base.Source_Span_ZERO

	list := new(frontend.Expr_List)
	list.elements = make([dynamic]frontend.Expr)
	append(&list.elements, frontend.Expr(one))
	append(&list.elements, frontend.Expr(two))
	append(&list.elements, frontend.Expr(three))
	list.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(list), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "[1, 2, 3]", "expected {}, got {}", "[1, 2, 3]", result)
}

@(test)
test_format_expr_lambda_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	x_id := base.intern(&ctx.interner, "x")

	// Param: x
	param := frontend.Func_Param {
		name = x_id,
		span = base.Source_Span_ZERO,
	}

	// Body: x + 1
	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	one := new(frontend.Expr_Int)
	one.value = 1
	one.span = base.Source_Span_ZERO

	body := new(frontend.Expr_BinOp)
	body.op = .Plus
	body.left = frontend.Expr(x_expr)
	body.right = frontend.Expr(one)
	body.span = base.Source_Span_ZERO

	lam := new(frontend.Expr_Lambda)
	lam.params = make([dynamic]frontend.Func_Param)
	append(&lam.params, param)
	lam.body = frontend.Expr(body)
	lam.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(lam), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "|x| x + 1", "expected {}, got {}", "|x| x + 1", result)
}

@(test)
test_format_expr_block :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	x_id := base.intern(&ctx.interner, "x")
	y_id := base.intern(&ctx.interner, "y")

	// x = 1
	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	one := new(frontend.Expr_Int)
	one.value = 1
	one.span = base.Source_Span_ZERO

	assign1 := new(frontend.Expr_Assign)
	assign1.target = frontend.Expr(x_expr)
	assign1.value = frontend.Expr(one)
	assign1.span = base.Source_Span_ZERO

	// y = 2
	y_expr := new(frontend.Expr_Identifier)
	y_expr.name = y_id
	y_expr.span = base.Source_Span_ZERO

	two := new(frontend.Expr_Int)
	two.value = 2
	two.span = base.Source_Span_ZERO

	assign2 := new(frontend.Expr_Assign)
	assign2.target = frontend.Expr(y_expr)
	assign2.value = frontend.Expr(two)
	assign2.span = base.Source_Span_ZERO

	// x + y
	x_expr2 := new(frontend.Expr_Identifier)
	x_expr2.name = x_id
	x_expr2.span = base.Source_Span_ZERO

	y_expr2 := new(frontend.Expr_Identifier)
	y_expr2.name = y_id
	y_expr2.span = base.Source_Span_ZERO

	add_expr := new(frontend.Expr_BinOp)
	add_expr.op = .Plus
	add_expr.left = frontend.Expr(x_expr2)
	add_expr.right = frontend.Expr(y_expr2)
	add_expr.span = base.Source_Span_ZERO

	block := new(frontend.Expr_Block)
	block.statements = make([dynamic]frontend.Expr)
	append(&block.statements, frontend.Expr(assign1))
	append(&block.statements, frontend.Expr(assign2))
	append(&block.statements, frontend.Expr(add_expr))
	block.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(block), &info, &ctx.interner), 0)
	defer delete(result)

	expected := "{\n    x = 1\n    y = 2\n    x + y\n}"
	testing.expectf(t, result == expected, "expected {}, got {}", expected, result)
}

@(test)
test_format_expr_binop :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	x_id := base.intern(&ctx.interner, "x")
	y_id := base.intern(&ctx.interner, "y")

	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	y_expr := new(frontend.Expr_Identifier)
	y_expr.name = y_id
	y_expr.span = base.Source_Span_ZERO

	binop := new(frontend.Expr_BinOp)
	binop.op = .Plus
	binop.left = frontend.Expr(x_expr)
	binop.right = frontend.Expr(y_expr)
	binop.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_expr(frontend.Expr(binop), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x + y", "expected {}, got {}", "x + y", result)
}

@(test)
test_format_expr_if_braceless :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	x_id := base.intern(&ctx.interner, "x")
	zero_id := base.intern(&ctx.interner, "0")

	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	zero_expr := new(frontend.Expr_Int)
	zero_expr.value = 0
	zero_expr.span = base.Source_Span_ZERO

	// condition: x > 0
	zero_val := new(frontend.Expr_Int)
	zero_val.value = 0
	zero_val.span = base.Source_Span_ZERO

	cond := new(frontend.Expr_BinOp)
	cond.op = .Gt
	cond.left = frontend.Expr(x_expr)
	cond.right = frontend.Expr(zero_val)
	cond.span = base.Source_Span_ZERO

	// then: x
	then_expr := new(frontend.Expr_Identifier)
	then_expr.name = x_id
	then_expr.span = base.Source_Span_ZERO

	// else: 0
	else_expr := new(frontend.Expr_Int)
	else_expr.value = 0
	else_expr.span = base.Source_Span_ZERO

	if_expr := new(frontend.Expr_If)
	if_expr.condition = frontend.Expr(cond)
	if_expr.then_branch = frontend.Expr(then_expr)
	if_expr.else_branch = frontend.Expr(else_expr)
	if_expr.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(
		format.format_expr(frontend.Expr(if_expr), &info, &ctx.interner),
		0,
	)
	defer delete(result)

	testing.expectf(
		t,
		result == "if x > 0 x else 0",
		"expected {}, got {}",
		"if x > 0 x else 0",
		result,
	)
}

// --- Declaration Formatting Tests ---

@(test)
test_format_decl_const_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "greet")
	x_id := base.intern(&ctx.interner, "x")

	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	lam := new(frontend.Expr_Lambda)
	lam.params = make([dynamic]frontend.Func_Param)
	append(&lam.params, frontend.Func_Param{name = x_id, span = base.Source_Span_ZERO})
	lam.body = frontend.Expr(x_expr)
	lam.span = base.Source_Span_ZERO

	dc := new(frontend.Decl_Const)
	dc.name = name_id
	dc.body = frontend.Expr(lam)
	dc.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "greet = |x| x", "expected {}, got {}", "greet = |x| x", result)
}

@(test)
test_format_decl_const_with_type :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "x")
	int_id := base.intern(&ctx.interner, "Int")

	prim := new(frontend.Type_Primitive)
	prim.name = int_id
	prim.span = base.Source_Span_ZERO
	type_val := frontend.Type(prim)

	body_val := new(frontend.Expr_Int)
	body_val.value = 42
	body_val.span = base.Source_Span_ZERO

	dc := new(frontend.Decl_Const)
	dc.name = name_id
	dc.type_ann = &type_val
	dc.body = frontend.Expr(body_val)
	dc.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x: Int = 42", "expected {}, got {}", "x: Int = 42", result)
}

@(test)
test_format_decl_const_effectful :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "x")

	body_val := new(frontend.Expr_Int)
	body_val.value = 42
	body_val.span = base.Source_Span_ZERO

	dc := new(frontend.Decl_Const)
	dc.name = name_id
	dc.is_effectful = true
	dc.body = frontend.Expr(body_val)
	dc.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x! = 42", "expected {}, got {}", "x! = 42", result)
}

@(test)
test_format_decl_const_pub :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "greet")
	x_id := base.intern(&ctx.interner, "x")

	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	lam := new(frontend.Expr_Lambda)
	lam.params = make([dynamic]frontend.Func_Param)
	append(&lam.params, frontend.Func_Param{name = x_id, span = base.Source_Span_ZERO})
	lam.body = frontend.Expr(x_expr)
	lam.span = base.Source_Span_ZERO

	dc := new(frontend.Decl_Const)
	dc.is_pub = true
	dc.name = name_id
	dc.body = frontend.Expr(lam)
	dc.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "pub greet = |x| x",
		"expected {}, got {}",
		"pub greet = |x| x",
		result,
	)
}

@(test)
test_format_decl_effect_empty :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	name_id := base.intern(&ctx.interner, "Empty")

	de := new(frontend.Decl_Effect)
	de.name = name_id
	de.operations = make([dynamic]frontend.Effect_Op)
	de.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "Empty! : {}", "expected {}, got {}", "Empty! : {}", result)
}

@(test)
test_format_decl_effect_with_ops :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	io_id := base.intern(&ctx.interner, "IO")
	println_id := base.intern(&ctx.interner, "println")
	readln_id := base.intern(&ctx.interner, "readln")

	op1 := frontend.Effect_Op {
		name         = println_id,
		is_effectful = true,
		span         = base.Source_Span_ZERO,
	}
	op2 := frontend.Effect_Op {
		name         = readln_id,
		is_effectful = true,
		span         = base.Source_Span_ZERO,
	}

	de := new(frontend.Decl_Effect)
	de.name = io_id
	de.operations = make([dynamic]frontend.Effect_Op)
	append(&de.operations, op1)
	append(&de.operations, op2)
	de.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	expected := "IO! : {\n    println!\n    readln!\n}"
	testing.expectf(t, result == expected, "expected {}, got {}", expected, result)
}

@(test)
test_format_decl_import_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	di := new(frontend.Decl_Import)
	di.module = "List"
	di.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(di), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "import List", "expected {}, got {}", "import List", result)
}

@(test)
test_format_decl_import_exposing :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	map_id := base.intern(&ctx.interner, "map")
	filter_id := base.intern(&ctx.interner, "filter")

	di := new(frontend.Decl_Import)
	di.module = "List"
	di.names = make([dynamic]frontend.Import_Item)
	append(&di.names, frontend.Import_Item(map_id))
	append(&di.names, frontend.Import_Item(filter_id))
	di.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(di), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "import List { map, filter }",
		"expected {}, got {}",
		"import List { map, filter }",
		result,
	)
}

@(test)
test_format_decl_alias :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	myint_id := base.intern(&ctx.interner, "MyInt")
	int_id := base.intern(&ctx.interner, "Int")

	prim := new(frontend.Type_Primitive)
	prim.name = int_id
	prim.span = base.Source_Span_ZERO
	type_val := frontend.Type(prim)

	da := new(frontend.Decl_Alias)
	da.name = myint_id
	da.target = &type_val
	da.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(da), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "MyInt : Int", "expected {}, got {}", "MyInt : Int", result)
}

@(test)
test_format_decl_test :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	body_val := new(frontend.Expr_Int)
	body_val.value = 1

	dt := new(frontend.Decl_Test)
	dt.name = "\"addition works\""
	dt.body = frontend.Expr(body_val)
	dt.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(dt), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(
		t,
		result == "test \"addition works\" = 1",
		"expected {}, got {}",
		"test \"addition works\" = 1",
		result,
	)
}

@(test)
test_format_decl_expect :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	x_id := base.intern(&ctx.interner, "x")
	one_id := base.intern(&ctx.interner, "1")

	x_expr := new(frontend.Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = base.Source_Span_ZERO

	one_expr := new(frontend.Expr_Int)
	one_expr.value = 1
	one_expr.span = base.Source_Span_ZERO

	b := new(frontend.Expr_BinOp)
	b.op = .Eq_Eq
	b.left = frontend.Expr(x_expr)
	b.right = frontend.Expr(one_expr)
	b.span = base.Source_Span_ZERO

	de := new(frontend.Decl_Expect)
	de.condition = frontend.Expr(b)
	de.span = base.Source_Span_ZERO

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_decl(frontend.Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "expect x == 1", "expected {}, got {}", "expect x == 1", result)
}

@(test)
test_format_file_empty :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := frontend.File {
		path  = "test.camp",
		decls = make([dynamic]frontend.Decl),
		span  = base.Source_Span_ZERO,
	}

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "", "expected empty string, got {}", result)
}

@(test)
test_format_file_with_blank_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	a_id := base.intern(&ctx.interner, "a")
	b_id := base.intern(&ctx.interner, "b")

	one := new(frontend.Expr_Int)
	one.value = 1
	one.span = base.Source_Span_ZERO

	d1 := new(frontend.Decl_Const)
	d1.name = a_id
	d1.body = frontend.Expr(one)
	d1.span = base.Source_Span_ZERO

	two := new(frontend.Expr_Int)
	two.value = 2
	two.span = base.Source_Span_ZERO

	d2 := new(frontend.Decl_Const)
	d2.name = b_id
	d2.body = frontend.Expr(two)
	d2.span = base.Source_Span_ZERO

	file := frontend.File {
		path  = "test.camp",
		decls = make([dynamic]frontend.Decl),
		span  = base.Source_Span_ZERO,
	}
	append(&file.decls, frontend.Decl(d1))
	append(&file.decls, frontend.Decl(d2))

	info := format.Format_Source_Info {
		blank_line_after = make(map[int]bool),
	}
	info.blank_line_after[d1.span.start] = true

	result := format.doc_resolve(format.format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "a = 1\n\nb = 2", "expected {}, got {}", "a = 1\n\nb = 2", result)
}

@(test)
test_format_file_no_blank_line :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	a_id := base.intern(&ctx.interner, "a")
	b_id := base.intern(&ctx.interner, "b")

	one := new(frontend.Expr_Int)
	one.value = 1
	one.span = base.Source_Span_ZERO

	d1 := new(frontend.Decl_Const)
	d1.name = a_id
	d1.body = frontend.Expr(one)
	d1.span = base.Source_Span_ZERO

	two := new(frontend.Expr_Int)
	two.value = 2
	two.span = base.Source_Span_ZERO

	d2 := new(frontend.Decl_Const)
	d2.name = b_id
	d2.body = frontend.Expr(two)
	d2.span = base.Source_Span_ZERO

	file := frontend.File {
		path  = "test.camp",
		decls = make([dynamic]frontend.Decl),
		span  = base.Source_Span_ZERO,
	}
	append(&file.decls, frontend.Decl(d1))
	append(&file.decls, frontend.Decl(d2))

	info := format.Format_Source_Info{}
	result := format.doc_resolve(format.format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "a = 1\nb = 2", "expected {}, got {}", "a = 1\nb = 2", result)
}

// --- Integration tests for format.format() function ---

cleanup_format_result :: proc(result: ^format.Format_Result) {
	delete(result.output)
	for &d in result.diagnostics {
		delete(d.labels)
		delete(d.hints)
	}
	delete(result.diagnostics)
}

@(test)
test_format_simple_decl :: proc(t: ^testing.T) {
	result := format.format("x = 1", "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics, got {}",
		len(result.diagnostics),
	)
	testing.expectf(t, result.output == "x = 1", "expected {}, got {}", "x = 1", result.output)
}

@(test)
test_format_refuse_syntax_error :: proc(t: ^testing.T) {
	// Incomplete declaration: missing expression after =
	result := format.format("x = ", "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		result.output == "",
		"expected empty output for syntax error, got {}",
		result.output,
	)
	testing.expectf(t, len(result.diagnostics) > 0, "expected diagnostics for syntax error")
}

@(test)
test_format_idempotent_simple :: proc(t: ^testing.T) {
	source := "x = 1"
	result1 := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(
		t,
		len(result1.diagnostics) == 0,
		"expected no diagnostics on first format.format, got {}",
		len(result1.diagnostics),
	)

	result2 := format.format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(
		t,
		len(result2.diagnostics) == 0,
		"expected no diagnostics on second format.format, got {}",
		len(result2.diagnostics),
	)
	testing.expectf(
		t,
		result2.output == result1.output,
		"expected idempotent format.format: first={} second={}",
		result1.output,
		result2.output,
	)
}

@(test)
test_format_idempotent_lambda :: proc(t: ^testing.T) {
	source := "add = |x| x + 1"
	result1 := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(
		t,
		len(result1.diagnostics) == 0,
		"first format.format had errors: {}",
		len(result1.diagnostics),
	)

	result2 := format.format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(
		t,
		len(result2.diagnostics) == 0,
		"second format.format had errors: {}",
		len(result2.diagnostics),
	)
	testing.expectf(
		t,
		result2.output == result1.output,
		"not idempotent: first={} second={}",
		result1.output,
		result2.output,
	)
}

@(test)
test_format_idempotent_list :: proc(t: ^testing.T) {
	source := "items = [1, 2, 3]"
	result1 := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(
		t,
		len(result1.diagnostics) == 0,
		"first format.format had errors: {}",
		len(result1.diagnostics),
	)

	result2 := format.format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(
		t,
		len(result2.diagnostics) == 0,
		"second format.format had errors: {}",
		len(result2.diagnostics),
	)
	testing.expectf(
		t,
		result2.output == result1.output,
		"not idempotent: first={} second={}",
		result1.output,
		result2.output,
	)
}

@(test)
test_format_idempotent_record :: proc(t: ^testing.T) {
	source := "record = { name: \"Camp\" }"
	result1 := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(
		t,
		len(result1.diagnostics) == 0,
		"first format.format had errors: {}",
		len(result1.diagnostics),
	)

	result2 := format.format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(
		t,
		len(result2.diagnostics) == 0,
		"second format.format had errors: {}",
		len(result2.diagnostics),
	)
	testing.expectf(
		t,
		result2.output == result1.output,
		"not idempotent: first={} second={}",
		result1.output,
		result2.output,
	)
}

@(test)
test_format_idempotent_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	result1 := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(
		t,
		len(result1.diagnostics) == 0,
		"first format.format had errors: {}",
		len(result1.diagnostics),
	)

	result2 := format.format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(
		t,
		len(result2.diagnostics) == 0,
		"second format.format had errors: {}",
		len(result2.diagnostics),
	)
	testing.expectf(
		t,
		result2.output == result1.output,
		"not idempotent: first={} second={}",
		result1.output,
		result2.output,
	)
}

@(test)
test_format_edge_empty :: proc(t: ^testing.T) {
	source := ""
	result := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics for empty source, got {}",
		len(result.diagnostics),
	)
	testing.expectf(
		t,
		result.output == "",
		"expected empty output for empty source, got {}",
		result.output,
	)
}

@(test)
test_format_edge_single_decl :: proc(t: ^testing.T) {
	source := "y = 42"
	result := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics, got {}",
		len(result.diagnostics),
	)
	testing.expectf(t, result.output == "y = 42", "expected {}, got {}", "y = 42", result.output)
}

@(test)
test_format_multiline_list :: proc(t: ^testing.T) {
	source := "items = [\n    1,\n    2,\n]"
	result := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	diag_titles := ""
	for d in result.diagnostics {
		diag_titles = strings.concatenate({diag_titles, d.title, ", "}, context.allocator)
	}
	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics, got {}: %s",
		len(result.diagnostics),
		diag_titles,
	)

	testing.expectf(
		t,
		strings.contains(result.output, "\n"),
		"expected multiline output, got {}",
		result.output,
	)
}

@(test)
test_format_preserves_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	result := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics, got {}",
		len(result.diagnostics),
	)
	testing.expectf(
		t,
		strings.contains(result.output, "\n\n"),
		"expected blank line in output, got {}",
		result.output,
	)
}

@(test)
test_format_decl_newtype_pub_variants :: proc(t: ^testing.T) {
	source := "@Result(a, e) : pub [Ok(a) | Err(e)]"
	result := format.format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(
		t,
		len(result.diagnostics) == 0,
		"expected no diagnostics, got {}",
		len(result.diagnostics),
	)
	testing.expectf(
		t,
		result.output == "@Result(a, e) : pub [Ok(a) | Err(e)]",
		"expected {}, got {}",
		"@Result(a, e) : pub [Ok(a) | Err(e)]",
		result.output,
	)
}


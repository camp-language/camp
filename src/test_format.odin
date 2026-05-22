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

// --- Type Formatting Tests ---

@(test)
test_format_type_primitive :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name := intern(&ctx.interner, "Int")

	prim := new(Type_Primitive)
	prim.name = name
	prim.span = Source_Span_ZERO

	type_val := Type(prim)

	info := Format_Source_Info{}
	result := doc_resolve(format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "Int", "expected %q, got %q", "Int", result)
}

@(test)
test_format_type_applied_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	list_name := intern(&ctx.interner, "List")
	a_name := intern(&ctx.interner, "a")

	a_prim := new(Type_Primitive)
	a_prim.name = a_name
	a_prim.span = Source_Span_ZERO

	applied := new(Type_Applied)
	applied.name = list_name
	applied.args = make([dynamic]Type)
	append(&applied.args, Type(a_prim))
	applied.span = Source_Span_ZERO

	type_val := Type(applied)

	info := Format_Source_Info{}
	result := doc_resolve(format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "List(a)", "expected %q, got %q", "List(a)", result)
}

@(test)
test_format_type_tag_union_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	ok_name := intern(&ctx.interner, "Ok")
	err_name := intern(&ctx.interner, "Err")
	a_name := intern(&ctx.interner, "a")
	e_name := intern(&ctx.interner, "e")

	a_prim := new(Type_Primitive)
	a_prim.name = a_name
	a_prim.span = Source_Span_ZERO

	e_prim := new(Type_Primitive)
	e_prim.name = e_name
	e_prim.span = Source_Span_ZERO

	ok_payload := make([dynamic]Type)
	append(&ok_payload, Type(a_prim))

	err_payload := make([dynamic]Type)
	append(&err_payload, Type(e_prim))

	ok_tag := new(Type_Tag)
	ok_tag.name = ok_name
	ok_tag.payload = ok_payload
	ok_tag.span = Source_Span_ZERO

	err_tag := new(Type_Tag)
	err_tag.name = err_name
	err_tag.payload = err_payload
	err_tag.span = Source_Span_ZERO

	tags := make([dynamic]Type_Tag)
	append(&tags, ok_tag^)
	append(&tags, err_tag^)

	tag_union := new(Type_Tag_Union)
	tag_union.tags = tags
	tag_union.span = Source_Span_ZERO

	type_val := Type(tag_union)

	info := Format_Source_Info{}
	result := doc_resolve(format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "[Ok(a) | Err(e)]", "expected %q, got %q", "[Ok(a) | Err(e)]", result)
}

@(test)
test_format_type_record_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "name")
	age_id := intern(&ctx.interner, "age")
	str_id := intern(&ctx.interner, "Str")
	u64_id := intern(&ctx.interner, "U64")

	str_prim := new(Type_Primitive)
	str_prim.name = str_id
	str_prim.span = Source_Span_ZERO

	u64_prim := new(Type_Primitive)
	u64_prim.name = u64_id
	u64_prim.span = Source_Span_ZERO

	field1 := Type_Field{
		name = name_id,
		type = Type(str_prim),
		span = Source_Span_ZERO,
	}

	field2 := Type_Field{
		name = age_id,
		type = Type(u64_prim),
		span = Source_Span_ZERO,
	}

	fields := make([dynamic]Type_Field)
	append(&fields, field1)
	append(&fields, field2)

	rec := new(Type_Record)
	rec.fields = fields
	rec.span = Source_Span_ZERO

	type_val := Type(rec)

	info := Format_Source_Info{}
	result := doc_resolve(format_type(&type_val, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "{ name: Str, age: U64 }", "expected %q, got %q", "{ name: Str, age: U64 }", result)
}

// --- Expression Formatting Tests ---

@(test)
test_format_expr_int :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	e := new(Expr_Int)
	e.value = 42
	e.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "42", "expected %q, got %q", "42", result)
}

@(test)
test_format_expr_string :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	e := new(Expr_String)
	e.value = "hello"
	e.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "hello", "expected %q, got %q", "hello", result)
}

@(test)
test_format_expr_bool :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	e := new(Expr_Bool)
	e.value = true
	e.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "True", "expected %q, got %q", "True", result)

	e2 := new(Expr_Bool)
	e2.value = false
	e2.span = Source_Span_ZERO

	result2 := doc_resolve(format_expr(Expr(e2), &info, &ctx.interner), 0)
	defer delete(result2)

	testing.expectf(t, result2 == "False", "expected %q, got %q", "False", result2)
}

@(test)
test_format_expr_identifier :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "myVar")

	e := new(Expr_Identifier)
	e.name = name_id
	e.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(e), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "myVar", "expected %q, got %q", "myVar", result)
}

@(test)
test_format_expr_call_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	f_id := intern(&ctx.interner, "f")
	a_id := intern(&ctx.interner, "a")
	b_id := intern(&ctx.interner, "b")

	f_expr := new(Expr_Identifier)
	f_expr.name = f_id
	f_expr.span = Source_Span_ZERO

	a_expr := new(Expr_Identifier)
	a_expr.name = a_id
	a_expr.span = Source_Span_ZERO

	b_expr := new(Expr_Identifier)
	b_expr.name = b_id
	b_expr.span = Source_Span_ZERO

	call := new(Expr_Call)
	call.callee = Expr(f_expr)
	call.args = make([dynamic]Expr)
	append(&call.args, Expr(a_expr))
	append(&call.args, Expr(b_expr))
	call.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(call), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "f(a, b)", "expected %q, got %q", "f(a, b)", result)
}

@(test)
test_format_expr_record_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "name")
	age_id := intern(&ctx.interner, "age")

	name_val := new(Expr_String)
	name_val.value = "\"Camp\""
	name_val.span = Source_Span_ZERO

	age_val := new(Expr_Int)
	age_val.value = 1
	age_val.span = Source_Span_ZERO

	field1 := Record_Field{
		name = name_id,
		value = Expr(name_val),
		span = Source_Span_ZERO,
	}
	field2 := Record_Field{
		name = age_id,
		value = Expr(age_val),
		span = Source_Span_ZERO,
	}

	rec := new(Expr_Record)
	rec.fields = make([dynamic]Record_Field)
	append(&rec.fields, field1)
	append(&rec.fields, field2)
	rec.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(rec), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "{ name: \"Camp\", age: 1 }", "expected %q, got %q", "{ name: \"Camp\", age: 1 }", result)
}

@(test)
test_format_expr_list_single_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	one := new(Expr_Int)
	one.value = 1
	one.span = Source_Span_ZERO

	two := new(Expr_Int)
	two.value = 2
	two.span = Source_Span_ZERO

	three := new(Expr_Int)
	three.value = 3
	three.span = Source_Span_ZERO

	list := new(Expr_List)
	list.elements = make([dynamic]Expr)
	append(&list.elements, Expr(one))
	append(&list.elements, Expr(two))
	append(&list.elements, Expr(three))
	list.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(list), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "[1, 2, 3]", "expected %q, got %q", "[1, 2, 3]", result)
}

@(test)
test_format_expr_lambda_simple :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	x_id := intern(&ctx.interner, "x")

	// Param: x
	param := Func_Param{
		name = x_id,
		span = Source_Span_ZERO,
	}

	// Body: x + 1
	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	one := new(Expr_Int)
	one.value = 1
	one.span = Source_Span_ZERO

	body := new(Expr_BinOp)
	body.op = .Plus
	body.left = Expr(x_expr)
	body.right = Expr(one)
	body.span = Source_Span_ZERO

	lam := new(Expr_Lambda)
	lam.params = make([dynamic]Func_Param)
	append(&lam.params, param)
	lam.body = Expr(body)
	lam.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(lam), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "|x| x + 1", "expected %q, got %q", "|x| x + 1", result)
}

@(test)
test_format_expr_block :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	x_id := intern(&ctx.interner, "x")
	y_id := intern(&ctx.interner, "y")

	// x = 1
	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	one := new(Expr_Int)
	one.value = 1
	one.span = Source_Span_ZERO

	assign1 := new(Expr_Assign)
	assign1.target = Expr(x_expr)
	assign1.value = Expr(one)
	assign1.span = Source_Span_ZERO

	// y = 2
	y_expr := new(Expr_Identifier)
	y_expr.name = y_id
	y_expr.span = Source_Span_ZERO

	two := new(Expr_Int)
	two.value = 2
	two.span = Source_Span_ZERO

	assign2 := new(Expr_Assign)
	assign2.target = Expr(y_expr)
	assign2.value = Expr(two)
	assign2.span = Source_Span_ZERO

	// x + y
	x_expr2 := new(Expr_Identifier)
	x_expr2.name = x_id
	x_expr2.span = Source_Span_ZERO

	y_expr2 := new(Expr_Identifier)
	y_expr2.name = y_id
	y_expr2.span = Source_Span_ZERO

	add_expr := new(Expr_BinOp)
	add_expr.op = .Plus
	add_expr.left = Expr(x_expr2)
	add_expr.right = Expr(y_expr2)
	add_expr.span = Source_Span_ZERO

	block := new(Expr_Block)
	block.statements = make([dynamic]Expr)
	append(&block.statements, Expr(assign1))
	append(&block.statements, Expr(assign2))
	append(&block.statements, Expr(add_expr))
	block.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(block), &info, &ctx.interner), 0)
	defer delete(result)

	expected := "{\n    x = 1\n    y = 2\n    x + y\n}"
	testing.expectf(t, result == expected, "expected %q, got %q", expected, result)
}

@(test)
test_format_expr_binop :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	x_id := intern(&ctx.interner, "x")
	y_id := intern(&ctx.interner, "y")

	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	y_expr := new(Expr_Identifier)
	y_expr.name = y_id
	y_expr.span = Source_Span_ZERO

	binop := new(Expr_BinOp)
	binop.op = .Plus
	binop.left = Expr(x_expr)
	binop.right = Expr(y_expr)
	binop.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(binop), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x + y", "expected %q, got %q", "x + y", result)
}

@(test)
test_format_expr_if_braceless :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	x_id := intern(&ctx.interner, "x")
	zero_id := intern(&ctx.interner, "0")

	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	zero_expr := new(Expr_Int)
	zero_expr.value = 0
	zero_expr.span = Source_Span_ZERO

	// condition: x > 0
	zero_val := new(Expr_Int)
	zero_val.value = 0
	zero_val.span = Source_Span_ZERO

	cond := new(Expr_BinOp)
	cond.op = .Gt
	cond.left = Expr(x_expr)
	cond.right = Expr(zero_val)
	cond.span = Source_Span_ZERO

	// then: x
	then_expr := new(Expr_Identifier)
	then_expr.name = x_id
	then_expr.span = Source_Span_ZERO

	// else: 0
	else_expr := new(Expr_Int)
	else_expr.value = 0
	else_expr.span = Source_Span_ZERO

	if_expr := new(Expr_If)
	if_expr.condition = Expr(cond)
	if_expr.then_branch = Expr(then_expr)
	if_expr.else_branch = Expr(else_expr)
	if_expr.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_expr(Expr(if_expr), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "if x > 0 x else 0", "expected %q, got %q", "if x > 0 x else 0", result)
}

// --- Declaration Formatting Tests ---

@(test)
test_format_decl_const_simple :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "greet")
	x_id := intern(&ctx.interner, "x")

	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	lam := new(Expr_Lambda)
	lam.params = make([dynamic]Func_Param)
	append(&lam.params, Func_Param{name = x_id, span = Source_Span_ZERO})
	lam.body = Expr(x_expr)
	lam.span = Source_Span_ZERO

	dc := new(Decl_Const)
	dc.name = name_id
	dc.body = Expr(lam)
	dc.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "greet = |x| x", "expected %q, got %q", "greet = |x| x", result)
}

@(test)
test_format_decl_const_with_type :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "x")
	int_id := intern(&ctx.interner, "Int")

	prim := new(Type_Primitive)
	prim.name = int_id
	prim.span = Source_Span_ZERO
	type_val := Type(prim)

	body_val := new(Expr_Int)
	body_val.value = 42
	body_val.span = Source_Span_ZERO

	dc := new(Decl_Const)
	dc.name = name_id
	dc.type_ann = &type_val
	dc.body = Expr(body_val)
	dc.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x: Int = 42", "expected %q, got %q", "x: Int = 42", result)
}

@(test)
test_format_decl_const_effectful :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "x")

	body_val := new(Expr_Int)
	body_val.value = 42
	body_val.span = Source_Span_ZERO

	dc := new(Decl_Const)
	dc.name = name_id
	dc.is_effectful = true
	dc.body = Expr(body_val)
	dc.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "x! = 42", "expected %q, got %q", "x! = 42", result)
}

@(test)
test_format_decl_const_pub :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "greet")
	x_id := intern(&ctx.interner, "x")

	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	lam := new(Expr_Lambda)
	lam.params = make([dynamic]Func_Param)
	append(&lam.params, Func_Param{name = x_id, span = Source_Span_ZERO})
	lam.body = Expr(x_expr)
	lam.span = Source_Span_ZERO

	dc := new(Decl_Const)
	dc.is_pub = true
	dc.name = name_id
	dc.body = Expr(lam)
	dc.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(dc), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "pub greet = |x| x", "expected %q, got %q", "pub greet = |x| x", result)
}

@(test)
test_format_decl_effect_empty :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	name_id := intern(&ctx.interner, "Empty")

	de := new(Decl_Effect)
	de.name = name_id
	de.operations = make([dynamic]Effect_Op)
	de.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "Empty! : {}", "expected %q, got %q", "Empty! : {}", result)
}

@(test)
test_format_decl_effect_with_ops :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	io_id := intern(&ctx.interner, "IO")
	println_id := intern(&ctx.interner, "println")
	readln_id := intern(&ctx.interner, "readln")

	op1 := Effect_Op{name = println_id, is_effectful = true, span = Source_Span_ZERO}
	op2 := Effect_Op{name = readln_id, is_effectful = true, span = Source_Span_ZERO}

	de := new(Decl_Effect)
	de.name = io_id
	de.operations = make([dynamic]Effect_Op)
	append(&de.operations, op1)
	append(&de.operations, op2)
	de.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	expected := "IO! : {\n    println!\n    readln!\n}"
	testing.expectf(t, result == expected, "expected %q, got %q", expected, result)
}

@(test)
test_format_decl_import_simple :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	di := new(Decl_Import)
	di.module = "List"
	di.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(di), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "import List", "expected %q, got %q", "import List", result)
}

@(test)
test_format_decl_import_exposing :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	map_id := intern(&ctx.interner, "map")
	filter_id := intern(&ctx.interner, "filter")

	di := new(Decl_Import)
	di.module = "List"
	di.exposing = make([dynamic]Intern_ID)
	append(&di.exposing, map_id)
	append(&di.exposing, filter_id)
	di.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(di), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "import List exposing [map, filter]", "expected %q, got %q", "import List exposing [map, filter]", result)
}

@(test)
test_format_decl_alias :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	myint_id := intern(&ctx.interner, "MyInt")
	int_id := intern(&ctx.interner, "Int")

	prim := new(Type_Primitive)
	prim.name = int_id
	prim.span = Source_Span_ZERO
	type_val := Type(prim)

	da := new(Decl_Alias)
	da.name = myint_id
	da.target = &type_val
	da.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(da), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "MyInt : Int", "expected %q, got %q", "MyInt : Int", result)
}

@(test)
test_format_decl_test :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	body_val := new(Expr_Int)
	body_val.value = 1

	dt := new(Decl_Test)
	dt.name = "\"addition works\""
	dt.body = Expr(body_val)
	dt.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(dt), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "test \"addition works\" = 1", "expected %q, got %q", "test \"addition works\" = 1", result)
}

@(test)
test_format_decl_expect :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	x_id := intern(&ctx.interner, "x")
	one_id := intern(&ctx.interner, "1")

	x_expr := new(Expr_Identifier)
	x_expr.name = x_id
	x_expr.span = Source_Span_ZERO

	one_expr := new(Expr_Int)
	one_expr.value = 1
	one_expr.span = Source_Span_ZERO

	b := new(Expr_BinOp)
	b.op = .Eq_Eq
	b.left = Expr(x_expr)
	b.right = Expr(one_expr)
	b.span = Source_Span_ZERO

	de := new(Decl_Expect)
	de.condition = Expr(b)
	de.span = Source_Span_ZERO

	info := Format_Source_Info{}
	result := doc_resolve(format_decl(Decl(de), &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "expect x == 1", "expected %q, got %q", "expect x == 1", result)
}

@(test)
test_format_file_empty :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := File{
		path = "test.camp",
		decls = make([dynamic]Decl),
		span = Source_Span_ZERO,
	}

	info := Format_Source_Info{}
	result := doc_resolve(format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "", "expected empty string, got %q", result)
}

@(test)
test_format_file_with_blank_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	a_id := intern(&ctx.interner, "a")
	b_id := intern(&ctx.interner, "b")

	one := new(Expr_Int)
	one.value = 1
	one.span = Source_Span_ZERO

	d1 := new(Decl_Const)
	d1.name = a_id
	d1.body = Expr(one)
	d1.span = Source_Span_ZERO

	two := new(Expr_Int)
	two.value = 2
	two.span = Source_Span_ZERO

	d2 := new(Decl_Const)
	d2.name = b_id
	d2.body = Expr(two)
	d2.span = Source_Span_ZERO

	file := File{
		path = "test.camp",
		decls = make([dynamic]Decl),
		span = Source_Span_ZERO,
	}
	append(&file.decls, Decl(d1))
	append(&file.decls, Decl(d2))

	info := Format_Source_Info{
		blank_line_after = make(map[int]bool),
	}
	info.blank_line_after[d1.span.start] = true

	result := doc_resolve(format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "a = 1\n\nb = 2", "expected %q, got %q", "a = 1\n\nb = 2", result)
}

@(test)
test_format_file_no_blank_line :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	a_id := intern(&ctx.interner, "a")
	b_id := intern(&ctx.interner, "b")

	one := new(Expr_Int)
	one.value = 1
	one.span = Source_Span_ZERO

	d1 := new(Decl_Const)
	d1.name = a_id
	d1.body = Expr(one)
	d1.span = Source_Span_ZERO

	two := new(Expr_Int)
	two.value = 2
	two.span = Source_Span_ZERO

	d2 := new(Decl_Const)
	d2.name = b_id
	d2.body = Expr(two)
	d2.span = Source_Span_ZERO

	file := File{
		path = "test.camp",
		decls = make([dynamic]Decl),
		span = Source_Span_ZERO,
	}
	append(&file.decls, Decl(d1))
	append(&file.decls, Decl(d2))

	info := Format_Source_Info{}
	result := doc_resolve(format_file(file, &info, &ctx.interner), 0)
	defer delete(result)

	testing.expectf(t, result == "a = 1\nb = 2", "expected %q, got %q", "a = 1\nb = 2", result)
}

// --- Integration tests for format() function ---

cleanup_format_result :: proc(result: ^Format_Result) {
	delete(result.output)
	for &d in result.diagnostics {
		delete(d.labels)
		delete(d.hints)
	}
	delete(result.diagnostics)
}

@(test)
test_format_simple_decl :: proc(t: ^testing.T) {
	result := format("x = 1", "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics, got %d", len(result.diagnostics))
	testing.expectf(t, result.output == "x = 1",
		"expected %q, got %q", "x = 1", result.output)
}

@(test)
test_format_refuse_syntax_error :: proc(t: ^testing.T) {
	// Incomplete declaration: missing expression after =
	result := format("x = ", "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, result.output == "",
		"expected empty output for syntax error, got %q", result.output)
	testing.expectf(t, len(result.diagnostics) > 0,
		"expected diagnostics for syntax error")
}

@(test)
test_format_idempotent_simple :: proc(t: ^testing.T) {
	source := "x = 1"
	result1 := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(t, len(result1.diagnostics) == 0,
		"expected no diagnostics on first format, got %d", len(result1.diagnostics))

	result2 := format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(t, len(result2.diagnostics) == 0,
		"expected no diagnostics on second format, got %d", len(result2.diagnostics))
	testing.expectf(t, result2.output == result1.output,
		"expected idempotent format: first=%q second=%q", result1.output, result2.output)
}

@(test)
test_format_idempotent_lambda :: proc(t: ^testing.T) {
	source := "add = |x, y| x + y"
	result1 := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(t, len(result1.diagnostics) == 0,
		"first format had errors: %d", len(result1.diagnostics))

	result2 := format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(t, len(result2.diagnostics) == 0,
		"second format had errors: %d", len(result2.diagnostics))
	testing.expectf(t, result2.output == result1.output,
		"not idempotent: first=%q second=%q", result1.output, result2.output)
}

@(test)
test_format_idempotent_list :: proc(t: ^testing.T) {
	source := "items = [1, 2, 3]"
	result1 := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(t, len(result1.diagnostics) == 0,
		"first format had errors: %d", len(result1.diagnostics))

	result2 := format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(t, len(result2.diagnostics) == 0,
		"second format had errors: %d", len(result2.diagnostics))
	testing.expectf(t, result2.output == result1.output,
		"not idempotent: first=%q second=%q", result1.output, result2.output)
}

@(test)
test_format_idempotent_record :: proc(t: ^testing.T) {
	source := "record = { name: \"Camp\" }"
	result1 := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(t, len(result1.diagnostics) == 0,
		"first format had errors: %d", len(result1.diagnostics))

	result2 := format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(t, len(result2.diagnostics) == 0,
		"second format had errors: %d", len(result2.diagnostics))
	testing.expectf(t, result2.output == result1.output,
		"not idempotent: first=%q second=%q", result1.output, result2.output)
}

@(test)
test_format_idempotent_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	result1 := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result1)

	testing.expectf(t, len(result1.diagnostics) == 0,
		"first format had errors: %d", len(result1.diagnostics))

	result2 := format(result1.output, "test.camp", context.allocator)
	defer cleanup_format_result(&result2)

	testing.expectf(t, len(result2.diagnostics) == 0,
		"second format had errors: %d", len(result2.diagnostics))
	testing.expectf(t, result2.output == result1.output,
		"not idempotent: first=%q second=%q", result1.output, result2.output)
}

@(test)
test_format_edge_empty :: proc(t: ^testing.T) {
	source := ""
	result := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics for empty source, got %d", len(result.diagnostics))
	testing.expectf(t, result.output == "",
		"expected empty output for empty source, got %q", result.output)
}

@(test)
test_format_edge_single_decl :: proc(t: ^testing.T) {
	source := "y = 42"
	result := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics, got %d", len(result.diagnostics))
	testing.expectf(t, result.output == "y = 42",
		"expected %q, got %q", "y = 42", result.output)
}

@(test)
test_format_multiline_list :: proc(t: ^testing.T) {
	source := "items = [\n    1,\n    2,\n]"
	result := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	diag_titles := ""
	for d in result.diagnostics {
		diag_titles = strings.concatenate({diag_titles, d.title, ", "}, context.allocator)
	}
	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics, got %d: %s", len(result.diagnostics), diag_titles)

	testing.expectf(t, strings.contains(result.output, "\n"),
		"expected multiline output, got %q", result.output)
}

@(test)
test_format_preserves_blank_line :: proc(t: ^testing.T) {
	source := "x = 1\n\ny = 2"
	result := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics, got %d", len(result.diagnostics))
	testing.expectf(t, strings.contains(result.output, "\n\n"),
		"expected blank line in output, got %q", result.output)
}

@(test)
test_format_decl_newtype_pub_variants :: proc(t: ^testing.T) {
	source := "@Result(a, e) : pub [Ok(a) | Err(e)]"
	result := format(source, "test.camp", context.allocator)
	defer cleanup_format_result(&result)

	testing.expectf(t, len(result.diagnostics) == 0,
		"expected no diagnostics, got %d", len(result.diagnostics))
	testing.expectf(t, result.output == "@Result(a, e) : pub [Ok(a) | Err(e)]",
		"expected %q, got %q", "@Result(a, e) : pub [Ok(a) | Err(e)]", result.output)
}

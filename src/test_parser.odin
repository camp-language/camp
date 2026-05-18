package camp

import "core:testing"

parse_expr :: proc(source: string, ctx: ^Compilation_Context) -> Expr {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := parser_parse_expr(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_parser_integer_literal :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("42", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Int:
		testing.expect(t, e.value == 42)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_tag :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("Ok(42)", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Tag:
		testing.expect(t, len(e.payload) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_addition :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("1 + 2", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_BinOp:
		testing.expect(t, e.op == .Plus)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_lambda :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("|x| x + 1", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Lambda:
		testing.expect(t, len(e.params) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_if_else :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("if True 1 else 2", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_If:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("{ name: \"Camp\", age: 1 }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Record:
		testing.expect(t, len(e.fields) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_match :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("match x { Ok(v) => v | Err(e) => 0 }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Match:
		testing.expect(t, len(e.arms) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_method_call :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("list.iter().map(|x| x + 1)", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Method_Call:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record_update :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("{ ..record, name: \"new\" }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Record:
		testing.expect(t, len(e.fields) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_handle :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("handle IO in { 42 } with { .println!(resume) => resume({}) }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Handle:
		testing.expect(t, e.is_shallow == false)
		testing.expect(t, len(e.arms) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_intercept :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("intercept IO in { 42 } with { .println!(resume) => resume({}) }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Handle:
		testing.expect(t, e.is_shallow == true)
		testing.expect(t, len(e.arms) == 1)
	case:
		testing.expect(t, false)
	}
}

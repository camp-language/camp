package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "core:testing"

parse_expr :: proc(source: string, ctx: ^build.Compilation_Context) -> frontend.Expr {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := base.Source_File {
		path     = "<test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := frontend.parser_parse_expr(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_parser_integer_literal :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("42", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Int:
		testing.expect(t, e.value == 42)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_tag :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("Ok(42)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Tag:
		testing.expect(t, len(e.payload) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_addition :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("1 + 2", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_BinOp:
		testing.expect(t, e.op == .Plus)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_lambda :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("|x| x + 1", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Lambda:
		testing.expect(t, len(e.params) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_if_else :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("if True { 1 } else { 2 }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_If:
		testing.expect(t, e.condition != nil)
		testing.expect(t, e.then_branch != nil)
		testing.expect(t, e.else_branch != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("{ name: \"Camp\", age: 1 }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Record:
		testing.expect(t, len(e.fields) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_match :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("match x {\n    Ok(v) => v\n    Err(e) => 0\n}", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Match:
		testing.expect(t, len(e.arms) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_method_call :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("list.iter().map(|x| x + 1)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Method_Call:
		testing.expect(t, e.method != base.NO_NAME)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record_update :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("{ ..record, name: \"new\" }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Record:
		testing.expect(t, len(e.fields) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_handle :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("handle IO in { 42 } with { .println!(resume) => resume({}) }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Handle:
		testing.expect(t, len(e.arms) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_method :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr(".foo(x)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^frontend.Expr_Method_Call:
			testing.expect(t, len(body.args) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_field :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr(".name", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^frontend.Expr_Field_Access:
			testing.expect(t, body.field != base.NO_NAME)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_chained :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr(".foo().bar(x)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^frontend.Expr_Method_Call:
			testing.expect(t, body.method != base.NO_NAME)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

parse_decl :: proc(source: string, ctx: ^build.Compilation_Context) -> frontend.Decl {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := base.Source_File {
		path     = "<test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := frontend.parser_parse_decl(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_parser_newtype_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	decl := parse_decl("@UserId : U64", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^frontend.Decl_Newtype:
		testing.expect(t, !d.is_pub)
		testing.expect(t, len(d.type_params) == 0)
		testing.expect(t, d.inner_type != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_parameterized :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	decl := parse_decl("@Result(a, e) : [Ok(a) | Err(e)]", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^frontend.Decl_Newtype:
		testing.expect(t, len(d.type_params) == 2)
		testing.expect(t, d.inner_type != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_pub :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	decl := parse_decl("pub @UserId : U64", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^frontend.Decl_Newtype:
		testing.expect(t, d.is_pub)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_pub_variants :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	decl := parse_decl("@Result(a, e) : pub [Ok(a) | Err(e)]", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^frontend.Decl_Newtype:
		testing.expect(t, d.pub_variants)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_mixed :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr(".record.field.method(x)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Dot_Lambda:
		testing.expect(t, e.body != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parse_simple_interpolation :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("\"Hello ${name}!\"", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Interpolated_String:
		testing.expect(t, len(e.parts) == 3)
		#partial switch p0 in e.parts[0] {
		case ^frontend.String_Segment:
			testing.expect(t, p0.text == "Hello ")
		case:
			testing.expect(t, false)
		}
		#partial switch p1 in e.parts[1] {
		case frontend.Expr:
			#partial switch inner in p1 {
			case ^frontend.Expr_Identifier:
			// name — success
			case:
				testing.expect(t, false)
			}
		case:
			testing.expect(t, false)
		}
		#partial switch p2 in e.parts[2] {
		case ^frontend.String_Segment:
			testing.expect(t, p2.text == "!")
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parse_expression_interpolation :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("\"${x + y}\"", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Interpolated_String:
		testing.expect(t, len(e.parts) == 1)
		#partial switch p0 in e.parts[0] {
		case frontend.Expr:
			#partial switch inner in p0 {
			case ^frontend.Expr_BinOp:
				testing.expect(t, inner.op == .Plus)
			case:
				testing.expect(t, false)
			}
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_nominal_construct :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("@UserId(42)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Nominal_Construct:
		testing.expect(t, e.variant == 0)
		testing.expect(t, len(e.payload) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_nominal_construct_qualified :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	expr := parse_expr("@Result.Ok(42)", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Nominal_Construct:
		testing.expect(t, e.variant != 0)
		testing.expect(t, len(e.payload) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_nominal_destructure :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	// Parse a match arm with @ destructure
	expr := parse_expr("match x { @UserId(n) => n }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^frontend.Expr_Match:
		testing.expect(t, len(e.arms) == 1)
		#partial switch pat in e.arms[0].pattern {
		case ^frontend.Pattern_Destructure:
			testing.expect(t, pat.type_name != 0)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}


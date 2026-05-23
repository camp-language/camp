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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_If:
		testing.expect(t, e.condition != nil)
		testing.expect(t, e.then_branch != nil)
		testing.expect(t, e.else_branch != nil)
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Method_Call:
		testing.expect(t, e.method != NO_NAME)
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
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
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Handle:
		testing.expect(t, e.is_shallow == true)
		testing.expect(t, len(e.arms) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_method :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".foo(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Method_Call:
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
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".name", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Field_Access:
			testing.expect(t, body.field != NO_NAME)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_chained :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".foo().bar(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Method_Call:
			testing.expect(t, body.method != NO_NAME)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

parse_decl :: proc(source: string, ctx: ^Compilation_Context) -> Decl {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := parser_parse_decl(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_parser_newtype_simple :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	decl := parse_decl("@UserId : U64", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^Decl_Newtype:
		testing.expect(t, !d.is_pub)
		testing.expect(t, len(d.type_params) == 0)
		testing.expect(t, len(d.trait_conforms) == 0)
		testing.expect(t, d.inner_type != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_parameterized :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	decl := parse_decl("@Result(a, e) : [Ok(a) | Err(e)]", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^Decl_Newtype:
		testing.expect(t, len(d.type_params) == 2)
		testing.expect(t, d.inner_type != nil)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_with_trait :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	decl := parse_decl("@UserId is Hash : U64", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^Decl_Newtype:
		testing.expect(t, len(d.trait_conforms) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_pub :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	decl := parse_decl("pub @UserId : U64", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^Decl_Newtype:
		testing.expect(t, d.is_pub)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_newtype_pub_variants :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	decl := parse_decl("@Result(a, e) : pub [Ok(a) | Err(e)]", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch d in decl {
	case ^Decl_Newtype:
		testing.expect(t, d.pub_variants)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_dot_lambda_mixed :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".record.field.method(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parse_simple_interpolation :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("\"Hello ${name}!\"", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Interpolated_String:
		testing.expect(t, len(e.parts) == 3)
		testing.expect(t, !e.is_raw)
		testing.expect(t, !e.is_multiline)
		#partial switch p0 in e.parts[0] {
		case ^String_Segment:
			testing.expect(t, p0.text == "Hello ")
		case:
			testing.expect(t, false)
		}
		#partial switch p1 in e.parts[1] {
		case Expr:
			#partial switch inner in p1 {
			case ^Expr_Identifier:
				// name — success
			case:
				testing.expect(t, false)
			}
		case:
			testing.expect(t, false)
		}
		#partial switch p2 in e.parts[2] {
		case ^String_Segment:
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
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("\"${x + y}\"", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Interpolated_String:
		testing.expect(t, len(e.parts) == 1)
		testing.expect(t, !e.is_raw)
		testing.expect(t, !e.is_multiline)
		#partial switch p0 in e.parts[0] {
		case Expr:
			#partial switch inner in p0 {
			case ^Expr_BinOp:
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
test_parse_raw_string_interpolation :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("r\"Hello ${name}!\"", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Interpolated_String:
		testing.expect(t, e.is_raw)
		testing.expect(t, !e.is_multiline)
		testing.expect(t, len(e.parts) == 3)
		#partial switch p1 in e.parts[1] {
		case Expr:
			#partial switch inner in p1 {
			case ^Expr_Identifier:
				// name — success
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
test_parse_multiline_string_interpolation :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr("\"\"\"Hello ${name}!\"\"\"", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Interpolated_String:
		testing.expect(t, !e.is_raw)
		testing.expect(t, e.is_multiline)
		testing.expect(t, len(e.parts) == 3)
		#partial switch p1 in e.parts[1] {
		case Expr:
			#partial switch inner in p1 {
			case ^Expr_Identifier:
				// name — success
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

package camp

import "core:testing"

parse_expr :: proc(source: string) -> (Expr, ^Error_Collector) {
	collector: ^Error_Collector = new(Error_Collector)
	collector_init(collector)

	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, collector, &table)

	parser: Parser
	parser_init(&parser, &lexer, collector, &table)

	return parser_parse_expr(&parser), collector
}

@(test)
test_parser_integer_literal :: proc(t: ^testing.T) {
	expr, collector := parse_expr("42")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Int:
		testing.expect(t, e.value == 42)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_tag :: proc(t: ^testing.T) {
	expr, collector := parse_expr("Ok(42)")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Tag:
		testing.expect(t, len(e.payload) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_addition :: proc(t: ^testing.T) {
	expr, collector := parse_expr("1 + 2")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_BinOp:
		testing.expect(t, e.op == .Plus)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_lambda :: proc(t: ^testing.T) {
	expr, collector := parse_expr("|x| x + 1")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Lambda:
		testing.expect(t, len(e.params) == 1)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_if_else :: proc(t: ^testing.T) {
	expr, collector := parse_expr("if True 1 else 2")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_If:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record :: proc(t: ^testing.T) {
	expr, collector := parse_expr("{ name: \"Camp\", age: 1 }")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Record:
		testing.expect(t, len(e.fields) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_match :: proc(t: ^testing.T) {
	expr, collector := parse_expr("match x { Ok(v) => v | Err(e) => 0 }")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Match:
		testing.expect(t, len(e.arms) == 2)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_method_call :: proc(t: ^testing.T) {
	expr, collector := parse_expr("list.iter().map(|x| x + 1)")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Method_Call:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_parser_record_update :: proc(t: ^testing.T) {
	expr, collector := parse_expr("{ ..record, name: \"new\" }")
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	#partial switch e in expr {
	case ^Expr_Record:
		testing.expect(t, len(e.fields) == 1)
	case:
		testing.expect(t, false)
	}
}

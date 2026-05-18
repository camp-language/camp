package camp

import "core:testing"

canon_file :: proc(source: string) -> (CFile, ^Compilation_Context) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	context.allocator = alloc

	table: ^Intern_Table = &ctx.interner
	collector: ^Diagnostic_Collector = &ctx.collector

	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, collector, table)

	parser: Parser
	parser_init(&parser, &lexer, collector, table)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)
	return canon, ctx
}

@(test)
test_canonicalize_const :: proc(t: ^testing.T) {
	file, ctx := canon_file("x = 42")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		testing.expect(t, decl.name.is_local == true)
		testing.expect(t, !decl.is_effectful)
		#partial switch expr in decl.body {
		case ^CExpr_Int:
			testing.expect(t, expr.value == 42)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_effectful_const :: proc(t: ^testing.T) {
	file, ctx := canon_file("main! = || { 42 }")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		testing.expect(t, decl.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_record_sorted :: proc(t: ^testing.T) {
	file, ctx := canon_file("r = { age: 1, name: \"Camp\" }")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Record:
			testing.expect(t, len(expr.fields) == 2)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_import :: proc(t: ^testing.T) {
	file, ctx := canon_file("import List exposing [map]")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.imports) == 1)
	testing.expect(t, len(file.imports[0].exposing) == 1)
}

@(test)
test_canonicalize_lambda :: proc(t: ^testing.T) {
	file, ctx := canon_file("add = |x, y| x + y")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Lambda:
			testing.expect(t, len(expr.params) == 2)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_handle :: proc(t: ^testing.T) {
	file, ctx := canon_file("main! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		testing.expect(t, decl.is_effectful == true)
		#partial switch expr in decl.body {
		case ^CExpr_Handle:
			testing.expect(t, expr.is_shallow == false)
			testing.expect(t, len(expr.arms) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

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
test_canonicalize_dot_lambda_method :: proc(t: ^testing.T) {
	file, ctx := canon_file("f = .foo(x)")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^CExpr_Method_Call:
				testing.expect(t, true)
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
test_canonicalize_dot_lambda_field :: proc(t: ^testing.T) {
	file, ctx := canon_file("f = .name")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^CExpr_Field_Access:
				testing.expect(t, true)
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

// ---------------------------------------------------------------------------
// Cache-key acceptance: structural form of canonical IR must be invariant
// under edits that only change whitespace/comments. Spans (held off-tree in
// CFile.spans) may differ; the tree shape must not.
//
// The structural_print_* renderer used here now lives in canonical_hash.odin
// (it's also consumed by the query layer in query.odin).
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Cache-key acceptance: structural form of canonical IR must be invariant
// under edits that only change whitespace/comments. Spans (held off-tree in
// CFile.spans) may differ; the tree shape must not.
//
// The structural_print_* renderer used here now lives in canonical_hash.odin
// (also consumed by the query layer in query.odin).
// ---------------------------------------------------------------------------

import "core:fmt"

assert_same_structure :: proc(t: ^testing.T, a, b: string, label: string) {
	file_a, ctx_a := canon_file(a)
	defer context_destroy(ctx_a)
	defer free(ctx_a)
	file_b, ctx_b := canon_file(b)
	defer context_destroy(ctx_b)
	defer free(ctx_b)

	sa := structural_print_file(file_a)
	sb := structural_print_file(file_b)
	if sa != sb {
		fmt.printf("\n%s: structures differ\n--- A ---\n%s\n--- B ---\n%s\n", label, sa, sb)
	}
	testing.expect(t, sa == sb, label)
}

@(test)
test_cache_key_whitespace_invariant :: proc(t: ^testing.T) {
	assert_same_structure(t,
		"x = 42",
		"x    =\n  42",
		"whitespace")

	assert_same_structure(t,
		"add = |a, b| a + b",
		"add   =  |a,  b|   a  +  b",
		"lambda spacing")

	assert_same_structure(t,
		"main! = || { 1\n2\n3 }",
		"main! = || {\n\n  1\n\n  2\n  3\n\n}",
		"block spacing")
}

// Comment-invariance will be added once camp grows a comment token.
// The lexer currently maps '#' to Token.Hash, not a skip-token.

@(test)
test_cache_key_meaningful_change_differs :: proc(t: ^testing.T) {
	// Sanity check: a real semantic edit must produce different structure.
	file_a, ctx_a := canon_file("x = 42")
	defer context_destroy(ctx_a)
	defer free(ctx_a)
	file_b, ctx_b := canon_file("x = 43")
	defer context_destroy(ctx_b)
	defer free(ctx_b)

	sa := structural_print_file(file_a)
	sb := structural_print_file(file_b)
	testing.expect(t, sa != sb, "different literals must produce different structure")
}

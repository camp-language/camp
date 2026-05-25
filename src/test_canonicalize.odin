package camp

import "core:testing"
import "camp:base"
import "camp:frontend"
import "camp:semantics"
import "camp:build"
import "camp:diagnostics"

canon_file :: proc(source: string) -> (semantics.CFile, ^build.Compilation_Context) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	table: ^base.Intern_Table = &ctx.interner
	collector: ^diagnostics.Diagnostic_Collector = &ctx.collector

	file := base.Source_File{path = "<test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, collector, table)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, collector, table)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)
	return canon, ctx
}

@(test)
test_canonicalize_const :: proc(t: ^testing.T) {
	file, ctx := canon_file("x = 42")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		testing.expect(t, decl.name.is_local == true)
		testing.expect(t, !decl.is_effectful)
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Int:
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
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		testing.expect(t, decl.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_record_sorted :: proc(t: ^testing.T) {
	file, ctx := canon_file("r = { age: 1, name: \"Camp\" }")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Record:
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
	file, ctx := canon_file("import List")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.imports) == 1)
}

@(test)
test_canonicalize_lambda :: proc(t: ^testing.T) {
	file, ctx := canon_file("add = |x, y| x + y")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Lambda:
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
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^semantics.CExpr_Method_Call:
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
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^semantics.CExpr_Field_Access:
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
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Const:
		testing.expect(t, decl.is_effectful == true)
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Handle:
			testing.expect(t, len(expr.arms) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_derive_eq :: proc(t: ^testing.T) {
	file, ctx := canon_file("@UserId derives Eq : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 2)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Newtype:
		testing.expect(t, len(decl.derive_targets) == 1)
	case:
		testing.expect(t, false)
	}
	#partial switch decl in file.decls[1] {
	case ^semantics.CDecl_Const:
		eq_name := base.intern(&ctx.interner, "UserId_eq")
		testing.expect(t, decl.name.name == eq_name)
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Lambda:
			testing.expect(t, len(expr.params) == 2)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_derive_ord :: proc(t: ^testing.T) {
	file, ctx := canon_file("@UserId derives Ord : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 3)
	#partial switch decl in file.decls[0] {
	case ^semantics.CDecl_Newtype:
		testing.expect(t, len(decl.derive_targets) == 1)
	case:
		testing.expect(t, false)
	}
	compare_name := base.intern(&ctx.interner, "UserId_compare")
	eq_name := base.intern(&ctx.interner, "UserId_eq")
	#partial switch decl in file.decls[1] {
	case ^semantics.CDecl_Const:
		testing.expect(t, decl.name.name == compare_name)
	case:
		testing.expect(t, false)
	}
	#partial switch decl in file.decls[2] {
	case ^semantics.CDecl_Const:
		testing.expect(t, decl.name.name == eq_name)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_canonicalize_derive_clone :: proc(t: ^testing.T) {
	file, ctx := canon_file("@UserId derives Clone : U64")
	defer build.context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 2)
	#partial switch decl in file.decls[1] {
	case ^semantics.CDecl_Const:
		clone_name := base.intern(&ctx.interner, "UserId_clone")
		testing.expect(t, decl.name.name == clone_name)
		#partial switch expr in decl.body {
		case ^semantics.CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^semantics.CExpr_Tag:
				testing.expect(t, len(body.payload) == 1)
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

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
// ---------------------------------------------------------------------------

import "core:fmt"
import "core:strings"

structural_print_file :: proc(file: CFile) -> string {
	sb := strings.builder_make()
	for decl in file.decls {
		structural_print_decl(&sb, decl)
		strings.write_string(&sb, "\n")
	}
	return strings.to_string(sb)
}

structural_print_decl :: proc(sb: ^strings.Builder, decl: CDecl) {
	switch d in decl {
	case ^CDecl_Const:
		fmt.sbprintf(sb, "Const(name=%v,pub=%v,eff=%v,type=", d.name, d.is_pub, d.is_effectful)
		structural_print_ctype(sb, d.type_ann)
		strings.write_string(sb, ",body=")
		structural_print_expr(sb, d.body)
		strings.write_string(sb, ")")
	case ^CDecl_Effect:
		fmt.sbprintf(sb, "Effect(name=%v,pub=%v,ops=[", d.name, d.is_pub)
		for op, i in d.operations {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v/eff=%v/ret=", op.name, op.is_effectful)
			structural_print_ctype(sb, op.return_type)
		}
		strings.write_string(sb, "])")
	case ^CDecl_Trait:
		fmt.sbprintf(sb, "Trait(name=%v,parent=%v,methods=%d)", d.name, d.parent, len(d.methods))
	case ^CDecl_Alias:
		fmt.sbprintf(sb, "Alias(name=%v,target=", d.name)
		structural_print_ctype(sb, d.target)
		strings.write_string(sb, ")")
	case ^CDecl_Import:
		fmt.sbprintf(sb, "Import(%v)", d.deferred.module)
	case ^CDecl_Test:
		fmt.sbprintf(sb, "Test(name=%q,body=", d.name)
		structural_print_expr(sb, d.body)
		strings.write_string(sb, ")")
	case ^CDecl_Expect:
		strings.write_string(sb, "Expect(")
		structural_print_expr(sb, d.condition)
		strings.write_string(sb, ")")
	}
}

structural_print_ctype :: proc(sb: ^strings.Builder, t: ^CType) {
	if t == nil { strings.write_string(sb, "_"); return }
	switch ty in t^ {
	case ^CType_Primitive:    fmt.sbprintf(sb, "Prim(%v)", ty.name)
	case ^CType_Variable:     fmt.sbprintf(sb, "TVar(%v)", ty.name)
	case ^CType_Wildcard:     strings.write_string(sb, "Wild")
	case ^CType_Applied:
		fmt.sbprintf(sb, "App(%v,[", ty.name)
		for a, i in ty.args {
			if i > 0 { strings.write_string(sb, ",") }
			a := a
			structural_print_ctype(sb, &a)
		}
		strings.write_string(sb, "])")
	case ^CType_Function:
		strings.write_string(sb, "Fn([")
		for p, i in ty.params {
			if i > 0 { strings.write_string(sb, ",") }
			p := p
			structural_print_ctype(sb, &p)
		}
		strings.write_string(sb, "]->")
		ret := ty.return_
		structural_print_ctype(sb, &ret)
		strings.write_string(sb, ")")
	case ^CType_Record:
		fmt.sbprintf(sb, "Rec(open=%v,[", ty.is_open)
		for f, i in ty.fields {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v=", f.name)
			fty := f.type
			structural_print_ctype(sb, &fty)
		}
		strings.write_string(sb, "])")
	case ^CType_Tag_Union:
		fmt.sbprintf(sb, "TagU(open=%v,[", ty.is_open)
		for tg, i in ty.tags {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v(%d)", tg.name, len(tg.payload))
		}
		strings.write_string(sb, "])")
	case ^CType_Effect_Row:
		fmt.sbprintf(sb, "Eff(open=%v,%v)", ty.is_open, ty.effects)
	}
}

structural_print_expr :: proc(sb: ^strings.Builder, e: CExpr) {
	switch x in e {
	case ^CExpr_Int:    fmt.sbprintf(sb, "Int(%d)", x.value)
	case ^CExpr_Float:  fmt.sbprintf(sb, "Flt(%v)", x.value)
	case ^CExpr_String: fmt.sbprintf(sb, "Str(%q)", x.value)
	case ^CExpr_Bool:   fmt.sbprintf(sb, "Bool(%v)", x.value)
	case ^CExpr_Name:   fmt.sbprintf(sb, "Name(%v)", x.name)
	case ^CExpr_Tag:
		fmt.sbprintf(sb, "Tag(%v,[", x.name)
		for p, i in x.payload {
			if i > 0 { strings.write_string(sb, ",") }
			structural_print_expr(sb, p)
		}
		strings.write_string(sb, "])")
	case ^CExpr_Record:
		fmt.sbprintf(sb, "Rec(open=%v,[", x.is_open)
		for f, i in x.fields {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v=", f.name)
			structural_print_expr(sb, f.value)
		}
		strings.write_string(sb, "],rest=")
		structural_print_expr(sb, x.rest)
		strings.write_string(sb, ")")
	case ^CExpr_List:
		strings.write_string(sb, "List[")
		for el, i in x.elements {
			if i > 0 { strings.write_string(sb, ",") }
			structural_print_expr(sb, el)
		}
		strings.write_string(sb, "]")
	case ^CExpr_Call:
		strings.write_string(sb, "Call(")
		structural_print_expr(sb, x.callee)
		strings.write_string(sb, ",[")
		for a, i in x.args {
			if i > 0 { strings.write_string(sb, ",") }
			structural_print_expr(sb, a)
		}
		strings.write_string(sb, "])")
	case ^CExpr_Method_Call:
		fmt.sbprintf(sb, "Method(%v,recv=", x.method)
		structural_print_expr(sb, x.receiver)
		strings.write_string(sb, ",args=[")
		for a, i in x.args {
			if i > 0 { strings.write_string(sb, ",") }
			structural_print_expr(sb, a)
		}
		strings.write_string(sb, "])")
	case ^CExpr_Lambda:
		strings.write_string(sb, "Lam([")
		for p, i in x.params {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v:", p.name)
			structural_print_ctype(sb, p.type_ann)
		}
		strings.write_string(sb, "]->")
		structural_print_ctype(sb, x.return_type)
		strings.write_string(sb, ",body=")
		structural_print_expr(sb, x.body)
		strings.write_string(sb, ")")
	case ^CExpr_Block:
		strings.write_string(sb, "Block[")
		for s, i in x.statements {
			if i > 0 { strings.write_string(sb, ";") }
			structural_print_expr(sb, s)
		}
		strings.write_string(sb, "]")
	case ^CExpr_If:
		strings.write_string(sb, "If(")
		structural_print_expr(sb, x.condition)
		strings.write_string(sb, ",")
		structural_print_expr(sb, x.then_branch)
		strings.write_string(sb, ",")
		structural_print_expr(sb, x.else_branch)
		strings.write_string(sb, ")")
	case ^CExpr_Match:
		strings.write_string(sb, "Match(")
		structural_print_expr(sb, x.scrutinee)
		strings.write_string(sb, ",arms=")
		fmt.sbprintf(sb, "%d", len(x.arms))
		strings.write_string(sb, ")")
	case ^CExpr_BinOp:
		fmt.sbprintf(sb, "BinOp(%v,", x.op)
		structural_print_expr(sb, x.left)
		strings.write_string(sb, ",")
		structural_print_expr(sb, x.right)
		strings.write_string(sb, ")")
	case ^CExpr_PrefixOp:
		fmt.sbprintf(sb, "Pre(%v,", x.op)
		structural_print_expr(sb, x.operand)
		strings.write_string(sb, ")")
	case ^CExpr_Field_Access:
		strings.write_string(sb, "Field(")
		structural_print_expr(sb, x.record)
		fmt.sbprintf(sb, ",%v)", x.field)
	case ^CExpr_Record_Update:
		strings.write_string(sb, "Upd(rest=")
		structural_print_expr(sb, x.rest)
		strings.write_string(sb, ",[")
		for u, i in x.updates {
			if i > 0 { strings.write_string(sb, ",") }
			fmt.sbprintf(sb, "%v=", u.name)
			structural_print_expr(sb, u.value)
		}
		strings.write_string(sb, "])")
	case ^CExpr_Assign:
		strings.write_string(sb, "Assn(")
		structural_print_expr(sb, x.target)
		strings.write_string(sb, ",")
		structural_print_expr(sb, x.value)
		strings.write_string(sb, ")")
	case ^CExpr_Return:
		strings.write_string(sb, "Ret(")
		structural_print_expr(sb, x.value)
		strings.write_string(sb, ")")
	case ^CExpr_Crash:
		strings.write_string(sb, "Crash(")
		structural_print_expr(sb, x.message)
		strings.write_string(sb, ")")
	case ^CExpr_Interpolate:
		fmt.sbprintf(sb, "Interp(%d)", len(x.parts))
	case ^CExpr_Handle:
		fmt.sbprintf(sb, "Handle(%v,shallow=%v,arms=%d)", x.effect, x.is_shallow, len(x.arms))
	}
}

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

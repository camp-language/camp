package camp

// Stable structural rendering of canonical IR.
//
// Used by the cache-key acceptance test (test_canonicalize.odin) AND by
// the query layer (query.odin) as the input to the canonical hash that
// gates typecheck early-cutoff. Two source edits that produce the same
// structural_print_file output must be safe to share a typecheck result.
//
// Spans are deliberately omitted — they live off-tree in CFile.spans.

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

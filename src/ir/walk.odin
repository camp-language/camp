package ir

import ba "camp:base"

// walk_expr_children calls visitor for each child expression of expr.
// It does not visit expr itself — only its direct children.
// visitor receives each child expression and the user-supplied context pointer.
// This centralizes the recursive child-walking logic so individual passes
// don't each need to replicate the same #partial switch over IR_Expr union variants.
walk_expr_children :: proc(expr: IR_Expr, visitor: proc(expr: IR_Expr, ctx: rawptr), ctx: rawptr) {
	if expr == nil {
		return
	}
	#partial switch e in expr {
	case ^IR_Let:
		visitor(e.value, ctx)
		visitor(e.body, ctx)
	case ^IR_Call:
		for arg in e.args {
			visitor(arg, ctx)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			visitor(arg, ctx)
		}
	case ^IR_If:
		visitor(e.condition, ctx)
		visitor(e.then_branch, ctx)
		visitor(e.else_branch, ctx)
	case ^IR_Match:
		visitor(e.scrutinee, ctx)
		for arm in e.arms {
			if arm.guard != nil { visitor(arm.guard, ctx) }
			visitor(arm.body, ctx)
		}
	case ^IR_Construct_Tag:
		for payload in e.payload {
			visitor(payload, ctx)
		}
	case ^IR_Expr_Nominal_Construct:
		for payload in e.payload {
			visitor(payload, ctx)
		}
	case ^IR_Construct_Record:
		for field in e.fields {
			visitor(field.value, ctx)
		}
		visitor(e.rest, ctx)
	case ^IR_Field_Access:
		visitor(e.record, ctx)
	case ^IR_Method_Call:
		visitor(e.receiver, ctx)
		for arg in e.args {
			visitor(arg, ctx)
		}
	case ^IR_Handle:
		visitor(e.body, ctx)
		for arm in e.arms {
			visitor(arm.body, ctx)
		}
	case ^IR_Perform:
		for arg in e.args {
			visitor(arg, ctx)
		}
	case ^IR_Resume:
		visitor(e.value, ctx)
		visitor(e.ev, ctx)
	case ^IR_Closure:
		visitor(e.env, ctx)
		visitor(e.body, ctx)
	case ^IR_Closure_Call:
		visitor(e.callee, ctx)
		for arg in e.args {
			visitor(arg, ctx)
		}
	case ^IR_Return:
		visitor(e.value, ctx)
	case ^IR_Block:
		for stmt in e.statements {
			visitor(stmt, ctx)
		}
	case ^IR_BinOp:
		visitor(e.left, ctx)
		visitor(e.right, ctx)
	case ^IR_Crash:
		visitor(e.message, ctx)
	case ^IR_I32_Load:
		visitor(e.base, ctx)
	case ^IR_I32_Store:
		visitor(e.base, ctx)
		visitor(e.value, ctx)
	case ^IR_Atomic_Load:
		visitor(e.base, ctx)
	case ^IR_Atomic_Store:
		visitor(e.base, ctx)
		visitor(e.value, ctx)
	case ^IR_Atomic_RMW:
		visitor(e.base, ctx)
		visitor(e.value, ctx)
	case ^IR_Wait:
		visitor(e.base, ctx)
		visitor(e.expected, ctx)
		visitor(e.timeout, ctx)
	case ^IR_Notify:
		visitor(e.base, ctx)
		visitor(e.count, ctx)
	case ^IR_Assign:
		visitor(e.value, ctx)
	case ^IR_Loop:
		visitor(e.iterable, ctx)
		visitor(e.body, ctx)
	// Leaves — no child expressions
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Var,
	     ^IR_Dup,
	     ^IR_Drop,
	     ^IR_Atomic_Fence:
	// no children
	}
}

// walk_decl_children calls visitor for each top-level expression within a declaration.
walk_decl_children :: proc(decl: IR_Decl, visitor: proc(expr: IR_Expr, ctx: rawptr), ctx: rawptr) {
	if decl == nil {
		return
	}
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		visitor(d.body, ctx)
	case ^IR_Decl_Const:
		visitor(d.value, ctx)
	// IR_Decl_Effect has no expression children
	case ^IR_Decl_Effect:
	// no children
	}
}


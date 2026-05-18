package camp

import "core:fmt"

RC_Var_Info :: struct {
	uses: [dynamic]Source_Span,
}

rc_insert :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) {
	for &decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			d.body = rc_insert_expr(d.body, &ctx.interner)
		case ^IR_Decl_Const:
			d.value = rc_insert_expr(d.value, &ctx.interner)
		case:
		}
	}
}

rc_collect_uses :: proc(expr: IR_Expr, uses: ^map[Intern_ID]int) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Var:
		count, ok := (uses^)[e.name]
		if ok {
			(uses^)[e.name] = count + 1
		} else {
			(uses^)[e.name] = 1
		}
	case ^IR_Let:
		rc_collect_uses(e.value, uses)
		rc_collect_uses(e.body, uses)
	case ^IR_Call:
		for arg in e.args {
			rc_collect_uses(arg, uses)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			rc_collect_uses(arg, uses)
		}
	case ^IR_If:
		rc_collect_uses(e.condition, uses)
		rc_collect_uses(e.then_branch, uses)
		rc_collect_uses(e.else_branch, uses)
	case ^IR_Match:
		rc_collect_uses(e.scrutinee, uses)
		for arm in e.arms {
			rc_collect_uses(arm.body, uses)
		}
	case ^IR_Construct_Tag:
		for p in e.payload {
			rc_collect_uses(p, uses)
		}
	case ^IR_Construct_Record:
		for f in e.fields {
			rc_collect_uses(f.value, uses)
		}
		rc_collect_uses(e.rest, uses)
	case ^IR_Field_Access:
		rc_collect_uses(e.record, uses)
	case ^IR_Method_Call:
		rc_collect_uses(e.receiver, uses)
		for arg in e.args {
			rc_collect_uses(arg, uses)
		}
	case ^IR_Handle:
		rc_collect_uses(e.body, uses)
		for arm in e.arms {
			rc_collect_uses(arm.body, uses)
		}
	case ^IR_Perform:
		for arg in e.args {
			rc_collect_uses(arg, uses)
		}
	case ^IR_Return:
		rc_collect_uses(e.value, uses)
	case ^IR_Block:
		for stmt in e.statements {
			rc_collect_uses(stmt, uses)
		}
	case ^IR_BinOp:
		rc_collect_uses(e.left, uses)
		rc_collect_uses(e.right, uses)
	case ^IR_Dup:
		count, ok := (uses^)[e.value]
		if ok {
			(uses^)[e.value] = count + 1
		} else {
			(uses^)[e.value] = 1
		}
	case ^IR_Drop:
		count, ok := (uses^)[e.value]
		if ok {
			(uses^)[e.value] = count + 1
		} else {
			(uses^)[e.value] = 1
		}
	case:
	}
}

rc_insert_expr :: proc(expr: IR_Expr, interner: ^Intern_Table) -> IR_Expr {
	uses: map[Intern_ID]int
	uses = make(map[Intern_ID]int, 16)
	rc_collect_uses(expr, &uses)

	remaining: map[Intern_ID]int
	remaining = make(map[Intern_ID]int, len(uses))
	for k, v in uses {
		remaining[k] = v
	}

	result := rc_insert_expr_inner(expr, &remaining, interner)

	delete(uses)
	delete(remaining)
	return result
}

rc_insert_expr_inner :: proc(expr: IR_Expr, remaining: ^map[Intern_ID]int, interner: ^Intern_Table) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Var:
		count, ok := (remaining^)[e.name]
		if !ok do return expr

		(remaining^)[e.name] = count - 1
		new_count := (remaining^)[e.name]

		if uses, has := (remaining^)[e.name]; has && uses > 0 {
			dup := new(IR_Dup)
			dup^ = IR_Dup{value = e.name, span = e.span}
			return IR_Expr(dup)
		} else {
			drop := new(IR_Drop)
			drop^ = IR_Drop{value = e.name, span = e.span}
			return IR_Expr(drop)
		}

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = rc_insert_expr_inner(e.value, remaining, interner),
			body = rc_insert_expr_inner(e.body, remaining, interner),
			span = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, interner))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, interner))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call{callee = e.callee, args = new_args, span = e.span}
		return IR_Expr(new_tc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = rc_insert_expr_inner(e.condition, remaining, interner),
			then_branch = rc_insert_expr_inner(e.then_branch, remaining, interner),
			else_branch = rc_insert_expr_inner(e.else_branch, remaining, interner),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Match_Arm{pattern = arm.pattern, body = rc_insert_expr_inner(arm.body, remaining, interner)})
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match{
			scrutinee = rc_insert_expr_inner(e.scrutinee, remaining, interner),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, rc_insert_expr_inner(p, remaining, interner))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag{tag_name = e.tag_name, payload = new_payload, type = e.type, span = e.span}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(&new_fields, IR_Record_Field{name = f.name, value = rc_insert_expr_inner(f.value, remaining, interner)})
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record{
			fields = new_fields,
			rest = rc_insert_expr_inner(e.rest, remaining, interner),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access{
			record = rc_insert_expr_inner(e.record, remaining, interner),
			field = e.field,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, interner))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call{
			receiver = rc_insert_expr_inner(e.receiver, remaining, interner),
			method = e.method,
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Handle:
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(&new_arms, IR_Handler_Arm{
				op = arm.op,
				resume_id = arm.resume_id,
				body = rc_insert_expr_inner(arm.body, remaining, interner),
			})
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = rc_insert_expr_inner(e.body, remaining, interner),
			arms = new_arms,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, interner))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform{effect = e.effect, op = e.op, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_perf)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = rc_insert_expr_inner(e.value, remaining, interner), span = e.span}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, rc_insert_expr_inner(stmt, remaining, interner))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = rc_insert_expr_inner(e.left, remaining, interner),
			right = rc_insert_expr_inner(e.right, remaining, interner),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)
	}

	return expr
}

package ir

import "camp:base"

// reuse_analyze performs Perceus in-place reuse optimization.
// It runs after rc_insert (which emits IR_Drop nodes) and looks for
// patterns where a drop of a heap variable immediately precedes a
// construct (tag or record). When found, it sets reuse_addr on the
// construct and removes the drop — the codegen will emit inline
// reuse-or-alloc logic instead.
//
// Pattern matched:
//   IR_Let { binding=x, value=IR_Construct_Tag/Record{...}, body=IR_Block{IR_Drop{y}, ...rest} }
// Becomes:
//   IR_Let { binding=x, value=IR_Construct_Tag/Record{reuse_addr=y, ...}, body=...rest }
//
// The drop of y is removed because the construct's codegen handles
// the refcount decrement inline (decrement, check zero, reuse-or-alloc).
reuse_analyze :: proc(mod: ^IR_Module) {
	for &decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			d.body = reuse_analyze_expr(d.body)
		case ^IR_Decl_Const:
			d.value = reuse_analyze_expr(d.value)
		case ^IR_Decl_Effect:
		}
	}
}

reuse_analyze_expr :: proc(expr: IR_Expr) -> IR_Expr {
	if expr == nil do return nil

	#partial switch e in expr {
	case ^IR_Let:
		new_value := reuse_analyze_expr(e.value)
		analyzed_body := reuse_analyze_expr(e.body)

		// Try to find a drop in the body that we can reuse
		new_body, reuse_addr := extract_reuse_from_body(analyzed_body)

		if reuse_addr != NO_REUSE_ADDR {
			// Set reuse_addr on the construct node — returns the value
			// unchanged if it's not a construct (in which case, keep the drop)
			value_with_reuse := set_reuse_addr(new_value, reuse_addr)
			if value_with_reuse != new_value {
				// Successfully set reuse_addr — use the modified value and body (drop removed)
				new_value = value_with_reuse
			} else {
				// Not a construct — can't reuse, keep the original body with the drop
				new_body = analyzed_body
			}
		}

		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = new_value,
			body    = new_body,
			span    = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, reuse_analyze_expr(stmt))
		}

		// Try to match drop-then-construct within the block
		new_stmts = optimize_block_drops(new_stmts)

		new_block := new(IR_Block)
		new_block^ = IR_Block {
			statements = new_stmts,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_block)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If {
			condition   = reuse_analyze_expr(e.condition),
			then_branch = reuse_analyze_expr(e.then_branch),
			else_branch = reuse_analyze_expr(e.else_branch),
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(
				&new_arms,
				IR_Match_Arm {
					pattern = arm.pattern,
					guard = reuse_analyze_expr(arm.guard) if arm.guard != nil else nil,
					body = reuse_analyze_expr(arm.body),
				},
			)
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = reuse_analyze_expr(e.scrutinee),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, reuse_analyze_expr(arg))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call {
			callee           = e.callee,
			args             = new_args,
			type             = e.type,
			span             = e.span,
			ord_compare_func = e.ord_compare_func,
		}
		return IR_Expr(new_call)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, reuse_analyze_expr(arg))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = reuse_analyze_expr(e.callee),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, reuse_analyze_expr(arg))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call {
			callee = e.callee,
			args   = new_args,
			span   = e.span,
		}
		return IR_Expr(new_tc)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, reuse_analyze_expr(p))
		}
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag {
			tag_name   = e.tag_name,
			tag_index  = e.tag_index,
			payload    = new_payload,
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_tag)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(
				&new_fields,
				IR_Record_Field{name = f.name, value = reuse_analyze_expr(f.value)},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = reuse_analyze_expr(e.rest),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = reuse_analyze_expr(e.record),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, reuse_analyze_expr(arg))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call {
			receiver = reuse_analyze_expr(e.receiver),
			method   = e.method,
			args     = new_args,
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Handle:
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(
				&new_arms,
				IR_Handler_Arm {
					op = arm.op,
					params = arm.params,
					body = reuse_analyze_expr(arm.body),
				},
			)
		}
		effects := make([dynamic]base.Canonical_Name, 0, len(e.effects))
		for eff in e.effects {
			append(&effects, eff)
		}
		new_handle := new(IR_Handle)
		new_handle^ = IR_Handle {
			effects = effects,
			body    = reuse_analyze_expr(e.body),
			arms    = new_arms,
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, reuse_analyze_expr(arg))
		}
		new_perf := new(IR_Perform)
		new_perf^ = IR_Perform {
			effect = e.effect,
			op     = e.op,
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_perf)

	case ^IR_Resume:
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = reuse_analyze_expr(e.ev)
		}
		new_resume := new(IR_Resume)
		new_resume^ = IR_Resume {
			resume_id = e.resume_id,
			value     = reuse_analyze_expr(e.value),
			ev        = ev_val,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = reuse_analyze_expr(e.value),
			span  = e.span,
		}
		return IR_Expr(new_ret)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp {
			op    = e.op,
			left  = reuse_analyze_expr(e.left),
			right = reuse_analyze_expr(e.right),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash {
			message = reuse_analyze_expr(e.message),
			span    = e.span,
		}
		return IR_Expr(new_crash)

	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign {
			binding = e.binding,
			value   = reuse_analyze_expr(e.value),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)

	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = reuse_analyze_expr(e.iterable),
			body     = reuse_analyze_expr(e.body),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)

	case ^IR_Dup:
		// Dup and Drop are leaf nodes — no children to recurse
		return expr

	case ^IR_Drop:
		return expr
	}

	return expr
}

// extract_reuse_from_body looks for a leading IR_Drop in the body expression
// and returns the modified body (with the drop removed) and the dropped
// variable name for reuse. If no suitable drop is found, returns the
// body unchanged and NO_REUSE_ADDR.
extract_reuse_from_body :: proc(body: IR_Expr) -> (IR_Expr, base.Intern_ID) {
	if body == nil do return body, NO_REUSE_ADDR

	// Pattern: body is IR_Block{IR_Drop{y}, ...rest}
	#partial switch b in body {
	case ^IR_Block:
		if len(b.statements) >= 2 {
			// Check if first statement is a drop
			#partial switch first in b.statements[0] {
			case ^IR_Drop:
				// Found a drop — extract it and return the rest
				reuse_addr := first.value
				rest := make([dynamic]IR_Expr, 0, len(b.statements) - 1)
				for i in 1 ..< len(b.statements) {
					append(&rest, b.statements[i])
				}

				if len(rest) == 1 {
					// Single remaining statement — unwrap the block
					result := rest[0]
					delete(rest)
					return result, reuse_addr
				}

				new_block := new(IR_Block)
				new_block^ = IR_Block {
					statements = rest,
					type       = b.type,
					span       = b.span,
				}
				return IR_Expr(new_block), reuse_addr
			}
		}
	case ^IR_Drop:
		// Body is just a single drop — the construct result is unused.
		// We can still reuse the dropped variable's memory.
		return nil, b.value
	}

	return body, NO_REUSE_ADDR
}

// set_reuse_addr sets the reuse_addr field on a construct expression.
// Returns the expression unchanged if it's not a construct node.
set_reuse_addr :: proc(expr: IR_Expr, reuse_addr: base.Intern_ID) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Construct_Tag:
		new_tag := new(IR_Construct_Tag)
		new_tag^ = IR_Construct_Tag {
			tag_name   = e.tag_name,
			tag_index  = e.tag_index,
			payload    = e.payload,
			reuse_addr = reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_tag)
	case ^IR_Construct_Record:
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = e.fields,
			rest       = e.rest,
			reuse_addr = reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)
	}

	// Not a construct — can't set reuse_addr
	return expr
}

// optimize_block_drops looks for drop-then-construct patterns within
// a block's statements and optimizes them. This handles the case where
// the drop and construct are sibling statements in a block rather than
// the construct being in a let's value.
optimize_block_drops :: proc(stmts: [dynamic]IR_Expr) -> [dynamic]IR_Expr {
	if len(stmts) < 2 do return stmts

	result := make([dynamic]IR_Expr, 0, len(stmts))
	i := 0
	for i < len(stmts) {
		// Check for drop-then-let-with-construct pattern
		if i < len(stmts) - 1 {
			drop_match := false

			#partial switch drop_stmt in stmts[i] {
			case ^IR_Drop:
				#partial switch next in stmts[i + 1] {
				case ^IR_Let:
					#partial switch val in next.value {
					case ^IR_Construct_Tag:
						if val.reuse_addr == NO_REUSE_ADDR {
							new_construct := new(IR_Construct_Tag)
							new_construct^ = IR_Construct_Tag {
								tag_name   = val.tag_name,
								tag_index  = val.tag_index,
								payload    = val.payload,
								reuse_addr = drop_stmt.value,
								type       = val.type,
								span       = val.span,
							}
							next.value = IR_Expr(new_construct)
							append(&result, stmts[i + 1])
							i += 2
							drop_match = true
						}
					case ^IR_Construct_Record:
						if val.reuse_addr == NO_REUSE_ADDR {
							new_construct := new(IR_Construct_Record)
							new_construct^ = IR_Construct_Record {
								fields     = val.fields,
								rest       = val.rest,
								reuse_addr = drop_stmt.value,
								type       = val.type,
								span       = val.span,
							}
							next.value = IR_Expr(new_construct)
							append(&result, stmts[i + 1])
							i += 2
							drop_match = true
						}
					}
				}
			}

			if drop_match do continue
		}

		append(&result, stmts[i])
		i += 1
	}

	delete(stmts)
	return result
}


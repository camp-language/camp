package ir

import "camp:base"

rc_insert :: proc(mod: ^IR_Module, interner: ^base.Intern_Table) {
	for &decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			d.body = rc_insert_fn(d, interner)
		case ^IR_Decl_Const:
			d.value = rc_insert_expr(d.value, interner)
		case ^IR_Decl_Effect:
		}
	}
}

// rc_insert_fn processes a function declaration, inserting dups/drops
// and emitting drops for unused heap-typed parameters at the end.
rc_insert_fn :: proc(d: ^IR_Decl_Fn, interner: ^base.Intern_Table) -> IR_Expr {
	uses: map[base.Intern_ID]int
	uses = make(map[base.Intern_ID]int, 16)
	rc_collect_uses(d.body, &uses)

	remaining: map[base.Intern_ID]int
	remaining = make(map[base.Intern_ID]int, len(uses))
	for k, v in uses {
		remaining[k] = v
	}

	// Build heap_types map from the entire function body + params
	heap_types: map[base.Intern_ID]base.IR_Type
	heap_types = make(map[base.Intern_ID]base.IR_Type, len(uses) + len(d.params))
	collect_heap_types(d.body, &heap_types)
	for &param in d.params {
		heap_types[param.name] = param.type
	}

	result := rc_insert_expr_inner(d.body, &remaining, &heap_types, interner)

	// Emit drops for unused heap-typed parameters at end of function body
	drops := emit_param_drops(d.params[:], &remaining, &heap_types)
	result = wrap_with_drops(result, drops)

	delete(uses)
	delete(remaining)
	delete(heap_types)
	return result
}

rc_insert_expr :: proc(expr: IR_Expr, interner: ^base.Intern_Table) -> IR_Expr {
	uses: map[base.Intern_ID]int
	uses = make(map[base.Intern_ID]int, 16)
	rc_collect_uses(expr, &uses)

	remaining: map[base.Intern_ID]int
	remaining = make(map[base.Intern_ID]int, len(uses))
	for k, v in uses {
		remaining[k] = v
	}

	heap_types: map[base.Intern_ID]base.IR_Type
	heap_types = make(map[base.Intern_ID]base.IR_Type, len(uses))
	collect_heap_types(expr, &heap_types)

	result := rc_insert_expr_inner(expr, &remaining, &heap_types, interner)

	delete(uses)
	delete(remaining)
	delete(heap_types)
	return result
}

rc_collect_uses :: proc(expr: IR_Expr, uses: ^map[base.Intern_ID]int) {
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
	case ^IR_Closure_Call:
		rc_collect_uses(e.callee, uses)
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
	case ^IR_Resume:
		count, ok := (uses^)[e.resume_id]
		if ok {
			(uses^)[e.resume_id] = count + 1
		} else {
			(uses^)[e.resume_id] = 1
		}
		rc_collect_uses(e.value, uses)
		if e.ev != nil {
			rc_collect_uses(e.ev, uses)
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
	case ^IR_Crash:
		rc_collect_uses(e.message, uses)
	case ^IR_Atomic_Load:
		rc_collect_uses(e.base, uses)
	case ^IR_Atomic_Store:
		rc_collect_uses(e.base, uses)
		rc_collect_uses(e.value, uses)
	case ^IR_Atomic_RMW:
		rc_collect_uses(e.base, uses)
		rc_collect_uses(e.value, uses)
	case ^IR_Atomic_Fence:
	case ^IR_Wait:
		rc_collect_uses(e.base, uses)
		rc_collect_uses(e.expected, uses)
	case ^IR_Notify:
		rc_collect_uses(e.base, uses)
		rc_collect_uses(e.count, uses)
	case ^IR_Assign:
		rc_collect_uses(e.value, uses)
	case ^IR_Loop:
		rc_collect_uses(e.iterable, uses)
		rc_collect_uses(e.body, uses)
	case ^IR_I32_Load:
		rc_collect_uses(e.base, uses)
	case ^IR_I32_Store:
		rc_collect_uses(e.base, uses)
		rc_collect_uses(e.value, uses)
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Expr_Nominal_Construct,
	     ^IR_Closure:
	}
}

copy_remaining :: proc(src: ^map[base.Intern_ID]int) -> map[base.Intern_ID]int {
	dst := make(map[base.Intern_ID]int, len(src^))
	for k, v in src^ {
		dst[k] = v
	}
	return dst
}

make_ir_duo :: proc(a: IR_Expr, b: IR_Expr) -> [dynamic]IR_Expr {
	list := make([dynamic]IR_Expr, 0, 2)
	append(&list, a)
	append(&list, b)
	return list
}

// was_dropped_in_branch returns true if a heap binding was not used in a branch
// (and thus a drop was emitted for it). A binding is considered "dropped in branch"
// if it was not used in the branch (initial and final remaining counts are the same,
// or the binding is not in the remaining map at all).
was_dropped_in_branch :: proc(
	name: base.Intern_ID,
	initial_remaining: ^map[base.Intern_ID]int,
	final_remaining: ^map[base.Intern_ID]int,
) -> bool {
	initial_count, was_in_initial := (initial_remaining^)[name]
	final_count, was_in_final := (final_remaining^)[name]

	if !was_in_initial && !was_in_final {
		// Binding was never in remaining — it was never used, so it's dropped
		return true
	}
	if was_in_initial && was_in_final && final_count >= initial_count {
		// Count didn't decrease — binding wasn't used in this branch
		return true
	}
	return false
}

// emit_drops_for_branch emits IR_Drop nodes for heap bindings whose ownership
// is not consumed within a branch. A binding's ownership is consumed if it's
// used at least once in the branch (the last use consumes the original).
// Bindings that are never used in the branch need a drop.
// `initial_remaining` is the remaining map at the START of the branch (before processing).
// `final_remaining` is the remaining map AFTER processing the branch.
// `heap_types` maps binding names to their IR_Types.
emit_drops_for_branch :: proc(
	initial_remaining: ^map[base.Intern_ID]int,
	final_remaining: ^map[base.Intern_ID]int,
	heap_types: ^map[base.Intern_ID]base.IR_Type,
) -> [dynamic]IR_Expr {
	drops: [dynamic]IR_Expr
	drops = make([dynamic]IR_Expr, 0, 4)

	for name, type_info in heap_types^ {
		if !type_info.is_heap do continue

		initial_count, was_in_initial := (initial_remaining^)[name]
		final_count, was_in_final := (final_remaining^)[name]

		used_in_branch := false
		if was_in_initial && was_in_final {
			if final_count < initial_count {
				used_in_branch = true
			}
		} else if was_in_final && !was_in_initial {
			used_in_branch = true
		}

		if !used_in_branch {
			drop := new(IR_Drop)
			drop^ = IR_Drop {
				value = name,
				span  = base.Source_Span{},
			}
			append(&drops, IR_Expr(drop))
		} else if was_in_final && final_count > 0 {
			for i in 0 ..< final_count {
				drop := new(IR_Drop)
				drop^ = IR_Drop {
					value = name,
					span  = base.Source_Span{},
				}
				append(&drops, IR_Expr(drop))
			}
			(final_remaining^)[name] = 0
		}
	}

	return drops
}

// emit_param_drops emits IR_Drop nodes for heap-typed function parameters
// that were not consumed in the function body.
emit_param_drops :: proc(
	params: []IR_Param,
	remaining: ^map[base.Intern_ID]int,
	heap_types: ^map[base.Intern_ID]base.IR_Type,
) -> [dynamic]IR_Expr {
	drops: [dynamic]IR_Expr
	drops = make([dynamic]IR_Expr, 0, 4)

	for &param in params {
		if !param.type.is_heap do continue
		count, ok := (remaining^)[param.name]
		if !ok {
			// Parameter never used — emit drop
			drop := new(IR_Drop)
			drop^ = IR_Drop {
				value = param.name,
				span  = base.Source_Span{},
			}
			append(&drops, IR_Expr(drop))
		} else if count > 0 {
			// Parameter has unconsumed remaining uses — emit that many drops
			for i in 0 ..< count {
				drop := new(IR_Drop)
				drop^ = IR_Drop {
					value = param.name,
					span  = base.Source_Span{},
				}
				append(&drops, IR_Expr(drop))
			}
			(remaining^)[param.name] = 0
		}
	}

	return drops
}

// wrap_with_drops wraps an expression with leading drop statements.
// If no drops, returns the expression unchanged.
// If drops exist, wraps in IR_Block{drop1, drop2, ..., expr}.
// The block's type is the same as the expression's type (drops don't produce values).
wrap_with_drops :: proc(expr: IR_Expr, drops: [dynamic]IR_Expr) -> IR_Expr {
	if len(drops) == 0 {
		delete(drops)
		return expr
	}

	stmts := make([dynamic]IR_Expr, 0, 1 + len(drops))
	for drop in drops {
		append(&stmts, drop)
	}
	append(&stmts, expr)
	delete(drops)

	// Determine the type from the expression
	block_type := base.IR_Type {
		wasm_type = .Void,
	}
	#partial switch e in expr {
	case ^IR_Literal_Int:
		block_type = e.type
	case ^IR_Literal_Bool:
		block_type = e.type
	case ^IR_Literal_Float:
		block_type = e.type
	case ^IR_Var:
		block_type = e.type
	case ^IR_BinOp:
		block_type = e.type
	case ^IR_Call:
		block_type = e.type
	case ^IR_Closure_Call:
		block_type = e.type
	case ^IR_Field_Access:
		block_type = e.type
	case ^IR_Construct_Tag:
		block_type = e.type
	case ^IR_Construct_Record:
		block_type = e.type
	case ^IR_If:
		block_type = e.type
	case ^IR_Match:
		block_type = e.type
	case ^IR_Block:
		block_type = e.type
	case:
	}

	block := new(IR_Block)
	block^ = IR_Block {
		statements = stmts,
		type       = block_type,
		span       = base.Source_Span{},
	}
	return IR_Expr(block)
}

// collect_heap_types walks an expression to build a map of binding names
// to their IR_Types, used to determine is_heap for drop emission.
collect_heap_types :: proc(expr: IR_Expr, types: ^map[base.Intern_ID]base.IR_Type) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Let:
		(types^)[e.binding] = e.type
		collect_heap_types(e.value, types)
		collect_heap_types(e.body, types)
	case ^IR_Block:
		for stmt in e.statements {
			collect_heap_types(stmt, types)
		}
	case ^IR_If:
		collect_heap_types(e.condition, types)
		collect_heap_types(e.then_branch, types)
		collect_heap_types(e.else_branch, types)
	case ^IR_Match:
		collect_heap_types(e.scrutinee, types)
		for arm in e.arms {
			collect_heap_types(arm.body, types)
		}
	case ^IR_Call:
		for arg in e.args {
			collect_heap_types(arg, types)
		}
	case ^IR_Closure_Call:
		collect_heap_types(e.callee, types)
		for arg in e.args {
			collect_heap_types(arg, types)
		}
	case ^IR_Construct_Tag:
		for p in e.payload {
			collect_heap_types(p, types)
		}
	case ^IR_Construct_Record:
		for f in e.fields {
			collect_heap_types(f.value, types)
		}
		collect_heap_types(e.rest, types)
	case ^IR_Field_Access:
		collect_heap_types(e.record, types)
	case ^IR_Method_Call:
		collect_heap_types(e.receiver, types)
		for arg in e.args {
			collect_heap_types(arg, types)
		}
	case ^IR_Handle:
		collect_heap_types(e.body, types)
		for arm in e.arms {
			collect_heap_types(arm.body, types)
		}
	case ^IR_BinOp:
		collect_heap_types(e.left, types)
		collect_heap_types(e.right, types)
	case ^IR_Return:
		collect_heap_types(e.value, types)
	case ^IR_Crash:
		collect_heap_types(e.message, types)
	case ^IR_Assign:
		collect_heap_types(e.value, types)
	case ^IR_Loop:
		collect_heap_types(e.iterable, types)
		collect_heap_types(e.body, types)
	case:
	}
}

rc_insert_expr_inner :: proc(
	expr: IR_Expr,
	remaining: ^map[base.Intern_ID]int,
	heap_types: ^map[base.Intern_ID]base.IR_Type,
	interner: ^base.Intern_Table,
) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Var:
		count, ok := (remaining^)[e.name]
		if !ok do return expr
		(remaining^)[e.name] = count - 1
		if (remaining^)[e.name] > 0 {
			dup := new(IR_Dup)
			dup^ = IR_Dup {
				value = e.name,
				span  = e.span,
			}
			block := new(IR_Block)
			block^ = IR_Block {
				statements = make_ir_duo(IR_Expr(dup), expr),
				type       = e.type,
				span       = e.span,
			}
			return IR_Expr(block)
		}
		return expr

	case ^IR_Let:
		new_value := rc_insert_expr_inner(e.value, remaining, heap_types, interner)
		new_body := rc_insert_expr_inner(e.body, remaining, heap_types, interner)

		// Emit drop for unused heap-typed bindings
		binding_count, binding_used := (remaining^)[e.binding]
		drops: [dynamic]IR_Expr
		drops = make([dynamic]IR_Expr, 0, 1)

		if binding_used && binding_count == -1 {
			// Binding was already dropped by branches (e.g., in IR_If/IR_Match)
			// Don't emit another drop
		} else if !binding_used || binding_count <= 0 {
			// Binding was never used or all uses were consumed —
			// if is_heap, we need to drop the original ownership
			if e.type.is_heap {
				drop := new(IR_Drop)
				drop^ = IR_Drop {
					value = e.binding,
					span  = e.span,
				}
				append(&drops, IR_Expr(drop))
			}
		} else {
			// Binding has unconsumed remaining uses — emit that many drops
			if e.type.is_heap {
				for i in 0 ..< binding_count {
					drop := new(IR_Drop)
					drop^ = IR_Drop {
						value = e.binding,
						span  = e.span,
					}
					append(&drops, IR_Expr(drop))
				}
			}
			(remaining^)[e.binding] = 0
		}

		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = new_value,
			body    = wrap_with_drops(new_body, drops),
			span    = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, heap_types, interner))
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
			append(&new_args, rc_insert_expr_inner(arg, remaining, heap_types, interner))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = rc_insert_expr_inner(e.callee, remaining, heap_types, interner),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, heap_types, interner))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call {
			callee = e.callee,
			args   = new_args,
			span   = e.span,
		}
		return IR_Expr(new_tc)

	case ^IR_If:
		then_rem := copy_remaining(remaining)
		else_rem := copy_remaining(remaining)

		then_branch := rc_insert_expr_inner(e.then_branch, &then_rem, heap_types, interner)
		else_branch := rc_insert_expr_inner(e.else_branch, &else_rem, heap_types, interner)

		// Emit drops for unconsumed heap bindings in each branch
		then_drops := emit_drops_for_branch(remaining, &then_rem, heap_types)
		else_drops := emit_drops_for_branch(remaining, &else_rem, heap_types)

		then_branch = wrap_with_drops(then_branch, then_drops)
		else_branch = wrap_with_drops(else_branch, else_drops)

		// Mark heap bindings that were dropped in BOTH branches as consumed
		// in the parent remaining, so the IR_Let handler doesn't double-drop.
		// Use -1 as sentinel for "handled by branches".
		for name, type_info in heap_types^ {
			if !type_info.is_heap do continue
			then_dropped := was_dropped_in_branch(name, remaining, &then_rem)
			else_dropped := was_dropped_in_branch(name, remaining, &else_rem)
			if then_dropped && else_dropped {
				(remaining^)[name] = -1
			}
		}

		// Merge branch remainings: take minimum (conservative — assume
		// the branch that consumed the most ran)
		for name, count in then_rem {
			else_count, ok := else_rem[name]
			if ok {
				min_count := count
				if else_count < min_count {
					min_count = else_count
				}
				(remaining^)[name] = min_count
			}
		}

		delete(then_rem)
		delete(else_rem)

		new_if := new(IR_If)
		new_if^ = IR_If {
			condition   = rc_insert_expr_inner(e.condition, remaining, heap_types, interner),
			then_branch = then_branch,
			else_branch = else_branch,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_if)

	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		first := true
		for arm in e.arms {
			arm_rem := copy_remaining(remaining)
			new_body := rc_insert_expr_inner(arm.body, &arm_rem, heap_types, interner)

			// Emit drops for unconsumed heap bindings in this arm
			arm_drops := emit_drops_for_branch(remaining, &arm_rem, heap_types)
			new_body = wrap_with_drops(new_body, arm_drops)

			guard_new: IR_Expr = nil
			if arm.guard != nil {
				guard_rem := copy_remaining(remaining)
				guard_new = rc_insert_expr_inner(arm.guard, &guard_rem, heap_types, interner)
			}
			append(
				&new_arms,
				IR_Match_Arm{pattern = arm.pattern, guard = guard_new, body = new_body},
			)

			// Merge: take minimum across arms (conservative)
			if first {
				for name, count in arm_rem {
					(remaining^)[name] = count
				}
				first = false
			} else {
				for name, count in arm_rem {
					existing, ok := (remaining^)[name]
					if ok {
						if count < existing {
							(remaining^)[name] = count
						}
					}
				}
			}

			delete(arm_rem)
		}

		// Mark heap bindings dropped in ALL arms as consumed (sentinel -1)
		for name, type_info in heap_types^ {
			if !type_info.is_heap do continue
			all_dropped := true
			// Check if the binding was dropped in every arm
			// (if it wasn't used in any arm, it was dropped in all arms)
			_, in_initial := (remaining^)[name]
			if !in_initial {
				// Binding not in remaining — check if it's in heap_types
				// and was never used in any arm
				// For now, just check if it's a heap binding that wasn't consumed
				all_dropped = true
			} else {
				all_dropped = false
			}
			if all_dropped {
				(remaining^)[name] = -1
			}
		}

		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = rc_insert_expr_inner(e.scrutinee, remaining, heap_types, interner),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, rc_insert_expr_inner(p, remaining, heap_types, interner))
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
				IR_Record_Field {
					name = f.name,
					value = rc_insert_expr_inner(f.value, remaining, heap_types, interner),
				},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = rc_insert_expr_inner(e.rest, remaining, heap_types, interner),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = rc_insert_expr_inner(e.record, remaining, heap_types, interner),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, heap_types, interner))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call {
			receiver = rc_insert_expr_inner(e.receiver, remaining, heap_types, interner),
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
					body = rc_insert_expr_inner(arm.body, remaining, heap_types, interner),
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
			body    = rc_insert_expr_inner(e.body, remaining, heap_types, interner),
			arms    = new_arms,
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, heap_types, interner))
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
		count, ok := (remaining^)[e.resume_id]
		if ok && count > 0 {
			(remaining^)[e.resume_id] = count - 1
		}
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = rc_insert_expr_inner(e.ev, remaining, heap_types, interner)
		}
		new_resume := new(IR_Resume)
		new_resume^ = IR_Resume {
			resume_id = e.resume_id,
			value     = rc_insert_expr_inner(e.value, remaining, heap_types, interner),
			ev        = ev_val,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = rc_insert_expr_inner(e.value, remaining, heap_types, interner),
			span  = e.span,
		}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, rc_insert_expr_inner(stmt, remaining, heap_types, interner))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block {
			statements = new_stmts,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_block)

	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp {
			op    = e.op,
			left  = rc_insert_expr_inner(e.left, remaining, heap_types, interner),
			right = rc_insert_expr_inner(e.right, remaining, heap_types, interner),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Crash:
		new_msg := rc_insert_expr_inner(e.message, remaining, heap_types, interner)
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash {
			message = new_msg,
			span    = e.span,
		}
		return IR_Expr(new_crash)
	case ^IR_I32_Load:
		new_load := new(IR_I32_Load)
		new_load^ = IR_I32_Load {
			base   = rc_insert_expr_inner(e.base, remaining, heap_types, interner),
			offset = e.offset,
			span   = e.span,
		}
		return IR_Expr(new_load)
	case ^IR_I32_Store:
		new_store := new(IR_I32_Store)
		new_store^ = IR_I32_Store {
			base   = rc_insert_expr_inner(e.base, remaining, heap_types, interner),
			offset = e.offset,
			value  = rc_insert_expr_inner(e.value, remaining, heap_types, interner),
			span   = e.span,
		}
		return IR_Expr(new_store)
	case ^IR_Atomic_Load:
		return IR_Expr(e)
	case ^IR_Atomic_Store:
		return IR_Expr(e)
	case ^IR_Atomic_RMW:
		return IR_Expr(e)
	case ^IR_Atomic_Fence:
		return IR_Expr(e)
	case ^IR_Wait:
		return IR_Expr(e)
	case ^IR_Notify:
		return IR_Expr(e)
	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign {
			binding = e.binding,
			value   = rc_insert_expr_inner(e.value, remaining, heap_types, interner),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = rc_insert_expr_inner(e.iterable, remaining, heap_types, interner),
			body     = rc_insert_expr_inner(e.body, remaining, heap_types, interner),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	}

	return expr
}


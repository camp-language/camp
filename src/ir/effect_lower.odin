package ir

import "camp:base"
import "camp:diagnostics"
import "camp:semantics"

Effect_Evidence :: struct {
	effect:      base.Canonical_Name,
	ev_var:      base.Intern_ID,
	arm_indices: map[base.Intern_ID]int,
	inactive:    bool,
	handle_type: base.IR_Type,
}

Effect_Lower_Env :: struct {
	module:          ^IR_Module,
	interner:        ^base.Intern_Table,
	collector:       ^diagnostics.Diagnostic_Collector,
	fresh_state:     base.Fresh_State,
	evidence_stack:  [dynamic]Effect_Evidence,
	async_id:        base.Intern_ID,
	spawn_id:        base.Intern_ID,
	parallel_id:     base.Intern_ID,
	file_id:         base.Intern_ID,
	console_id:      base.Intern_ID,
	time_id:         base.Intern_ID,
	fn_effects:      map[base.Canonical_Name][dynamic]base.Canonical_Name,
	camp_alloc_id:   base.Intern_ID,
	camp_dealloc_id: base.Intern_ID,
}

is_scheduler_effect_by_ids :: proc(
	effect_name: base.Intern_ID,
	async_id, spawn_id, parallel_id, file_id, console_id, time_id: base.Intern_ID,
	interner: ^base.Intern_Table,
) -> bool {
	ids := []base.Intern_ID{async_id, spawn_id, parallel_id, file_id, console_id, time_id}
	for id in ids {
		if effect_name == id {
			return true
		}
	}
	// Effect decls are stored without `!` suffix, but scheduler IDs include `!`.
	// Accept effect names missing the `!` by probing each scheduler ID stripped.
	name_str := base.intern_get(interner, effect_name)
	bare_name := name_str
	if len(name_str) > 0 && name_str[len(name_str) - 1] == '!' {
		bare_name = name_str[:len(name_str) - 1]
	}
	for id in ids {
		id_str := base.intern_get(interner, id)
		if len(id_str) > 0 && id_str[len(id_str) - 1] == '!' {
			bare_id_str := id_str[:len(id_str) - 1]
			if bare_name == bare_id_str {
				return true
			}
		}
	}
	return false
}

is_scheduler_effect :: proc(effect: base.Canonical_Name, env: ^Effect_Lower_Env) -> bool {
	return is_scheduler_effect_by_ids(
		effect.name,
		env.async_id,
		env.spawn_id,
		env.parallel_id,
		env.file_id,
		env.console_id,
		env.time_id,
		env.interner,
	)
}

effect_lower :: proc(
	mod: ^IR_Module,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
	type_store: ^semantics.Type_Store,
) -> IR_Module {
	result: IR_Module
	result.decls = make([dynamic]IR_Decl, 0, len(mod.decls) + 16)
	result.effect_defs = make([dynamic]IR_Effect_Def, 0, len(mod.effect_defs))
	for eff in mod.effect_defs {
		new_eff := eff
		new_eff.operations = make([dynamic]IR_Effect_Op, len(eff.operations))
		for op, i in eff.operations {
			new_eff.operations[i] = op
			new_eff.operations[i].params = make([dynamic]IR_Param, len(op.params))
			for p, j in op.params {
				new_eff.operations[i].params[j] = p
			}
		}
		new_eff.type_params = make([dynamic]base.Intern_ID, len(eff.type_params))
		for tp, i in eff.type_params {
			new_eff.type_params[i] = tp
		}
		append(&result.effect_defs, new_eff)
	}
	result.string_table = make([dynamic]String_Table_Entry, 0, len(mod.string_table))
	for entry in mod.string_table {
		append(&result.string_table, entry)
	}

	env: Effect_Lower_Env
	env.module = &result
	env.interner = interner
	env.fresh_state = base.Fresh_State {
		counter  = 0,
		interner = interner,
	}
	env.evidence_stack = make([dynamic]Effect_Evidence, 0, 8)
	env.collector = collector
	env.async_id = base.intern(interner, "Async!")
	env.spawn_id = base.intern(interner, "Spawn!")
	env.parallel_id = base.intern(interner, "Parallel!")
	env.file_id = base.intern(interner, "File!")
	env.console_id = base.intern(interner, "Console!")
	env.time_id = base.intern(interner, "Time!")
	env.fn_effects = make(map[base.Canonical_Name][dynamic]base.Canonical_Name, 16)
	env.camp_alloc_id = base.intern(interner, "camp_alloc")
	env.camp_dealloc_id = base.intern(interner, "camp_dealloc")

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			if len(d.effects) > 0 {
				env.fn_effects[d.name] = d.effects
			}
		case ^IR_Decl_Const, ^IR_Decl_Effect:
		}
	}

	throw_name := base.intern(interner, "Throw!")

	for decl in mod.decls {
		transformed := el_lower_decl(decl, &env, throw_name, type_store)
		append(&result.decls, transformed)
	}

	delete(env.evidence_stack)
	delete(env.fn_effects)
	return result
}

el_lower_decl :: proc(
	decl: IR_Decl,
	env: ^Effect_Lower_Env,
	throw_name: base.Intern_ID,
	type_store: ^semantics.Type_Store,
) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^
		new_fn.params = make([dynamic]IR_Param, len(d.params))
		for p, i in d.params {new_fn.params[i] = p}
		new_fn.effects = make([dynamic]base.Canonical_Name, len(d.effects))
		for e, i in d.effects {new_fn.effects[i] = e}
		new_fn.body = el_lower_expr(d.body, env)
		// Effects list is preserved for codegen's _start evidence allocation.
		// Effect_lower handles effects internally via evidence records,
		// but codegen needs the original effects to allocate evidence at the top level.
		return IR_Decl(new_fn)
	case ^IR_Decl_Const:
		new_const := new(IR_Decl_Const)
		new_const^ = d^
		new_const.value = el_lower_expr(d.value, env)
		return IR_Decl(new_const)
	case ^IR_Decl_Effect:
		return decl
	}
	return decl
}

el_effect_row_has_throw :: proc(
	effect_row: base.IR_Type,
	throw_name: base.Intern_ID,
	store: ^semantics.Type_Store,
) -> bool {
	effect_var_id := effect_row.type_id
	resolved := semantics.resolve_var(store, effect_var_id)
	v := &store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	inf_effect, inf_is_effect := inf.(semantics.Inferred_Effect_Row)
	if !is_inf || !inf_is_effect {
		return false
	}
	for entry in inf_effect.effects {
		if entry.name == throw_name {
			return true
		}
	}
	return false
}

el_wrap_throw_handler :: proc(
	body: IR_Expr,
	fn_decl: ^IR_Decl_Fn,
	throw_name: base.Intern_ID,
	type_store: ^semantics.Type_Store,
	env: ^Effect_Lower_Env,
) -> IR_Expr {
	if !el_effect_row_has_throw(fn_decl.effect_row, throw_name, type_store) {
		return body
	}

	throw_effect_name := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = throw_name,
		is_local = false,
	}

	throw_op_name := base.intern(env.interner, "throw!")
	resume_id := base.fresh_id(&env.fresh_state, "_resume")
	tag_param := base.fresh_id(&env.fresh_state, "_tag")

	crash_msg := new(IR_Literal_String)
	crash_msg^ = IR_Literal_String {
		value = "Unhandled tag\n",
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = fn_decl.span,
	}

	crash := new(IR_Crash)
	crash^ = IR_Crash {
		message = IR_Expr(crash_msg),
		span    = fn_decl.span,
	}

	arm := IR_Handler_Arm {
		op     = throw_op_name,
		params = make([dynamic]base.Intern_ID, 0, 2),
		body   = IR_Expr(crash),
	}
	append(&arm.params, resume_id)
	append(&arm.params, tag_param)

	arms := make([dynamic]IR_Handler_Arm, 0, 1)
	append(&arms, arm)

	effects := make([dynamic]base.Canonical_Name, 0, 1)
	append(&effects, throw_effect_name)
	handle := new(IR_Handle)
	handle^ = IR_Handle {
		effects = effects,
		body    = body,
		arms    = arms,
		type    = fn_decl.return_type,
		span    = fn_decl.span,
	}
	return IR_Expr(handle)
}

// Effect references in `handle`/`perform` carry the `!` suffix (e.g. `Throw!`),
// but effect definitions store the bare name (e.g. `Throw`). Compare modulo the
// trailing `!` so handler lowering can find the operation signatures.
el_effect_name_matches :: proc(
	def_name, ref_name: base.Intern_ID,
	interner: ^base.Intern_Table,
) -> bool {
	if def_name == ref_name {
		return true
	}
	strip :: proc(s: string) -> string {
		if len(s) > 0 && s[len(s) - 1] == '!' {
			return s[:len(s) - 1]
		}
		return s
	}
	return strip(base.intern_get(interner, def_name)) ==
		strip(base.intern_get(interner, ref_name))
}

el_find_effect_ops :: proc(effect: base.Canonical_Name, env: ^Effect_Lower_Env) -> []IR_Effect_Op {
	for &eff_def in env.module.effect_defs {
		if el_effect_name_matches(eff_def.name.name, effect.name, env.interner) {
			return eff_def.operations[:]
		}
	}
	return nil
}

el_find_arm_index :: proc(
	effect: base.Canonical_Name,
	op: base.Intern_ID,
	env: ^Effect_Lower_Env,
) -> int {
	ops := el_find_effect_ops(effect, env)
	if ops == nil {
		return 0
	}
	for op_def, i in ops {
		if op_def.name == op {
			return i
		}
	}
	return 0
}

el_find_handle_type :: proc(effect: base.Canonical_Name, env: ^Effect_Lower_Env) -> base.IR_Type {
	for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
		ev := env.evidence_stack[i]
		if ev.effect == effect && !ev.inactive {
			return ev.handle_type
		}
	}
	return base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)}
}

el_find_evidence :: proc(effect: base.Canonical_Name, env: ^Effect_Lower_Env) -> base.Intern_ID {
	for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
		ev := env.evidence_stack[i]
		if ev.effect == effect && !ev.inactive {
			return ev.ev_var
		}
	}
	return base.NO_NAME
}

el_replace_resume :: proc(
	expr: IR_Expr,
	resume_id: base.Intern_ID,
	resume_param: base.Intern_ID,
	ev_param: base.Intern_ID,
	env: ^Effect_Lower_Env,
) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Call:
		if e.callee.module == base.NO_NAME && e.callee.name == resume_id {
			resume_val: IR_Expr
			if len(e.args) > 0 {
				resume_val = el_replace_resume(e.args[0], resume_id, resume_param, ev_param, env)
			} else {
				lit := new(IR_Literal_Int)
				lit^ = IR_Literal_Int {
					value = 0,
					type = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
					span = e.span,
				}
				resume_val = IR_Expr(lit)
			}

			ev_expr: IR_Expr = nil
			if ev_param != base.NO_NAME {
				ev_var := new(IR_Var)
				ev_var^ = IR_Var {
					name = ev_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = true,
					},
					span = e.span,
				}
				ev_expr = IR_Expr(ev_var)
			}

			resume := new(IR_Resume)
			resume^ = IR_Resume {
				resume_id = resume_param,
				value     = resume_val,
				ev        = ev_expr,
				type      = e.type,
				span      = e.span,
			}
			return IR_Expr(resume)
		}
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, env))
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

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = el_replace_resume(e.value, resume_id, resume_param, ev_param, env),
			body    = el_replace_resume(e.body, resume_id, resume_param, ev_param, env),
			span    = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Closure_Call:
		// `resume(x)` lowers to an IR_Closure_Call on the `resume` local (it is a
		// let-bound name, not a module decl). Recognize that shape and rewrite it
		// into an IR_Resume so it goes through the continuation ABI (env, value, ev)
		// with the one-shot guard — same as the IR_Call form above.
		if callee_var, is_var := e.callee.(^IR_Var); is_var && callee_var.name == resume_id {
			resume_val: IR_Expr
			if len(e.args) > 0 {
				resume_val = el_replace_resume(e.args[0], resume_id, resume_param, ev_param, env)
			} else {
				lit := new(IR_Literal_Int)
				lit^ = IR_Literal_Int {
					value = 0,
					type = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
					span = e.span,
				}
				resume_val = IR_Expr(lit)
			}

			ev_expr: IR_Expr = nil
			if ev_param != base.NO_NAME {
				ev_var := new(IR_Var)
				ev_var^ = IR_Var {
					name = ev_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = true,
					},
					span = e.span,
				}
				ev_expr = IR_Expr(ev_var)
			}

			resume := new(IR_Resume)
			resume^ = IR_Resume {
				resume_id = resume_param,
				value     = resume_val,
				ev        = ev_expr,
				type      = e.type,
				span      = e.span,
			}
			return IR_Expr(resume)
		}
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = el_replace_resume(e.callee, resume_id, resume_param, ev_param, env),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If {
			condition   = el_replace_resume(e.condition, resume_id, resume_param, ev_param, env),
			then_branch = el_replace_resume(e.then_branch, resume_id, resume_param, ev_param, env),
			else_branch = el_replace_resume(e.else_branch, resume_id, resume_param, ev_param, env),
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
					guard = el_replace_resume(arm.guard, resume_id, resume_param, ev_param, env) if arm.guard != nil else nil,
					body = el_replace_resume(arm.body, resume_id, resume_param, ev_param, env),
				},
			)
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = el_replace_resume(e.scrutinee, resume_id, resume_param, ev_param, env),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, el_replace_resume(stmt, resume_id, resume_param, ev_param, env))
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
			left  = el_replace_resume(e.left, resume_id, resume_param, ev_param, env),
			right = el_replace_resume(e.right, resume_id, resume_param, ev_param, env),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = el_replace_resume(e.value, resume_id, resume_param, ev_param, env),
			span  = e.span,
		}
		return IR_Expr(new_ret)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_replace_resume(p, resume_id, resume_param, ev_param, env))
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
	case ^IR_Expr_Nominal_Construct:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_replace_resume(p, resume_id, resume_param, ev_param, env))
		}
		new_cons := new(IR_Expr_Nominal_Construct)
		new_cons^ = IR_Expr_Nominal_Construct {
			type_name = e.type_name,
			variant   = e.variant,
			payload   = new_payload,
			span      = e.span,
		}
		return IR_Expr(new_cons)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(
				&new_fields,
				IR_Record_Field {
					name = f.name,
					value = el_replace_resume(f.value, resume_id, resume_param, ev_param, env),
				},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = el_replace_resume(e.rest, resume_id, resume_param, ev_param, env),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)
	case ^IR_Construct_Tuple:
		new_elements := make([dynamic]IR_Expr, 0, len(e.elements))
		for el in e.elements {
			append(&new_elements, el_replace_resume(el, resume_id, resume_param, ev_param, env))
		}
		new_tuple := new(IR_Construct_Tuple)
		new_tuple^ = IR_Construct_Tuple {
			elements   = new_elements,
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_tuple)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = el_replace_resume(e.record, resume_id, resume_param, ev_param, env),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Handle:
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(
				&new_arms,
				IR_Handler_Arm {
					op = arm.op,
					params = arm.params,
					body = el_replace_resume(arm.body, resume_id, resume_param, ev_param, env),
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
			body    = el_replace_resume(e.body, resume_id, resume_param, ev_param, env),
			arms    = new_arms,
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, env))
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

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call {
			receiver = el_replace_resume(e.receiver, resume_id, resume_param, ev_param, env),
			method   = e.method,
			args     = new_args,
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure {
			fn_name     = e.fn_name,
			params      = e.params,
			env         = el_replace_resume(e.env, resume_id, resume_param, ev_param, env),
			body        = el_replace_resume(e.body, resume_id, resume_param, ev_param, env),
			type        = e.type,
			return_type = e.return_type,
			span        = e.span,
		}
		return IR_Expr(new_closure)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_replace_resume(arg, resume_id, resume_param, ev_param, env))
		}
		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call {
			callee = e.callee,
			args   = new_args,
			span   = e.span,
		}
		return IR_Expr(new_tc)

	case ^IR_Dup:
		return expr
	case ^IR_Drop:
		return expr
	case ^IR_Resume:
		return expr
	case ^IR_Atomic_Load:
		return expr
	case ^IR_Atomic_Store:
		return expr
	case ^IR_Atomic_RMW:
		return expr
	case ^IR_Atomic_Fence:
		return expr
	case ^IR_Wait:
		return expr
	case ^IR_Notify:
		return expr
	case ^IR_Literal_Int, ^IR_Literal_Float, ^IR_Literal_Bool, ^IR_Literal_String:
		return expr
	case ^IR_Var:
		return expr
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash {
			message = el_replace_resume(e.message, resume_id, resume_param, ev_param, env),
			span    = e.span,
		}
		return IR_Expr(new_crash)
	case ^IR_I32_Load:
		new_load := new(IR_I32_Load)
		new_load^ = IR_I32_Load {
			base   = el_replace_resume(e.base, resume_id, resume_param, ev_param, env),
			offset = e.offset,
			span   = e.span,
		}
		return IR_Expr(new_load)
	case ^IR_I32_Store:
		new_store := new(IR_I32_Store)
		new_store^ = IR_I32_Store {
			base   = el_replace_resume(e.base, resume_id, resume_param, ev_param, env),
			offset = e.offset,
			value  = el_replace_resume(e.value, resume_id, resume_param, ev_param, env),
			span   = e.span,
		}
		return IR_Expr(new_store)
	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign {
			binding = e.binding,
			value   = el_replace_resume(e.value, resume_id, resume_param, ev_param, env),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = el_replace_resume(e.iterable, resume_id, resume_param, ev_param, env),
			body     = el_replace_resume(e.body, resume_id, resume_param, ev_param, env),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	}

	return expr
}

el_make_camp_alloc_call :: proc(
	size: int,
	span: base.Source_Span,
	env: ^Effect_Lower_Env,
) -> IR_Expr {
	size_lit := new(IR_Literal_Int)
	size_lit^ = IR_Literal_Int {
		value = i64(size),
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
		span = span,
	}

	callee := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = env.camp_alloc_id,
		is_local = false,
	}

	args := make([dynamic]IR_Expr, 0, 1)
	append(&args, IR_Expr(size_lit))

	call := new(IR_Call)
	call^ = IR_Call {
		callee = callee,
		args = args,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = false},
		span = span,
		ord_compare_func = base.Canonical_Name{},
	}
	return IR_Expr(call)
}

el_make_camp_dealloc_call :: proc(
	ev_var: base.Intern_ID,
	size: int,
	span: base.Source_Span,
	env: ^Effect_Lower_Env,
) -> IR_Expr {
	ev_var_expr := new(IR_Var)
	ev_var_expr^ = IR_Var {
		name = ev_var,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = span,
	}

	size_lit := new(IR_Literal_Int)
	size_lit^ = IR_Literal_Int {
		value = i64(size),
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
		span = span,
	}

	callee := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = env.camp_dealloc_id,
		is_local = false,
	}

	args := make([dynamic]IR_Expr, 0, 2)
	append(&args, IR_Expr(ev_var_expr))
	append(&args, IR_Expr(size_lit))

	call := new(IR_Call)
	call^ = IR_Call {
		callee = callee,
		args = args,
		type = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
		span = span,
		ord_compare_func = base.Canonical_Name{},
	}
	return IR_Expr(call)
}

el_make_i32_store :: proc(
	base_var: base.Intern_ID,
	offset: int,
	value: IR_Expr,
	span: base.Source_Span,
) -> IR_Expr {
	base_ir := new(IR_Var)
	base_ir^ = IR_Var {
		name = base_var,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = span,
	}

	store := new(IR_I32_Store)
	store^ = IR_I32_Store {
		base   = IR_Expr(base_ir),
		offset = offset,
		value  = value,
		span   = span,
	}
	return IR_Expr(store)
}

el_make_let_void :: proc(
	binding: base.Intern_ID,
	value: IR_Expr,
	body: IR_Expr,
	span: base.Source_Span,
) -> IR_Expr {
	let_expr := new(IR_Let)
	let_expr^ = IR_Let {
		binding = binding,
		type = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
		value = value,
		body = body,
		span = span,
	}
	return IR_Expr(let_expr)
}

el_lower_let_perform :: proc(
	let_expr: ^IR_Let,
	perform: ^IR_Perform,
	env: ^Effect_Lower_Env,
) -> IR_Expr {
	ev_var := el_find_evidence(perform.effect, env)

	if ev_var == base.NO_NAME {
		// Scheduler-mediated effects (File!, Console!, Time!, Async!, Parallel!, Spawn!)
		// are handled directly by the codegen rather than via CPS evidence passing.
		if is_scheduler_effect(perform.effect, env) {
			return IR_Expr(perform) // pass through IR_Perform to codegen
		}
		diagnostics.collector_add_diag(
			env.collector,
			diagnostics.diag_internal("perform without handler evidence", perform.span),
		)
		lit := new(IR_Literal_Int)
		lit^ = IR_Literal_Int {
			value = 0,
			type  = let_expr.type,
			span  = let_expr.span,
		}
		return IR_Expr(lit)
	}

	arm_index := el_find_arm_index(perform.effect, perform.op, env)

	cont_fn_name := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = base.fresh_id(&env.fresh_state, "_kc"),
		is_local = true,
	}
	cont_params := make([dynamic]IR_Param, 0, 2)
	ev_param_for_cont: base.Intern_ID = base.NO_NAME
	append(&cont_params, IR_Param{name = let_expr.binding, type = let_expr.type})
	ev_param_for_cont = base.fresh_id(&env.fresh_state, "_ev")
	append(
		&cont_params,
		IR_Param {
			name = ev_param_for_cont,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		},
	)

	cont_fn_body := el_lower_expr(let_expr.body, env)

	cont_closure := new(IR_Closure)
	cont_closure^ = IR_Closure {
		fn_name     = cont_fn_name,
		params      = cont_params,
		env         = IR_Expr(nil),
		body        = cont_fn_body,
		type        = let_expr.type,
		return_type = let_expr.type,
		span        = let_expr.span,
	}

	cont_fn := new(IR_Decl_Fn)
	cont_fn^ = IR_Decl_Fn {
		name = cont_fn_name,
		is_effectful = false,
		params = cont_params,
		return_type = let_expr.type,
		effect_row = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
		effects = make([dynamic]base.Canonical_Name, 0),
		body = cont_fn_body,
		span = let_expr.span,
	}
	append(&env.module.decls, IR_Decl(cont_fn))

	ev_var_expr := new(IR_Var)
	ev_var_expr^ = IR_Var {
		name = ev_var,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = perform.span,
	}

	closure_load := new(IR_I32_Load)
	closure_load^ = IR_I32_Load {
		base   = IR_Expr(ev_var_expr),
		offset = arm_index * 4,
		span   = perform.span,
	}

	args := make([dynamic]IR_Expr, 0, len(perform.args) + 2)
	for arg in perform.args {
		append(&args, el_lower_expr(arg, env))
	}
	append(&args, IR_Expr(cont_closure))

	ev_arg := new(IR_Var)
	ev_arg^ = IR_Var {
		name = ev_var,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = perform.span,
	}
	append(&args, IR_Expr(ev_arg))

	cc := new(IR_Closure_Call)
	cc^ = IR_Closure_Call {
		callee = IR_Expr(closure_load),
		args   = args,
		type   = let_expr.type,
		span   = let_expr.span,
	}
	return IR_Expr(cc)
}

el_lower_expr :: proc(expr: IR_Expr, env: ^Effect_Lower_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Handle:
		// Scheduler-mediated effects are handled directly by the codegen
		// (they call camp_sched_* runtime functions, not CPS evidence passing)
		// Check if any effect is a scheduler effect
		all_scheduler := len(e.effects) > 0
		for eff in e.effects {
			if !is_scheduler_effect(eff, env) {
				all_scheduler = false
				break
			}
		}
		if all_scheduler {
			new_handle := new(IR_Handle)
			new_handle^ = IR_Handle {
				effects = e.effects,
				body    = el_lower_expr(e.body, env),
				arms    = e.arms, // arms kept for scope_id tracking but not transformed
				type    = e.type,
				span    = e.span,
			}
			return IR_Expr(new_handle)
		}

		ev_var := base.fresh_id(&env.fresh_state, "_ev")

		// effect_ops removed - search across effects per arm instead
		resume_param := base.fresh_id(&env.fresh_state, "_resume")
		ev_param := base.fresh_id(&env.fresh_state, "_ev_arm")
		env_param := base.fresh_id(&env.fresh_state, "_env")

		num_arms := len(e.arms)

		arm_indices: map[base.Intern_ID]int
		arm_indices = make(map[base.Intern_ID]int, num_arms)
		arm_handler_names := make([dynamic]base.Canonical_Name, 0, num_arms)

		for arm, arm_idx in e.arms {
			handler_name_id := base.fresh_id(&env.fresh_state, "handler")
			handler_name := base.Canonical_Name {
				module   = base.NO_NAME,
				name     = handler_name_id,
				is_local = true,
			}

			params := make([dynamic]IR_Param, 0, 4 + len(arm.params))
			append(
				&params,
				IR_Param {
					name = env_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = false,
					},
				},
			)

			// Find the operation definition across all effects
			found_op: IR_Effect_Op
			op_found := false
			for eff in e.effects {
				ops := el_find_effect_ops(eff, env)
				if ops != nil {
					for op in ops {
						if op.name == arm.op {
							found_op = op
							op_found = true
							break
						}
					}
				}
				if op_found do break
			}

			// Add operation params from the handler arm (arm.params[1:] are op params, arm.params[0] is resume_id)
			for i := 1; i < len(arm.params); i += 1 {
				param_id := arm.params[i]
				// Look up the param type from the effect definition
				if op_found {
					if i - 1 < len(found_op.params) {
						append(&params, found_op.params[i - 1])
					} else {
						append(
							&params,
							IR_Param {
								name = param_id,
								type = base.IR_Type {
									wasm_type = .I32,
									type_id = base.Type_Var_ID(0),
								},
							},
						)
					}
				} else {
					append(
						&params,
						IR_Param {
							name = param_id,
							type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
						},
					)
				}
			}

			append(
				&params,
				IR_Param {
					name = resume_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = false,
					},
				},
			)
			append(
				&params,
				IR_Param {
					name = ev_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = false,
					},
				},
			)

			lowered_body := el_lower_expr(arm.body, env)
			transformed_body := el_replace_resume(
				lowered_body,
				arm.params[0],
				resume_param,
				ev_param,
				env,
			)

			// Wrap non-resume body in implicit resume call to the continuation
			if _, is_resume := transformed_body.(^IR_Resume); !is_resume {
				ev_expr: IR_Expr = nil
				if ev_param != base.NO_NAME {
					ev_var2 := new(IR_Var)
					ev_var2^ = IR_Var {
						name = ev_param,
						type = base.IR_Type {
							wasm_type = .I32,
							type_id = base.Type_Var_ID(0),
							is_heap = true,
						},
						span = e.span,
					}
					ev_expr = IR_Expr(ev_var2)
				}
				resume_expr := new(IR_Resume)
				resume_expr^ = IR_Resume {
					resume_id = resume_param,
					value     = transformed_body,
					ev        = ev_expr,
					type      = e.type,
					span      = e.span,
				}
				transformed_body = IR_Expr(resume_expr)
			}

			handler_fn := new(IR_Decl_Fn)
			handler_fn^ = IR_Decl_Fn {
				name = handler_name,
				is_effectful = false,
				params = params,
				return_type = e.type,
				effect_row = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
				effects = make([dynamic]base.Canonical_Name, 0),
				body = transformed_body,
				span = e.span,
			}
			append(&env.module.decls, IR_Decl(handler_fn))
			append(&arm_handler_names, handler_name)
			arm_indices[arm.op] = arm_idx
		}

		for eff in e.effects {
			append(
				&env.evidence_stack,
				Effect_Evidence {
					effect = eff,
					ev_var = ev_var,
					arm_indices = arm_indices,
					handle_type = e.type,
				},
			)
		}
		transformed_body := el_lower_expr(e.body, env)
		for _ in e.effects {
			if len(env.evidence_stack) > 0 {
				pop(&env.evidence_stack)
			}
		}

		ev_record_size := num_arms * 4

		alloc_call := el_make_camp_alloc_call(ev_record_size, e.span, env)

		result: IR_Expr = transformed_body

		for arm, arm_idx in e.arms {
			handler_name := arm_handler_names[arm_idx]

			found_op2: IR_Effect_Op
			op_found2 := false
			for eff in e.effects {
				ops := el_find_effect_ops(eff, env)
				if ops != nil {
					for op in ops {
						if op.name == arm.op {
							found_op2 = op
							op_found2 = true
							break
						}
					}
				}
				if op_found2 do break
			}

			closure_params := make([dynamic]IR_Param, 0, 2 + len(arm.params))
			append(
				&closure_params,
				IR_Param {
					name = env_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = true,
					},
				},
			)
			// Add operation params from the handler arm (arm.params[1:] are op params)
			for i := 1; i < len(arm.params); i += 1 {
				param_id := arm.params[i]
				if op_found2 {
					if i - 1 < len(found_op2.params) {
						append(&closure_params, found_op2.params[i - 1])
					} else {
						append(
							&closure_params,
							IR_Param {
								name = param_id,
								type = base.IR_Type {
									wasm_type = .I32,
									type_id = base.Type_Var_ID(0),
								},
							},
						)
					}
				} else {
					append(
						&closure_params,
						IR_Param {
							name = param_id,
							type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
						},
					)
				}
			}
			append(
				&closure_params,
				IR_Param {
					name = resume_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = true,
					},
				},
			)
			append(
				&closure_params,
				IR_Param {
					name = ev_param,
					type = base.IR_Type {
						wasm_type = .I32,
						type_id = base.Type_Var_ID(0),
						is_heap = true,
					},
				},
			)

			zero_lit := new(IR_Literal_Int)
			zero_lit^ = IR_Literal_Int {
				value = 0,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}

			handler_closure := new(IR_Closure)
			handler_closure^ = IR_Closure {
				fn_name = handler_name,
				params = closure_params,
				env = IR_Expr(zero_lit),
				body = IR_Expr(nil),
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
				return_type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}

			closure_binding := base.fresh_id(&env.fresh_state, "_hcl")

			closure_var := new(IR_Var)
			closure_var^ = IR_Var {
				name = closure_binding,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
				span = e.span,
			}

			store_expr := el_make_i32_store(ev_var, arm_idx * 4, IR_Expr(closure_var), e.span)
			store_binding := base.fresh_id(&env.fresh_state, "_store")

			result = el_make_let_void(store_binding, store_expr, result, e.span)

			closure_let := new(IR_Let)
			closure_let^ = IR_Let {
				binding = closure_binding,
				// The handler closure is stored into the evidence record (which is
				// itself non-heap / not RC-managed) and is consumed later by the
				// perform site. Mark the binding non-heap so rc_insert does not emit
				// a drop of it before the store that transfers it into the record.
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = false,
				},
				value = IR_Expr(handler_closure),
				body = result,
				span = e.span,
			}
			result = IR_Expr(closure_let)
		}
		delete(arm_handler_names)

		let_expr := new(IR_Let)
		let_expr^ = IR_Let {
			binding = ev_var,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = false},
			value = alloc_call,
			body = result,
			span = e.span,
		}
		return IR_Expr(let_expr)

	case ^IR_Let:
		#partial switch v in e.value {
		case ^IR_Perform:
			return el_lower_let_perform(e, v, env)
		case ^IR_Literal_Int,
		     ^IR_Literal_Float,
		     ^IR_Literal_String,
		     ^IR_Literal_Bool,
		     ^IR_Var,
		     ^IR_Let,
		     ^IR_Call,
		     ^IR_Tail_Call,
		     ^IR_If,
		     ^IR_Match,
		     ^IR_Construct_Tag,
		     ^IR_Expr_Nominal_Construct,
		     ^IR_Construct_Record,
		     ^IR_Construct_Tuple,
		     ^IR_Field_Access,
		     ^IR_Method_Call,
		     ^IR_Handle,
		     ^IR_Resume,
		     ^IR_Closure,
		     ^IR_Closure_Call,
		     ^IR_Return,
		     ^IR_Block,
		     ^IR_BinOp,
		     ^IR_Dup,
		     ^IR_Drop,
		     ^IR_Crash,
		     ^IR_I32_Load,
		     ^IR_I32_Store,
		     ^IR_Atomic_Load,
		     ^IR_Atomic_Store,
		     ^IR_Atomic_RMW,
		     ^IR_Atomic_Fence,
		     ^IR_Wait,
		     ^IR_Notify,
		     ^IR_Assign,
		     ^IR_Loop:
		}

		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = el_lower_expr(e.value, env),
			body    = el_lower_expr(e.body, env),
			span    = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Perform:
		ev_var := el_find_evidence(e.effect, env)

		if ev_var == base.NO_NAME {
			// Scheduler-mediated effects are handled directly by the codegen
			if is_scheduler_effect(e.effect, env) {
				return expr // pass through to codegen
			}
			diagnostics.collector_add_diag(
				env.collector,
				diagnostics.diag_internal("perform without handler evidence", e.span),
			)
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int {
				value = 0,
				type  = e.type,
				span  = e.span,
			}
			return IR_Expr(lit)
		}
		arm_index := el_find_arm_index(e.effect, e.op, env)

		cont_fn_name := base.Canonical_Name {
			module   = base.NO_NAME,
			name     = base.fresh_id(&env.fresh_state, "_kc"),
			is_local = true,
		}
		cont_result := base.fresh_id(&env.fresh_state, "_kr")

		handle_type := el_find_handle_type(e.effect, env)
		perf_type := e.type
		if handle_type.wasm_type != .Void {
			perf_type = handle_type
		}

		cont_params := make([dynamic]IR_Param, 0, 2)
		append(&cont_params, IR_Param{name = cont_result, type = perf_type})
		ev_param_for_cont := base.fresh_id(&env.fresh_state, "_ev")
		append(
			&cont_params,
			IR_Param {
				name = ev_param_for_cont,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
			},
		)

		result_var := new(IR_Var)
		result_var^ = IR_Var {
			name = cont_result,
			type = perf_type,
			span = e.span,
		}

		cont_fn := new(IR_Decl_Fn)
		cont_fn^ = IR_Decl_Fn {
			name = cont_fn_name,
			is_effectful = false,
			params = cont_params,
			return_type = perf_type,
			effect_row = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
			effects = make([dynamic]base.Canonical_Name, 0),
			body = IR_Expr(result_var),
			span = e.span,
		}
		append(&env.module.decls, IR_Decl(cont_fn))

		cont_closure := new(IR_Closure)
		cont_closure^ = IR_Closure {
			fn_name     = cont_fn_name,
			params      = cont_params,
			env         = IR_Expr(nil),
			body        = IR_Expr(result_var),
			type        = perf_type,
			return_type = perf_type,
			span        = e.span,
		}

		ev_var_expr := new(IR_Var)
		ev_var_expr^ = IR_Var {
			name = ev_var,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
			span = e.span,
		}

		closure_load := new(IR_I32_Load)
		closure_load^ = IR_I32_Load {
			base   = IR_Expr(ev_var_expr),
			offset = arm_index * 4,
			span   = e.span,
		}

		args := make([dynamic]IR_Expr, 0, len(e.args) + 2)
		for arg in e.args {
			append(&args, el_lower_expr(arg, env))
		}
		append(&args, IR_Expr(cont_closure))

		ev_arg := new(IR_Var)
		ev_arg^ = IR_Var {
			name = ev_var,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
			span = e.span,
		}
		append(&args, IR_Expr(ev_arg))

		cc := new(IR_Closure_Call)
		cc^ = IR_Closure_Call {
			callee = IR_Expr(closure_load),
			args   = args,
			type   = perf_type,
			span   = e.span,
		}
		return IR_Expr(cc)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}

		if callee_effects, ok := env.fn_effects[e.callee]; ok {
			for eff in callee_effects {
				ev_arg_id := el_find_evidence(eff, env)
				if ev_arg_id != base.NO_NAME {
					ev_arg := new(IR_Var)
					ev_arg^ = IR_Var {
						name = ev_arg_id,
						type = base.IR_Type {
							wasm_type = .I32,
							type_id = base.Type_Var_ID(0),
							is_heap = true,
						},
						span = e.span,
					}
					append(&new_args, IR_Expr(ev_arg))
				} else {
					zero_lit := new(IR_Literal_Int)
					zero_lit^ = IR_Literal_Int {
						value = 0,
						type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
						span = e.span,
					}
					append(&new_args, IR_Expr(zero_lit))
				}
			}
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
			append(&new_args, el_lower_expr(arg, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = el_lower_expr(e.callee, env),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}

		if callee_effects, ok := env.fn_effects[e.callee]; ok {
			for eff in callee_effects {
				ev_arg_id := el_find_evidence(eff, env)
				if ev_arg_id != base.NO_NAME {
					ev_arg := new(IR_Var)
					ev_arg^ = IR_Var {
						name = ev_arg_id,
						type = base.IR_Type {
							wasm_type = .I32,
							type_id = base.Type_Var_ID(0),
							is_heap = true,
						},
						span = e.span,
					}
					append(&new_args, IR_Expr(ev_arg))
				} else {
					zero_lit := new(IR_Literal_Int)
					zero_lit^ = IR_Literal_Int {
						value = 0,
						type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
						span = e.span,
					}
					append(&new_args, IR_Expr(zero_lit))
				}
			}
		}

		new_tc := new(IR_Tail_Call)
		new_tc^ = IR_Tail_Call {
			callee = e.callee,
			args   = new_args,
			span   = e.span,
		}
		return IR_Expr(new_tc)

	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If {
			condition   = el_lower_expr(e.condition, env),
			then_branch = el_lower_expr(e.then_branch, env),
			else_branch = el_lower_expr(e.else_branch, env),
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
					guard = el_lower_expr(arm.guard, env) if arm.guard != nil else nil,
					body = el_lower_expr(arm.body, env),
				},
			)
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = el_lower_expr(e.scrutinee, env),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_lower_expr(p, env))
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
	case ^IR_Expr_Nominal_Construct:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, el_lower_expr(p, env))
		}
		new_cons := new(IR_Expr_Nominal_Construct)
		new_cons^ = IR_Expr_Nominal_Construct {
			type_name = e.type_name,
			variant   = e.variant,
			payload   = new_payload,
			span      = e.span,
		}
		return IR_Expr(new_cons)

	case ^IR_Construct_Record:
		new_fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
		for f in e.fields {
			append(
				&new_fields,
				IR_Record_Field{name = f.name, value = el_lower_expr(f.value, env)},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = el_lower_expr(e.rest, env),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)
	case ^IR_Construct_Tuple:
		new_elements := make([dynamic]IR_Expr, 0, len(e.elements))
		for el in e.elements {
			append(&new_elements, el_lower_expr(el, env))
		}
		new_tuple := new(IR_Construct_Tuple)
		new_tuple^ = IR_Construct_Tuple {
			elements   = new_elements,
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_tuple)


	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = el_lower_expr(e.record, env),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, el_lower_expr(arg, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call {
			receiver = el_lower_expr(e.receiver, env),
			method   = e.method,
			args     = new_args,
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = el_lower_expr(e.value, env),
			span  = e.span,
		}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, el_lower_expr(stmt, env))
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
			left  = el_lower_expr(e.left, env),
			right = el_lower_expr(e.right, env),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure {
			fn_name     = e.fn_name,
			params      = e.params,
			env         = el_lower_expr(e.env, env),
			body        = el_lower_expr(e.body, env),
			type        = e.type,
			return_type = e.return_type,
			span        = e.span,
		}
		return IR_Expr(new_closure)

	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash {
			message = el_lower_expr(e.message, env),
			span    = e.span,
		}
		return IR_Expr(new_crash)
	case ^IR_Resume:
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = el_lower_expr(e.ev, env)
		}
		new_resume^ = IR_Resume {
			resume_id = e.resume_id,
			value     = el_lower_expr(e.value, env),
			ev        = ev_val,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_I32_Load:
		new_load := new(IR_I32_Load)
		new_load^ = IR_I32_Load {
			base   = el_lower_expr(e.base, env),
			offset = e.offset,
			span   = e.span,
		}
		return IR_Expr(new_load)

	case ^IR_I32_Store:
		new_store := new(IR_I32_Store)
		new_store^ = IR_I32_Store {
			base   = el_lower_expr(e.base, env),
			offset = e.offset,
			value  = el_lower_expr(e.value, env),
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
			value   = el_lower_expr(e.value, env),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = el_lower_expr(e.iterable, env),
			body     = el_lower_expr(e.body, env),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	}

	return expr
}


package ir

import "camp:base"
import "camp:diagnostics"
import "core:fmt"
import "core:strings"

Closure_Convert_Env :: struct {
	module:            ^IR_Module,
	interner:          ^base.Intern_Table,
	collector:         ^diagnostics.Diagnostic_Collector,
	fresh_state:       base.Fresh_State,
	// Names of synthesized closed_fn decls — references to these are
	// function pointers, not free variables to capture.
	known_fns:         map[base.Intern_ID]bool,
	// Name of the current declaration being closure-converted.
	// Used to detect self-referential closures (recursive).
	current_decl_name: base.Intern_ID,
}


cc_free_vars :: proc(expr: IR_Expr, bound: ^map[base.Intern_ID]bool) -> [dynamic]base.Intern_ID {
	result: [dynamic]base.Intern_ID
	result = make([dynamic]base.Intern_ID, 0, 8)

	#partial switch e in expr {
	case ^IR_Var:
		if _, ok := bound^[e.name]; !ok {
			already := false
			for v in result {
				if v == e.name {
					already = true
					break
				}
			}
			if !already {
				append(&result, e.name)
			}
		}
	case ^IR_Let:
		inner := cc_free_vars(e.value, bound)
		for v in inner {
			append(&result, v)
		}
		delete(inner)

		bound^[e.binding] = true
		body_free := cc_free_vars(e.body, bound)
		for v in body_free {
			append(&result, v)
		}
		delete(body_free)
	case ^IR_Call:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {
				append(&result, v)
			}
			delete(inner)
		}
	case ^IR_Closure_Call:
		callee := cc_free_vars(e.callee, bound)
		for v in callee {append(&result, v)}
		delete(callee)
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Tail_Call:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {
				append(&result, v)
			}
			delete(inner)
		}
	case ^IR_If:
		cond := cc_free_vars(e.condition, bound)
		then_br := cc_free_vars(e.then_branch, bound)
		else_br := cc_free_vars(e.else_branch, bound)
		for v in cond {append(&result, v)}
		for v in then_br {append(&result, v)}
		for v in else_br {append(&result, v)}
		delete(cond)
		delete(then_br)
		delete(else_br)
	case ^IR_BinOp:
		l := cc_free_vars(e.left, bound)
		r := cc_free_vars(e.right, bound)
		for v in l {append(&result, v)}
		for v in r {append(&result, v)}
		delete(l)
		delete(r)
	case ^IR_Crash:
		inner := cc_free_vars(e.message, bound)
		for v in inner {append(&result, v)}
		delete(inner)
	case ^IR_Return:
		inner := cc_free_vars(e.value, bound)
		for v in inner {append(&result, v)}
		delete(inner)
	case ^IR_Block:
		for stmt in e.statements {
			inner := cc_free_vars(stmt, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Construct_Tag:
		for p in e.payload {
			inner := cc_free_vars(p, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Construct_Record:
		for f in e.fields {
			inner := cc_free_vars(f.value, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
		rest := cc_free_vars(e.rest, bound)
		for v in rest {append(&result, v)}
		delete(rest)
	case ^IR_Field_Access:
		inner := cc_free_vars(e.record, bound)
		for v in inner {append(&result, v)}
		delete(inner)
	case ^IR_Method_Call:
		recv := cc_free_vars(e.receiver, bound)
		for v in recv {append(&result, v)}
		delete(recv)
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Handle:
		body := cc_free_vars(e.body, bound)
		for v in body {append(&result, v)}
		delete(body)
		for arm in e.arms {
			bound^[arm.params[0]] = true
			inner := cc_free_vars(arm.body, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Perform:
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Resume:
		if _, ok := bound^[e.resume_id]; !ok {
			already := false
			for v in result {
				if v == e.resume_id {
					already = true
					break
				}
			}
			if !already {
				append(&result, e.resume_id)
			}
		}
		inner := cc_free_vars(e.value, bound)
		for v in inner {append(&result, v)}
		delete(inner)
		if e.ev != nil {
			ev_free := cc_free_vars(e.ev, bound)
			for v in ev_free {append(&result, v)}
			delete(ev_free)
		}
	case ^IR_Closure:
		inner := cc_free_vars(e.body, bound)
		for v in inner {append(&result, v)}
		delete(inner)
	case ^IR_Assign:
		inner := cc_free_vars(e.value, bound)
		for v in inner {append(&result, v)}
		delete(inner)
		// Bind the assigned name so later statements in the same block don't
		// treat it as free.
		bound^[e.binding] = true
	case ^IR_Loop:
		iter := cc_free_vars(e.iterable, bound)
		for v in iter {append(&result, v)}
		delete(iter)
		body := cc_free_vars(e.body, bound)
		for v in body {append(&result, v)}
		delete(body)
	case ^IR_Match:
		scrut := cc_free_vars(e.scrutinee, bound)
		for v in scrut {append(&result, v)}
		delete(scrut)
		for arm in e.arms {
			cc_bind_pattern_vars(arm.pattern, bound)
			inner := cc_free_vars(arm.body, bound)
			for v in inner {append(&result, v)}
			delete(inner)
		}
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Dup,
	     ^IR_Drop,
	     ^IR_I32_Load,
	     ^IR_I32_Store,
	     ^IR_Atomic_Load,
	     ^IR_Atomic_Store,
	     ^IR_Atomic_RMW,
	     ^IR_Atomic_Fence,
	     ^IR_Wait,
	     ^IR_Notify,
	     ^IR_Expr_Nominal_Construct:
	}

	return result
}

// Walks an expression and records the IR_Type seen for each variable name.
// Used to thread free-var types through closure capture so the env record
// load uses the right wasm width (i32 vs i64).
cc_collect_var_types :: proc(expr: IR_Expr, types: ^map[base.Intern_ID]base.IR_Type) {
	if expr == nil do return
	#partial switch e in expr {
	case ^IR_Var:
		if _, exists := types^[e.name]; !exists {
			types^[e.name] = e.type
		}
	case ^IR_Let:
		types^[e.binding] = e.type
		cc_collect_var_types(e.value, types)
		cc_collect_var_types(e.body, types)
	case ^IR_Call:
		for arg in e.args do cc_collect_var_types(arg, types)
	case ^IR_Closure_Call:
		cc_collect_var_types(e.callee, types)
		for arg in e.args do cc_collect_var_types(arg, types)
	case ^IR_Tail_Call:
		for arg in e.args do cc_collect_var_types(arg, types)
	case ^IR_If:
		cc_collect_var_types(e.condition, types)
		cc_collect_var_types(e.then_branch, types)
		cc_collect_var_types(e.else_branch, types)
	case ^IR_BinOp:
		cc_collect_var_types(e.left, types)
		cc_collect_var_types(e.right, types)
	case ^IR_Crash:
		cc_collect_var_types(e.message, types)
	case ^IR_Return:
		cc_collect_var_types(e.value, types)
	case ^IR_Block:
		for stmt in e.statements do cc_collect_var_types(stmt, types)
	case ^IR_Construct_Tag:
		for p in e.payload do cc_collect_var_types(p, types)
	case ^IR_Construct_Record:
		for f in e.fields do cc_collect_var_types(f.value, types)
		cc_collect_var_types(e.rest, types)
	case ^IR_Field_Access:
		cc_collect_var_types(e.record, types)
	case ^IR_Method_Call:
		cc_collect_var_types(e.receiver, types)
		for arg in e.args do cc_collect_var_types(arg, types)
	case ^IR_Handle:
		cc_collect_var_types(e.body, types)
		for arm in e.arms do cc_collect_var_types(arm.body, types)
	case ^IR_Perform:
		for arg in e.args do cc_collect_var_types(arg, types)
	case ^IR_Resume:
		cc_collect_var_types(e.value, types)
		if e.ev != nil do cc_collect_var_types(e.ev, types)
	case ^IR_Closure:
		cc_collect_var_types(e.body, types)
	case ^IR_Assign:
		cc_collect_var_types(e.value, types)
	case ^IR_Loop:
		cc_collect_var_types(e.iterable, types)
		cc_collect_var_types(e.body, types)
	case ^IR_Match:
		cc_collect_var_types(e.scrutinee, types)
		for arm in e.arms do cc_collect_var_types(arm.body, types)
	}
}

cc_bind_pattern_vars :: proc(pat: IR_Pattern, bound: ^map[base.Intern_ID]bool) {
	#partial switch p in pat {
	case ^IR_Pat_Var:
		bound^[p.name] = true
	case ^IR_Pat_Tag:
		for v in p.payload {
			bound^[v] = true
		}
	case ^IR_Pat_Record:
		for f in p.fields {
			bound^[f.binding] = true
		}
		if p.rest != 0 {
			bound^[p.rest] = true
		}
	case ^IR_Pat_Wildcard, ^IR_Pat_Bool, ^IR_Pat_Int, ^IR_Pat_String:
	}
}

closure_convert :: proc(
	mod: ^IR_Module,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
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

	env: Closure_Convert_Env
	env.module = &result
	env.interner = interner
	env.collector = collector
	env.fresh_state = base.Fresh_State {
		counter  = 0,
		interner = interner,
	}

	for decl in mod.decls {
		transformed := cc_convert_decl(decl, &env)
		append(&result.decls, transformed)
	}

	return result
}

cc_convert_decl :: proc(decl: IR_Decl, env: ^Closure_Convert_Env) -> IR_Decl {
	#partial switch d in decl {
	case ^IR_Decl_Fn:
		new_fn := new(IR_Decl_Fn)
		new_fn^ = d^
		new_fn.params = make([dynamic]IR_Param, len(d.params))
		for p, i in d.params {new_fn.params[i] = p}
		new_fn.effects = make([dynamic]base.Canonical_Name, len(d.effects))
		for e, i in d.effects {new_fn.effects[i] = e}
		new_fn.body = cc_convert_expr(d.body, env)
		return IR_Decl(new_fn)
	case ^IR_Decl_Const:
		new_const := new(IR_Decl_Const)
		new_const^ = d^
		env.current_decl_name = d.name.name
		new_const.value = cc_convert_expr(d.value, env)
		env.current_decl_name = 0
		return IR_Decl(new_const)
	case ^IR_Decl_Effect:
		return decl
	}
	return decl
}

cc_convert_expr :: proc(expr: IR_Expr, env: ^Closure_Convert_Env) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Closure:
		// If fn_name is set and body is nil, this is a reference closure
		// pointing to an already-created IR_Decl_Fn (e.g., from effect_lower)
		if e.body == nil && e.fn_name.name != base.NO_NAME {
			// Use IR_Var referencing the function by name — codegen resolves via func_map
			fields := make([dynamic]IR_Record_Field, 0, 2)
			fn_idx_id := base.intern(env.interner, "fn_idx")
			fn_idx_var := new(IR_Var)
			fn_idx_var^ = IR_Var {
				name = e.fn_name.name,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_var)})

			// Add env as a field
			env_id := base.intern(env.interner, "env")
			append(&fields, IR_Record_Field{name = env_id, value = e.env})

			rest_nil := new(IR_Literal_Int)
			rest_nil^ = IR_Literal_Int {
				value = 0,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}

			rec := new(IR_Construct_Record)
			rec^ = IR_Construct_Record {
				fields = fields,
				rest = IR_Expr(rest_nil),
				reuse_addr = NO_REUSE_ADDR,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
				span = e.span,
			}
			return IR_Expr(rec)
		}

		env_param_name := base.fresh_id(&env.fresh_state, "_cenv")

		bound: map[base.Intern_ID]bool
		bound = make(map[base.Intern_ID]bool, 8)
		bound[env_param_name] = true
		for p in e.params {
			bound[p.name] = true
		}

		raw_free := cc_free_vars(e.body, &bound)
		// Filter out references to synthesized closed_fn decls — those are
		// function pointers resolved via func_map, not captured variables.
		free: [dynamic]base.Intern_ID
		free = make([dynamic]base.Intern_ID, 0, len(raw_free))
		for v in raw_free {
			if _, is_fn := env.known_fns[v]; !is_fn {
				append(&free, v)
			}
		}
		delete(raw_free)

		// Detect self-referential closures: if the current declaration name
		// appears as a free variable, the closure references itself (recursive).
		// Remove it from captured vars and mark the closure so codegen stores
		// the closure pointer as its own env field.
		is_self_referential := false
		if env.current_decl_name != 0 {
			filtered_free: [dynamic]base.Intern_ID
			filtered_free = make([dynamic]base.Intern_ID, 0, len(free))
			for fv in free {
				if fv == env.current_decl_name {
					is_self_referential = true
				} else {
					append(&filtered_free, fv)
				}
			}
			if is_self_referential {
				delete(free)
				free = filtered_free
			} else {
				delete(filtered_free)
			}
		}

		// Mutable ($-prefixed) variables are stack-local and cannot escape
		// into a closure. Emit an error for each and remove from capture list.
		mutable_free: [dynamic]base.Intern_ID
		mutable_free = make([dynamic]base.Intern_ID, 0, len(free))
		for fv in free {
			fv_str := base.intern_get(env.interner, fv)
			if strings.has_prefix(fv_str, "$") {
				append(&mutable_free, fv)
			}
		}
		for fv in mutable_free {
			fv_str := base.intern_get(env.interner, fv)
			diagnostics.collector_add_diag(
				env.collector,
				diagnostics.diag_mutable_capture(fv_str, e.span),
			)
		}
		if len(mutable_free) > 0 {
			filtered: [dynamic]base.Intern_ID
			filtered = make([dynamic]base.Intern_ID, 0, len(free) - len(mutable_free))
			mutable_set: map[base.Intern_ID]bool
			mutable_set = make(map[base.Intern_ID]bool, len(mutable_free))
			for fv in mutable_free {
				mutable_set[fv] = true
			}
			for fv in free {
				if _, is_mut := mutable_set[fv]; !is_mut {
					append(&filtered, fv)
				}
			}
			delete(mutable_set)
			delete(free)
			free = filtered
		} else {
			delete(mutable_free)
		}

		// Collect types for free vars so capture stores and env loads use
		// the right wasm width (a captured I64 must round-trip as I64).
		free_types: map[base.Intern_ID]base.IR_Type
		free_types = make(map[base.Intern_ID]base.IR_Type, len(free))
		defer delete(free_types)
		cc_collect_var_types(e.body, &free_types)

		// The _cenv parameter receives the closure's env record when the closure
		// captures free vars (a real heap object), or the closure pointer itself
		// when self-referential. When there are no free vars and the closure is
		// not self-referential, _cenv is a null literal (0) — NOT a heap object.
		// Marking it is_heap=true in that case makes rc_insert emit an IR_Drop for
		// address 0, which faults (camp_drop(0) reads garbage as refcount). Only
		// mark _cenv heap-typed when it actually holds a heap pointer.
		cenv_is_heap := len(free) > 0 || is_self_referential
		params := make([dynamic]IR_Param, 0, len(e.params) + 1)
		append(
			&params,
			IR_Param {
				name = env_param_name,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = cenv_is_heap,
				},
			},
		)
		for p in e.params {
			append(&params, p)
		}

		closed_fn_name := base.Canonical_Name {
			module   = base.NO_NAME,
			name     = base.fresh_id(&env.fresh_state, "closed"),
			is_local = true,
		}

		env_access_map: map[base.Intern_ID]IR_Expr
		env_access_map = make(map[base.Intern_ID]IR_Expr, len(free))
		// The closed function receives the env record (built below) as its
		// first param. Free vars occupy slots 0..N-1 of that record.
		for fv, idx in free {
			ft, ok := free_types[fv]
			if !ok {
				ft = base.IR_Type {
					wasm_type = .I32,
					type_id   = base.Type_Var_ID(0),
				}
			}
			env_access_map[fv] = make_env_field_access(
				env_param_name,
				idx,
				ft,
				e.span,
				env.interner,
			)
		}

		// For self-referential closures, map the declaration name to the
		// _cenv parameter directly. The closed function receives its own
		// closure pointer as _cenv, so recursive calls work via Closure_Call.
		if is_self_referential {
			self_var := new(IR_Var)
			self_var^ = IR_Var {
				name = env_param_name,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			env_access_map[env.current_decl_name] = IR_Expr(self_var)
		}

		converted_body := cc_convert_expr(e.body, env)

		closed_fn := new(IR_Decl_Fn)
		closed_fn^ = IR_Decl_Fn {
			name = closed_fn_name,
			is_effectful = false,
			params = params,
			return_type = e.return_type,
			effect_row = base.IR_Type{wasm_type = .Void, type_id = base.Type_Var_ID(0)},
			effects = make([dynamic]base.Canonical_Name, 0),
			body = rewrite_free_var_access(converted_body, &env_access_map),
			span = e.span,
		}
		append(&env.module.decls, IR_Decl(closed_fn))
		if env.known_fns == nil do env.known_fns = make(map[base.Intern_ID]bool, 8)
		env.known_fns[closed_fn_name.name] = true

		fn_idx_var := new(IR_Var)
		fn_idx_var^ = IR_Var {
			name = closed_fn_name.name,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
			span = e.span,
		}

		// Build a separate env record holding the captured free vars, then a
		// closure record [fn_idx, env_ptr] — matches the IR_Closure layout
		// that IR_Closure_Call expects (slot 0 = fn, slot 1 = env_ptr).
		env_rec_expr: IR_Expr
		if len(free) > 0 {
			env_fields := make([dynamic]IR_Record_Field, 0, len(free))
			for fv in free {
				ft, ok := free_types[fv]
				if !ok {
					ft = base.IR_Type {
						wasm_type = .I32,
						type_id   = base.Type_Var_ID(0),
					}
				}
				fv_var := new(IR_Var)
				fv_var^ = IR_Var {
					name = fv,
					type = ft,
					span = e.span,
				}
				append(&env_fields, IR_Record_Field{name = fv, value = IR_Expr(fv_var)})
			}
			env_nil := new(IR_Literal_Int)
			env_nil^ = IR_Literal_Int {
				value = 0,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			env_rec := new(IR_Construct_Record)
			env_rec^ = IR_Construct_Record {
				fields = env_fields,
				rest = IR_Expr(env_nil),
				reuse_addr = NO_REUSE_ADDR,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
				span = e.span,
			}
			env_rec_expr = IR_Expr(env_rec)
		} else {
			env_nil := new(IR_Literal_Int)
			env_nil^ = IR_Literal_Int {
				value = 0,
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			env_rec_expr = IR_Expr(env_nil)
		}

		if is_self_referential {
			// Self-referential closure: return IR_Closure with is_self_referential flag.
			// The codegen will store the closure pointer as its own env field,
			// enabling the closed function to call itself recursively.
			self_closure := new(IR_Closure)
			self_closure^ = IR_Closure {
				fn_name = closed_fn_name,
				params = make([dynamic]IR_Param, 0),
				env = env_rec_expr,
				body = nil,
				type = base.IR_Type {
					wasm_type = .I32,
					type_id = base.Type_Var_ID(0),
					is_heap = true,
				},
				return_type = e.return_type,
				span = e.span,
				is_self_referential = true,
			}
			delete(env_access_map)
			delete(bound)
			delete(free)
			return IR_Expr(self_closure)
		}

		fields := make([dynamic]IR_Record_Field, 0, 2)
		fn_idx_id := base.intern(env.interner, "fn_idx")
		env_id := base.intern(env.interner, "env")
		append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_var)})
		append(&fields, IR_Record_Field{name = env_id, value = env_rec_expr})

		rest_nil := new(IR_Literal_Int)
		rest_nil^ = IR_Literal_Int {
			value = 0,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
			span = e.span,
		}

		rec := new(IR_Construct_Record)
		rec^ = IR_Construct_Record {
			fields = fields,
			rest = IR_Expr(rest_nil),
			reuse_addr = NO_REUSE_ADDR,
			type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
			span = e.span,
		}

		delete(env_access_map)
		delete(bound)
		delete(free)
		return IR_Expr(rec)

	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = cc_convert_expr(e.value, env),
			body    = cc_convert_expr(e.body, env),
			span    = e.span,
		}
		return IR_Expr(new_let)

	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call {
			callee           = e.callee,
			args             = new_args,
			type             = e.type,
			span             = e.span,
			ord_compare_func = e.ord_compare_func,
			eq_func          = e.eq_func,
		}
		return IR_Expr(new_call)

	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = cc_convert_expr(e.callee, env),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)

	case ^IR_Tail_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
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
			condition   = cc_convert_expr(e.condition, env),
			then_branch = cc_convert_expr(e.then_branch, env),
			else_branch = cc_convert_expr(e.else_branch, env),
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
					guard = cc_convert_expr(arm.guard, env) if arm.guard != nil else nil,
					body = cc_convert_expr(arm.body, env),
				},
			)
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = cc_convert_expr(e.scrutinee, env),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)

	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, cc_convert_expr(p, env))
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
				IR_Record_Field{name = f.name, value = cc_convert_expr(f.value, env)},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = cc_convert_expr(e.rest, env),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)

	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = cc_convert_expr(e.record, env),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)

	case ^IR_Method_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_mc := new(IR_Method_Call)
		new_mc^ = IR_Method_Call {
			receiver = cc_convert_expr(e.receiver, env),
			method   = e.method,
			args     = new_args,
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_mc)

	case ^IR_Handle:
		body := cc_convert_expr(e.body, env)
		new_arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(
				&new_arms,
				IR_Handler_Arm {
					op = arm.op,
					params = arm.params,
					body = cc_convert_expr(arm.body, env),
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
			body    = body,
			arms    = new_arms,
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_handle)

	case ^IR_Perform:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
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
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = cc_convert_expr(e.ev, env)
		}
		new_resume^ = IR_Resume {
			resume_id = e.resume_id,
			value     = cc_convert_expr(e.value, env),
			ev        = ev_val,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_resume)

	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = cc_convert_expr(e.value, env),
			span  = e.span,
		}
		return IR_Expr(new_ret)

	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, cc_convert_expr(stmt, env))
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
			left  = cc_convert_expr(e.left, env),
			right = cc_convert_expr(e.right, env),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)

	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash {
			message = cc_convert_expr(e.message, env),
			span    = e.span,
		}
		return IR_Expr(new_crash)

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
			value   = cc_convert_expr(e.value, env),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = cc_convert_expr(e.iterable, env),
			body     = cc_convert_expr(e.body, env),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	}

	return expr
}

make_env_field_access :: proc(
	env_name: base.Intern_ID,
	field_index: int,
	field_type: base.IR_Type,
	span: base.Source_Span,
	interner: ^base.Intern_Table,
) -> IR_Expr {
	env_var := new(IR_Var)
	env_var^ = IR_Var {
		name = env_name,
		type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true},
		span = span,
	}

	field_access := new(IR_Field_Access)
	field_access^ = IR_Field_Access {
		record      = IR_Expr(env_var),
		field       = base.intern(interner, fmt.tprintf("env_{}", field_index)),
		field_index = field_index,
		type        = field_type,
		span        = span,
	}
	return IR_Expr(field_access)
}

rewrite_free_var_access :: proc(expr: IR_Expr, env_map: ^map[base.Intern_ID]IR_Expr) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Var:
		if replacement, ok := env_map^[e.name]; ok {
			return replacement
		}
		return expr
	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let {
			binding = e.binding,
			type    = e.type,
			value   = rewrite_free_var_access(e.value, env_map),
			body    = rewrite_free_var_access(e.body, env_map),
			span    = e.span,
		}
		return IR_Expr(new_let)
	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rewrite_free_var_access(arg, env_map))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call {
			callee           = e.callee,
			args             = new_args,
			type             = e.type,
			span             = e.span,
			ord_compare_func = e.ord_compare_func,
			eq_func          = e.eq_func,
		}
		return IR_Expr(new_call)
	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rewrite_free_var_access(arg, env_map))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call {
			callee = rewrite_free_var_access(e.callee, env_map),
			args   = new_args,
			type   = e.type,
			span   = e.span,
		}
		return IR_Expr(new_cc)
	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp {
			op    = e.op,
			left  = rewrite_free_var_access(e.left, env_map),
			right = rewrite_free_var_access(e.right, env_map),
			type  = e.type,
			span  = e.span,
		}
		return IR_Expr(new_binop)
	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If {
			condition   = rewrite_free_var_access(e.condition, env_map),
			then_branch = rewrite_free_var_access(e.then_branch, env_map),
			else_branch = rewrite_free_var_access(e.else_branch, env_map),
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_if)
	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return {
			value = rewrite_free_var_access(e.value, env_map),
			span  = e.span,
		}
		return IR_Expr(new_ret)
	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, rewrite_free_var_access(stmt, env_map))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block {
			statements = new_stmts,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_block)
	case ^IR_Match:
		new_arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
		for arm in e.arms {
			append(
				&new_arms,
				IR_Match_Arm {
					pattern = arm.pattern,
					guard = rewrite_free_var_access(arm.guard, env_map) if arm.guard != nil else nil,
					body = rewrite_free_var_access(arm.body, env_map),
				},
			)
		}
		new_match := new(IR_Match)
		new_match^ = IR_Match {
			scrutinee = rewrite_free_var_access(e.scrutinee, env_map),
			arms      = new_arms,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_match)
	case ^IR_Construct_Tag:
		new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&new_payload, rewrite_free_var_access(p, env_map))
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
				IR_Record_Field{name = f.name, value = rewrite_free_var_access(f.value, env_map)},
			)
		}
		new_rec := new(IR_Construct_Record)
		new_rec^ = IR_Construct_Record {
			fields     = new_fields,
			rest       = rewrite_free_var_access(e.rest, env_map),
			reuse_addr = e.reuse_addr,
			type       = e.type,
			span       = e.span,
		}
		return IR_Expr(new_rec)
	case ^IR_Field_Access:
		new_fa := new(IR_Field_Access)
		new_fa^ = IR_Field_Access {
			record      = rewrite_free_var_access(e.record, env_map),
			field       = e.field,
			field_index = e.field_index,
			type        = e.type,
			span        = e.span,
		}
		return IR_Expr(new_fa)
	case ^IR_Resume:
		new_resume := new(IR_Resume)
		ev_val: IR_Expr = nil
		if e.ev != nil {
			ev_val = rewrite_free_var_access(e.ev, env_map)
		}
		new_resume^ = IR_Resume {
			resume_id = e.resume_id,
			value     = rewrite_free_var_access(e.value, env_map),
			ev        = ev_val,
			type      = e.type,
			span      = e.span,
		}
		return IR_Expr(new_resume)
	case ^IR_Assign:
		new_assign := new(IR_Assign)
		new_assign^ = IR_Assign {
			binding = e.binding,
			value   = rewrite_free_var_access(e.value, env_map),
			type    = e.type,
			span    = e.span,
		}
		return IR_Expr(new_assign)
	case ^IR_Loop:
		new_loop := new(IR_Loop)
		new_loop^ = IR_Loop {
			var      = e.var,
			iterable = rewrite_free_var_access(e.iterable, env_map),
			body     = rewrite_free_var_access(e.body, env_map),
			type     = e.type,
			span     = e.span,
		}
		return IR_Expr(new_loop)
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Tail_Call,
	     ^IR_Expr_Nominal_Construct,
	     ^IR_Method_Call,
	     ^IR_Handle,
	     ^IR_Perform,
	     ^IR_Closure,
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
	     ^IR_Notify:
		return expr
	}
	return expr
}


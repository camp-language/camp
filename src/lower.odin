package camp

import "core:fmt"

lower_tfile :: proc(tfile: TFile, store: ^Type_Store) -> IR_Module {
	mod: IR_Module
	mod.decls = make([dynamic]IR_Decl, 0, len(tfile.decls))
	mod.effect_defs = make([dynamic]IR_Effect_Def, 0, 8)
	mod.string_table = make([dynamic]String_Table_Entry, 0, 16)

	env: Lower_Env = {module = &mod, store = store, interner = store.interner}
	env.pending_decls = make([dynamic]IR_Decl, 0, 8)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^TDecl_Effect:
			eff_def := lower_teffect_def(&d^, &env)
			append(&mod.effect_defs, eff_def)
		case:
		}
	}

	inject_prelude_effect_defs(&mod, store)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^TDecl_Const:
			ir_decl := lower_tdecl_const(&d^, &env)
			append(&mod.decls, ir_decl)
		case ^TDecl_Effect:
			ir_decl := lower_tdecl_effect(&d^, &env)
			append(&mod.decls, ir_decl)
		case ^TDecl_Trait:
		case ^TDecl_Alias:
		case ^TDecl_Newtype:
		// Newtypes are erased at runtime — no IR decl needed.
		case ^TDecl_Import:
		case ^TDecl_Test:
		case ^TDecl_Expect:
		}
	}

	for &d in env.pending_decls {
		append(&mod.decls, d)
	}
	delete(env.pending_decls)

	return mod
}

Lower_Env :: struct {
	module:        ^IR_Module,
	store:         ^Type_Store,
	interner:      ^Intern_Table,
	fresh_counter: int,
	pending_decls: [dynamic]IR_Decl,
}

lower_type :: proc(store: ^Type_Store, type_var: Type_Var_ID) -> IR_Type {
	resolved := resolve_var(store, type_var)
	v := get_var(store, resolved)

	wasm_type: IR_Wasm_Type = .I64

	inf, is_inf := v.link.(Inferred_Type)
	if is_inf {
		switch inf.tag {
		case .Primitive:
			name_str := intern_get(store.interner, inf.primitive_name)
			switch name_str {
			case "I64": wasm_type = .I64
			case "I32": wasm_type = .I32
			case "F64": wasm_type = .F64
			case "F32": wasm_type = .F32
			case "Bool": wasm_type = .I32
			case "Str": wasm_type = .I32
			case "Unit": wasm_type = .Void
			case: wasm_type = .I64
			}
		case .Function:
			wasm_type = .Funcref
		case .Record_Row:
			wasm_type = .I32
		case .Tag_Union_Row:
			wasm_type = .I32
		case .Effect_Row:
			wasm_type = .Void
		case .Constructor:
			wasm_type = .I32
		case .Newtype:
			wasm_type = lower_type(store, inf.inner_id).wasm_type
		case .Handle:
			wasm_type = .I32
		}
	}

	return IR_Type{wasm_type = wasm_type, type_id = resolved}
}

lower_effect_type :: proc(store: ^Type_Store, eff_var: Type_Var_ID) -> IR_Type {
	resolved := resolve_var(store, eff_var)
	v := get_var(store, resolved)
	if inf, is_inf := v.link.(Inferred_Type); is_inf && inf.tag == .Effect_Row {
		return IR_Type{wasm_type = .Void, type_id = resolved}
	}
	return IR_Type{wasm_type = .Void, type_id = eff_var}
}

fresh_ir_name :: proc(env: ^Lower_Env) -> Intern_ID {
	name := fmt.tprintf("_ir_{}", env.fresh_counter)
	env.fresh_counter += 1
	return intern(env.interner, name)
}

extract_effects :: proc(store: ^Type_Store, effect_row_var: Type_Var_ID, effect_defs: []IR_Effect_Def) -> [dynamic]Canonical_Name {
	effects: [dynamic]Canonical_Name
	effects = make([dynamic]Canonical_Name, 0, 4)
	collect_effects_from_row(store, effect_row_var, effect_defs, &effects)
	return effects
}

extract_effects_from_fn_binding :: proc(store: ^Type_Store, fn_name: Canonical_Name, effect_defs: []IR_Effect_Def) -> [dynamic]Canonical_Name {
	if fn_name.module != NO_NAME {
		return make([dynamic]Canonical_Name, 0)
	}
	binding_var, ok := store.bindings[fn_name.name]
	if !ok {
		return make([dynamic]Canonical_Name, 0)
	}
	resolved := resolve_var(store, binding_var)
	v := get_var(store, resolved)
	inf, is_inf := v.link.(Inferred_Type)
	tag_str := "none"
	if is_inf { tag_str = fmt.tprintf("%v", inf.tag) }
	if !is_inf || inf.tag != .Function {
		return make([dynamic]Canonical_Name, 0)
	}
	result := extract_effects(store, inf.effect_id, effect_defs)
	return result
}

collect_effects_from_row :: proc(store: ^Type_Store, effect_var: Type_Var_ID, effect_defs: []IR_Effect_Def, result: ^[dynamic]Canonical_Name) {
	resolved := resolve_var(store, effect_var)
	v := get_var(store, resolved)

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf || inf.tag != .Effect_Row {
		return
	}

	for entry in inf.effects {
		for def in effect_defs {
			if def.name.name == entry.name {
				already := false
				for e in result^ {
					if e == def.name {
						already = true
						break
					}
				}
				if !already {
					append(result, def.name)
				}
				break
			}
		}
	}

	rest_resolved := resolve_var(store, inf.rest_id)
	rest_v := get_var(store, rest_resolved)
	rest_inf, rest_is_inf := rest_v.link.(Inferred_Type)
	if rest_is_inf && rest_inf.tag == .Effect_Row {
		collect_effects_from_row(store, inf.rest_id, effect_defs, result)
	}
}

make_ir_lit_int :: proc(value: i64, type_: IR_Type, span: Source_Span) -> IR_Expr {
	lit := new(IR_Literal_Int)
	lit^ = IR_Literal_Int{value = value, type = type_, span = span}
	return IR_Expr(lit)
}

make_ir_lit_bool :: proc(value: bool, type_: IR_Type, span: Source_Span) -> IR_Expr {
	lit := new(IR_Literal_Bool)
	lit^ = IR_Literal_Bool{value = value, type = type_, span = span}
	return IR_Expr(lit)
}


lower_texpr :: proc(expr: TExpr, env: ^Lower_Env) -> IR_Expr {
	switch e in expr {
	case ^TExpr_Int:
		type_var := make_primitive_type(env.store, intern(env.interner, "I64"), e.span)
		return make_ir_lit_int(e.value, lower_type(env.store, type_var), e.span)

	case ^TExpr_Float:
		type_var := make_primitive_type(env.store, intern(env.interner, "F64"), e.span)
		lit := new(IR_Literal_Float)
		lit^ = IR_Literal_Float{value = e.value, type = e.type_, span = e.span}
		return IR_Expr(lit)

	case ^TExpr_String:
		type_var := make_primitive_type(env.store, intern(env.interner, "Str"), e.span)
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = e.value, type = e.type_, span = e.span}
		append(&env.module.string_table, String_Table_Entry{id = fresh_ir_name(env), value = e.value})
		return IR_Expr(lit)

	case ^TExpr_Bool:
		type_var := make_primitive_type(env.store, intern(env.interner, "Bool"), e.span)
		return make_ir_lit_bool(e.value, lower_type(env.store, type_var), e.span)

	case ^TExpr_Name:
		v := new(IR_Var)
		v^ = IR_Var{name = e.name.name, type = e.type_, span = e.span}
		return IR_Expr(v)

	case ^TExpr_Call:
		return lower_tcall(e, env)

	case ^TExpr_Method_Call:
		return lower_tmethod_call(e, env)

	case ^TExpr_Lambda:
		return lower_tlambda(e, env)

	case ^TExpr_Block:
		return lower_tblock(e, env)

	case ^TExpr_If:
		return lower_tif(e, env)

	case ^TExpr_Match:
		return lower_tmatch(e, env)

	case ^TExpr_BinOp:
		return lower_tbinop(e, env)

	case ^TExpr_PrefixOp:
		return lower_tprefixop(e, env)

	case ^TExpr_Tag:
		return lower_ttag(e, env)

	case ^TExpr_Record:
		return lower_trecord(e, env)

	case ^TExpr_Field_Access:
		return lower_tfield_access(e, env)

	case ^TExpr_Record_Update:
		return lower_trecord_update(e, env)

	case ^TExpr_Assign:
		#partial switch target in e.target {
		case ^TExpr_Name:
			value := lower_texpr(e.value, env)
			assign := new(IR_Assign)
			assign^ = IR_Assign{
				binding = target.name.name,
				value   = value,
				type    = e.type_,
				span    = e.span,
			}
			return IR_Expr(assign)
		case:
			return lower_texpr(e.value, env)
		}

	case ^TExpr_Return:
		inner := lower_texpr(e.value, env)
		ret := new(IR_Return)
		ret^ = IR_Return{value = inner, span = e.span}
		return IR_Expr(ret)

	case ^TExpr_Crash:
		msg_expr := lower_texpr(e.message, env)
		crash := new(IR_Crash)
		crash^ = IR_Crash{message = msg_expr, span = e.span}
		return IR_Expr(crash)

	case ^TExpr_Interpolated_String:
		return lower_tinterpolated_string(e, env)

	case ^TExpr_Handle:
		return lower_thandle(e, env)

	case ^TExpr_List:
		return lower_tlist(e, env)

	case ^TExpr_Perform:
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		perf := new(IR_Perform)
		perf^ = IR_Perform{
			effect = e.effect,
			op = e.op,
			args = ir_args,
			type = e.type_,
			span = e.span,
		}
		return IR_Expr(perf)

	case ^TExpr_For:
		iterable := lower_texpr(e.iterable, env)
		body := lower_texpr(e.body, env)
		loop := new(IR_Loop)
		loop^ = IR_Loop{
			var      = e.var,
			iterable = iterable,
			body     = body,
			type     = e.type_,
			span     = e.span,
		}
		return IR_Expr(loop)
	}

	return make_ir_lit_int(0, IR_Type{.I64, Type_Var_ID(-1)}, Source_Span_ZERO)
}

lower_tdecl_const :: proc(d: ^TDecl_Const, env: ^Lower_Env) -> IR_Decl {
	#partial switch body_expr in d.body {
	case ^TExpr_Lambda:
		return lower_tlambda_as_decl(body_expr, d.name, d.is_effectful, d.span, env)
	case:
	}

	ir_type := d.type_
	body := lower_texpr(d.body, env)

	if d.is_effectful {
		fn_decl := new(IR_Decl_Fn)
		fn_decl^ = IR_Decl_Fn{
			name = d.name,
			is_effectful = true,
			params = make([dynamic]IR_Param, 0, 4),
			return_type = ir_type,
			effect_row = d.eff_,
			effects = extract_effects_from_fn_binding(env.store, d.name, env.module.effect_defs[:]),
			body = body,
			span = d.span,
		}
		return IR_Decl(fn_decl)
	}

	decl := new(IR_Decl_Const)
	decl^ = IR_Decl_Const{
		name = d.name,
		type = ir_type,
		value = body,
		span = d.span,
	}
	return IR_Decl(decl)
}

lower_tlambda_as_decl :: proc(e: ^TExpr_Lambda, name: Canonical_Name, is_effectful: bool, span: Source_Span, env: ^Lower_Env) -> IR_Decl {
	params := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		append(&params, IR_Param{name = p.name, type = p.type_})
	}

	body := lower_texpr(e.body, env)

	// Extract effects from the typechecker's resolved function type,
	// not from the annotation's fresh (unlinked) effect row variable.
	// The annotation creates fresh variables that are never connected
	// to the typechecker's results, so e.effects.type_id is Unlinked.
	effects := extract_effects_from_fn_binding(env.store, name, env.module.effect_defs[:])

	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = name,
		is_effectful = is_effectful,
		params = params,
		return_type = e.return_type,
		effect_row = e.effects,
		effects = effects,
		body = body,
		span = span,
	}
	return IR_Decl(fn_decl)
}

lower_tdecl_effect :: proc(d: ^TDecl_Effect, env: ^Lower_Env) -> IR_Decl {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_teffect_op(op, env)
		append(&ops, ir_op)
	}

	decl := new(IR_Decl_Effect)
	decl^ = IR_Decl_Effect{
		name = d.name,
		operations = ops,
		span = d.span,
	}
	return IR_Decl(decl)
}

lower_teffect_def :: proc(d: ^TDecl_Effect, env: ^Lower_Env) -> IR_Effect_Def {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_teffect_op(op, env)
		append(&ops, ir_op)
	}
	type_params := make([dynamic]Intern_ID, 0, len(d.type_params))
	for tp in d.type_params {
		append(&type_params, tp.name)
	}
	return IR_Effect_Def{name = d.name, operations = ops, type_params = type_params}
}

lower_teffect_op :: proc(op: TEffect_Op, env: ^Lower_Env) -> IR_Effect_Op {
	params := make([dynamic]IR_Param, 0, len(op.params))
	for p in op.params {
		append(&params, IR_Param{name = p.name, type = p.type_})
	}

	return IR_Effect_Op{
		name = op.name,
		params = params,
		return_type = op.return_type,
	}
}

inject_prelude_effect_defs :: proc(mod: ^IR_Module, store: ^Type_Store) {
	inject_prelude_effects_lower(mod, store)
}

lower_tcall :: proc(e: ^TExpr_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch c in e.callee {
	case ^TExpr_Name:
		callee_name := c.name
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		call := new(IR_Call)
		call^ = IR_Call{
			callee = callee_name,
			args = ir_args,
			type = e.type_,
			span = e.span,
		}
		return IR_Expr(call)

	case:
		callee_expr := lower_texpr(e.callee, env)
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		ccall := new(IR_Closure_Call)
		ccall^ = IR_Closure_Call{
			callee = callee_expr,
			args = ir_args,
			type = e.type_,
			span = e.span,
		}
		return IR_Expr(ccall)
	}
}

lower_tmethod_call :: proc(e: ^TExpr_Method_Call, env: ^Lower_Env) -> IR_Expr {
	receiver_ir := lower_texpr(e.receiver, env)

	// Check if this is an effect operation call
	receiver_effect_name: Intern_ID = NO_NAME
	receiver_effect_canonical: Canonical_Name
	#partial switch r in e.receiver {
	case ^TExpr_Name:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case ^TExpr_Tag:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case:
	}

	if receiver_effect_name != NO_NAME && is_declared_effect(env.store, receiver_effect_name) {
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		// Look up the effect operation's return type for proper wasm_type resolution
		perf_type := e.type_
		for &eff_def in env.module.effect_defs {
			if eff_def.name == receiver_effect_canonical {
				for op_def in eff_def.operations {
					if op_def.name == e.method.name {
						resolved_type := lower_type(env.store, op_def.return_type.type_id)
						perf_type = resolved_type
						break
					}
				}
				break
			}
		}
		perf := new(IR_Perform)
		perf^ = IR_Perform{
			effect = receiver_effect_canonical,
			op = e.method.name,
			args = ir_args,
			type = perf_type,
			span = e.span,
		}
		return IR_Expr(perf)
	}

	// Check for string method intrinsics: .len() and .slice()
	// We check the receiver type to see if it's a Str
	method_str := intern_get(env.interner, e.method.name)
	receiver_type_var: Type_Var_ID = 0
	#partial switch r in e.receiver {
	case ^TExpr_Name:
		receiver_type_var = r.type_.type_id
	case ^TExpr_String:
		receiver_type_var = r.type_.type_id
	case ^TExpr_Method_Call:
		receiver_type_var = r.type_.type_id
	case ^TExpr_Field_Access:
		receiver_type_var = r.type_.type_id
	case ^TExpr_Call:
		receiver_type_var = r.type_.type_id
	case:
	}

	if receiver_type_var != 0 {
		resolved_type := resolve_var(env.store, receiver_type_var)
		v := get_var(env.store, resolved_type)
		if inf, ok := v.link.(Inferred_Type); ok && inf.tag == .Primitive {
			type_name_str := intern_get(env.interner, inf.primitive_name)
			if type_name_str == "Str" {
				if method_str == "len" && len(e.args) == 0 {
					str_name := intern(env.interner, "Str")
					len_name := intern(env.interner, "length")
					args := make([dynamic]IR_Expr, 0, 1)
					append(&args, receiver_ir)
					call := new(IR_Call)
					call^ = IR_Call{
						callee = Canonical_Name{module = str_name, name = len_name},
						args = args,
						type = e.type_,
						span = e.span,
					}
					return IR_Expr(call)
				}
			}
		}
	}

	ir_args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
	append(&ir_args, receiver_ir)
	for arg in e.args {
		append(&ir_args, lower_texpr(arg, env))
	}

	if e.resolved_.name != 0 {
		meth_call := new(IR_Call)
		meth_call^ = IR_Call{
			callee = e.resolved_,
			args = ir_args,
			type = e.type_,
			span = e.span,
		}
		return IR_Expr(meth_call)
	}

	ccall := new(IR_Closure_Call)
	ccall^ = IR_Closure_Call{
		callee = receiver_ir,
		args = ir_args,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(ccall)
}

lower_tlambda :: proc(e: ^TExpr_Lambda, env: ^Lower_Env) -> IR_Expr {
	name := Canonical_Name{
		module = 0,
		name = fresh_ir_name(env),
		is_local = true,
	}

	params := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		append(&params, IR_Param{name = p.name, type = p.type_})
	}

	body := lower_texpr(e.body, env)

	effects := extract_effects_from_fn_binding(env.store, name, env.module.effect_defs[:])

	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = name,
		is_effectful = false,
		params = params,
		return_type = e.return_type,
		effect_row = e.effects,
		effects = effects,
		body = body,
		span = e.span,
	}
	append(&env.pending_decls, IR_Decl(fn_decl))

	closure_params := make([dynamic]IR_Param, len(params))
	for p, i in params {
		closure_params[i] = p
	}

	closure := new(IR_Closure)
	closure^ = IR_Closure{
		fn_name = name,
		params = closure_params,
		env = IR_Expr(nil),
		body = body,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(closure)
}

lower_tblock :: proc(e: ^TExpr_Block, env: ^Lower_Env) -> IR_Expr {
	if len(e.statements) == 0 {
		return make_ir_lit_int(0, e.type_, e.span)
	}
	last: IR_Expr
	for stmt in e.statements {
		last = lower_texpr(stmt, env)
	}
	return last
}

lower_tif :: proc(e: ^TExpr_If, env: ^Lower_Env) -> IR_Expr {
	cond_ir := lower_texpr(e.condition, env)
	then_ir := lower_texpr(e.then_branch, env)
	else_ir := lower_texpr(e.else_branch, env)
	result := new(IR_If)
	result^ = IR_If{
		condition = cond_ir,
		then_branch = then_ir,
		else_branch = else_ir,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tmatch :: proc(e: ^TExpr_Match, env: ^Lower_Env) -> IR_Expr {
	scrut_ir := lower_texpr(e.scrutinee, env)
	arms := make([dynamic]IR_Match_Arm, len(e.arms))
	for i in 0..<len(e.arms) {
		arms[i] = IR_Match_Arm{
			pattern = lower_tpattern(e.arms[i].pattern, env),
			body = lower_texpr(e.arms[i].body, env),
		}
	}
	result := new(IR_Match)
	result^ = IR_Match{
		scrutinee = scrut_ir,
		arms = arms,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tpattern :: proc(pattern: TPattern, env: ^Lower_Env) -> IR_Pattern {
	switch p in pattern {
	case ^TPattern_Tag:
		payload_ids := make([dynamic]Intern_ID, 0, len(p.payload))
		for sub in p.payload {
			#partial switch s in sub {
			case ^TPattern_Identifier:
				append(&payload_ids, s.name)
			case:
				append(&payload_ids, Intern_ID(0))
			}
		}
		result := new(IR_Pat_Tag)
		result.name = p.name.name
		result.payload = payload_ids
		return IR_Pattern(result)

	case ^TPattern_Record:
		fields_ir := make([dynamic]IR_Pat_Field, len(p.fields))
		for i in 0..<len(p.fields) {
			fields_ir[i] = IR_Pat_Field{
				name = p.fields[i].name,
				binding = p.fields[i].binding,
			}
		}
		result := new(IR_Pat_Record)
		result.fields = fields_ir
		result.is_open = p.is_open
		return IR_Pattern(result)

	case ^TPattern_List:
		nil_tag := new(IR_Pat_Tag)
		nil_tag.name = intern(env.interner, "Nil")
		nil_tag.payload = make([dynamic]Intern_ID, 0)

		list_var := fresh_ir_name(env)
		cons_tag := new(IR_Pat_Tag)
		cons_tag.name = intern(env.interner, "Cons")
		cons_tag.payload = make([dynamic]Intern_ID, 0)
		append(&cons_tag.payload, list_var)

		pat := IR_Pattern(cons_tag)
		for i := len(p.elements) - 1; i >= 0; i -= 1 {
			elem_pat := lower_tpattern(p.elements[i], env)
			if elem_pat != nil {
				if elem_var, ok := elem_pat.(^IR_Pat_Var); ok {
					prev_cons := new(IR_Pat_Tag)
					prev_cons.name = intern(env.interner, "Cons")
					prev_cons.payload = make([dynamic]Intern_ID, 0)
					append(&prev_cons.payload, elem_var.name)
					append(&prev_cons.payload, list_var)
					list_var = elem_var.name
					pat = IR_Pattern(prev_cons)
				}
			}
		}
		return pat

	case ^TPattern_Bool:
		result := new(IR_Pat_Bool)
		result.value = p.value
		return IR_Pattern(result)

	case ^TPattern_Int:
		result := new(IR_Pat_Int)
		result.value = p.value
		return IR_Pattern(result)

	case ^TPattern_String:
		string_id := fresh_ir_name(env)
		append(&env.module.string_table, String_Table_Entry{id = string_id, value = p.value})
		result := new(IR_Pat_String)
		result.string_id = string_id
		return IR_Pattern(result)

	case ^TPattern_Identifier:
		result := new(IR_Pat_Var)
		result.name = p.name
		return IR_Pattern(result)

	case ^TPattern_Wildcard:
		result := new(IR_Pat_Wildcard)
		return IR_Pattern(result)

	case ^TPattern_Destructure:
		result := new(IR_Pat_Var)
		result.name = Intern_ID(0)
		return IR_Pattern(result)
	}
	return IR_Pattern(nil)
}

lower_binop_kind :: proc(op: Token_Kind) -> IR_BinOp_Kind {
	#partial switch op {
	case .Plus:      return .Add
	case .Minus:     return .Sub
	case .Star:      return .Mul
	case .Slash:     return .Div
	case .Percent:   return .Mod
	case .Caret:     return .Exp
	case .Eq_Eq:     return .Eq
	case .Bang_Eq:   return .Ne
	case .Lt:        return .Lt
	case .Gt:        return .Gt
	case .Lt_Eq:     return .Le
	case .Gt_Eq:     return .Ge
	case .Kw_And:    return .And
	case .Kw_Or:     return .Or
	}
	return .Add
}

lower_tbinop :: proc(e: ^TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	// String concatenation: convert `a + b` (when both operands are Str) to Str.concat(a, b)
	if e.op == .Plus {
		resolved := resolve_var(env.store, e.type_.type_id)
		v := get_var(env.store, resolved)
		if inf, ok := v.link.(Inferred_Type); ok && inf.tag == .Primitive {
			name_str := intern_get(env.interner, inf.primitive_name)
			if name_str == "Str" {
				left_ir := lower_texpr(e.left, env)
				right_ir := lower_texpr(e.right, env)
				args := make([dynamic]IR_Expr, 0, 2)
				append(&args, left_ir)
				append(&args, right_ir)
				call := new(IR_Call)
				str_name := intern(env.interner, "Str")
				concat_name := intern(env.interner, "concat")
				call^ = IR_Call{
					callee = Canonical_Name{module = str_name, name = concat_name},
					args = args,
					type = e.type_,
					span = e.span,
				}
				return IR_Expr(call)
			}
		}
	}

	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	result := new(IR_BinOp)
	result^ = IR_BinOp{
		op = lower_binop_kind(e.op),
		left = left_ir,
		right = right_ir,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tprefixop :: proc(e: ^TExpr_PrefixOp, env: ^Lower_Env) -> IR_Expr {
	operand_ir := lower_texpr(e.operand, env)

	#partial switch e.op {
	case .Kw_Not:
		false_lit := make_ir_lit_bool(false, e.type_, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{op = .Eq, left = operand_ir, right = false_lit, type = e.type_, span = e.span}
		return IR_Expr(binop)
	case .Minus:
		zero_lit := make_ir_lit_int(0, e.type_, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{op = .Sub, left = zero_lit, right = operand_ir, type = e.type_, span = e.span}
		return IR_Expr(binop)
	case:
		return operand_ir
	}
}

resolve_tag_index :: proc(store: ^Type_Store, type_var: Type_Var_ID, tag_name: Intern_ID) -> int {
	resolved := resolve_var(store, type_var)
	v := get_var(store, resolved)
	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return 0
	}
	if inf.tag == .Newtype {
		return resolve_tag_index(store, inf.inner_id, tag_name)
	}
	if inf.tag == .Tag_Union_Row {
		for entry, i in inf.tag_entries {
			if entry.name == tag_name {
				return i
			}
		}
	}
	return 0
}

lower_ttag :: proc(e: ^TExpr_Tag, env: ^Lower_Env) -> IR_Expr {
	payload := make([dynamic]IR_Expr, 0, len(e.payload))
	for p in e.payload {
		append(&payload, lower_texpr(p, env))
	}
	tag_index := resolve_tag_index(env.store, e.type_.type_id, e.name.name)
	result := new(IR_Construct_Tag)
	result^ = IR_Construct_Tag{
		tag_name = e.name.name,
		tag_index = tag_index,
		payload = payload,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_trecord :: proc(e: ^TExpr_Record, env: ^Lower_Env) -> IR_Expr {
	fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
	for f in e.fields {
		append(&fields, IR_Record_Field{name = f.name, value = lower_texpr(f.value, env)})
	}
	rest := lower_texpr(e.rest, env)
	result := new(IR_Construct_Record)
	result^ = IR_Construct_Record{
		fields = fields,
		rest = rest,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tfield_access :: proc(e: ^TExpr_Field_Access, env: ^Lower_Env) -> IR_Expr {
	record_ir := lower_texpr(e.record, env)
	result := new(IR_Field_Access)
	result^ = IR_Field_Access{
		record = record_ir,
		field = e.field,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_trecord_update :: proc(e: ^TExpr_Record_Update, env: ^Lower_Env) -> IR_Expr {
	rest_ir := lower_texpr(e.rest, env)
	fields := make([dynamic]IR_Record_Field, 0, len(e.updates))
	for f in e.updates {
		append(&fields, IR_Record_Field{name = f.name, value = lower_texpr(f.value, env)})
	}
	result := new(IR_Construct_Record)
	result^ = IR_Construct_Record{
		fields = fields,
		rest = rest_ir,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tinterpolated_string :: proc(e: ^TExpr_Interpolated_String, env: ^Lower_Env) -> IR_Expr {
	if len(e.parts) == 0 {
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = "", type = e.type_, span = e.span}
		return IR_Expr(lit)
	}

	str_name_id := intern(env.interner, "Str")
	concat_name := intern(env.interner, "concat")

	lower_part :: proc(part: TExpr_String_Part, env: ^Lower_Env, str_type: IR_Type, span: Source_Span) -> IR_Expr {
		switch p in part {
		case ^TExpr_String_Literal:
			lit := new(IR_Literal_String)
			lit^ = IR_Literal_String{value = p.value, type = p.type_, span = p.span}
			append(&env.module.string_table, String_Table_Entry{id = fresh_ir_name(env), value = p.value})
			return IR_Expr(lit)
		case ^TExpr_String_Expr:
			inner := lower_texpr(p.expr, env)
			if p.needs_to_str {
				args := make([dynamic]IR_Expr, 0, 1)
				append(&args, inner)
				call := new(IR_Call)
				call^ = IR_Call{
					callee = p.display_impl,
					args = args,
					type = str_type,
					span = span,
				}
				return IR_Expr(call)
			}
			return inner
		}
		return make_ir_lit_int(0, IR_Type{.I64, Type_Var_ID(-1)}, Source_Span_ZERO)
	}

	result := lower_part(e.parts[0], env, e.type_, e.span)
	for i := 1; i < len(e.parts); i += 1 {
		right := lower_part(e.parts[i], env, e.type_, e.span)
		args := make([dynamic]IR_Expr, 0, 2)
		append(&args, result)
		append(&args, right)
		call := new(IR_Call)
		call^ = IR_Call{
			callee = Canonical_Name{module = str_name_id, name = concat_name},
			args = args,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(call)
	}
	return result
}

lower_thandle :: proc(e: ^TExpr_Handle, env: ^Lower_Env) -> IR_Expr {
	body_ir := lower_texpr(e.body, env)
	arms := make([dynamic]IR_Handler_Arm, len(e.arms))
	for i in 0..<len(e.arms) {
		arms[i] = IR_Handler_Arm{
			op = e.arms[i].op,
			params = e.arms[i].params,
			body = lower_texpr(e.arms[i].body, env),
		}
	}
	result := new(IR_Handle)
	result^ = IR_Handle{
		effect = e.effect,
		is_shallow = e.is_shallow,
		body = body_ir,
		arms = arms,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tlist :: proc(e: ^TExpr_List, env: ^Lower_Env) -> IR_Expr {
	nil_name := intern(env.interner, "Nil")
	cons_name := intern(env.interner, "Cons")
	nil_index := resolve_tag_index(env.store, e.type_.type_id, nil_name)
	cons_index := resolve_tag_index(env.store, e.type_.type_id, cons_name)

	nil_tag := new(IR_Construct_Tag)
	nil_tag^ = IR_Construct_Tag{
		tag_name = nil_name,
		tag_index = nil_index,
		payload = make([dynamic]IR_Expr, 0),
		type = e.type_,
		span = e.span,
	}

	result: IR_Expr = IR_Expr(nil_tag)
	for i := len(e.elements) - 1; i >= 0; i -= 1 {
		elem := lower_texpr(e.elements[i], env)
		cons_payload := make([dynamic]IR_Expr, 0, 2)
		append(&cons_payload, elem)
		append(&cons_payload, result)
		cons_tag := new(IR_Construct_Tag)
		cons_tag^ = IR_Construct_Tag{
			tag_name = cons_name,
			tag_index = cons_index,
			payload = cons_payload,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}



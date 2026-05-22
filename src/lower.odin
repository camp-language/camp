package camp

import "core:fmt"

lower_file :: proc(cfile: CFile, store: ^Type_Store) -> IR_Module {
	mod: IR_Module
	mod.decls = make([dynamic]IR_Decl, 0, len(cfile.decls))
	mod.effect_defs = make([dynamic]IR_Effect_Def, 0, 8)
	mod.string_table = make([dynamic]String_Table_Entry, 0, 16)

	env: Lower_Env = {module = &mod, store = store, interner = store.interner}
	env.pending_decls = make([dynamic]IR_Decl, 0, 8)

	for &decl in cfile.decls {
		#partial switch d in decl {
		case ^CDecl_Effect:
			eff_def := lower_effect_def(d^, &env)
			append(&mod.effect_defs, eff_def)
		case:
		}
	}

	for &decl in cfile.decls {
		#partial switch d in decl {
		case ^CDecl_Const:
			ir_decl := lower_decl_const(d^, &env)
			append(&mod.decls, ir_decl)
		case ^CDecl_Effect:
			ir_decl := lower_decl_effect(d^, &env)
			append(&mod.decls, ir_decl)
		case ^CDecl_Newtype:
		case:
		}
	}

	for &d in env.pending_decls {
		append(&mod.decls, d)
	}
	delete(env.pending_decls)

	return mod
}

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
		}
	}

	return IR_Type{wasm_type = wasm_type, type_id = resolved}
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

lower_decl_const :: proc(d: CDecl_Const, env: ^Lower_Env) -> IR_Decl {
	#partial switch body_expr in d.body {
	case ^CExpr_Lambda:
		return lower_lambda_as_decl(body_expr, d.name, d.is_effectful, d.span, env)
	case:
	}

	type_var: Type_Var_ID = 0
	if d.type_ann != nil {
		type_var = convert_type_to_var(d.type_ann, env.store)
	} else {
		type_var = fresh_value_var(env.store, d.span)
	}
	ir_type := lower_type(env.store, type_var)

	body := lower_expr(d.body, env)

	if d.is_effectful {
		fn_decl := new(IR_Decl_Fn)
		fn_decl^ = IR_Decl_Fn{
			name = d.name,
			is_effectful = true,
			params = make([dynamic]IR_Param, 0, 4),
			return_type = ir_type,
			effect_row = IR_Type{.Void, type_var},
			effects = extract_effects(env.store, type_var, env.module.effect_defs[:]),
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

lower_lambda_as_decl :: proc(e: ^CExpr_Lambda, name: Canonical_Name, is_effectful: bool, span: Source_Span, env: ^Lower_Env) -> IR_Decl {
	params := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		p_type_var := fresh_value_var(env.store, p.span)
		if p.type_ann != nil {
			p_type_var = convert_type_to_var(p.type_ann, env.store)
		}
		append(&params, IR_Param{name = p.name, type = lower_type(env.store, p_type_var)})
	}

	body := lower_expr(e.body, env)

	ret_type_var := fresh_value_var(env.store, span)
	if e.return_type != nil {
		ret_type_var = convert_type_to_var(e.return_type, env.store)
	}
	ir_ret_type := lower_type(env.store, ret_type_var)

	eff_type_var := fresh_effect_row(env.store, span)
	if e.effects != nil {
		eff_type_var = convert_type_to_var(e.effects, env.store)
	}

	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = name,
		is_effectful = is_effectful,
		params = params,
		return_type = ir_ret_type,
		effect_row = IR_Type{.Void, eff_type_var},
		effects = extract_effects(env.store, eff_type_var, env.module.effect_defs[:]),
		body = body,
		span = span,
	}
	return IR_Decl(fn_decl)
}

lower_decl_effect :: proc(d: CDecl_Effect, env: ^Lower_Env) -> IR_Decl {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_effect_op(op, env)
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

lower_effect_def :: proc(d: CDecl_Effect, env: ^Lower_Env) -> IR_Effect_Def {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_effect_op(op, env)
		append(&ops, ir_op)
	}
	type_params := make([dynamic]Intern_ID, 0, len(d.type_params))
	for tp in d.type_params {
		append(&type_params, tp.name)
	}
	return IR_Effect_Def{name = d.name, operations = ops, type_params = type_params}
}

lower_effect_op :: proc(op: CEffect_Op, env: ^Lower_Env) -> IR_Effect_Op {
	params := make([dynamic]IR_Param, 0, len(op.params))
	for p in op.params {
		p_type_var := fresh_value_var(env.store, p.span)
		if p.type_ann != nil {
			p_type_var = convert_type_to_var(p.type_ann, env.store)
		}
		append(&params, IR_Param{name = p.name, type = lower_type(env.store, p_type_var)})
	}

	ret_type_var := fresh_value_var(env.store, op.span)
	if op.return_type != nil {
		ret_type_var = convert_type_to_var(op.return_type, env.store)
	}

	return IR_Effect_Op{
		name = op.name,
		params = params,
		return_type = lower_type(env.store, ret_type_var),
	}
}

lower_expr :: proc(expr: CExpr, env: ^Lower_Env) -> IR_Expr {
	switch e in expr {
	case ^CExpr_Int:
		type_var := make_primitive_type(env.store, intern(env.interner, "I64"), e.span)
		return make_ir_lit_int(e.value, lower_type(env.store, type_var), e.span)

	case ^CExpr_Float:
		type_var := make_primitive_type(env.store, intern(env.interner, "F64"), e.span)
		lit := new(IR_Literal_Float)
		lit^ = IR_Literal_Float{value = e.value, type = lower_type(env.store, type_var), span = e.span}
		return IR_Expr(lit)

	case ^CExpr_String:
		type_var := make_primitive_type(env.store, intern(env.interner, "Str"), e.span)
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = e.value, type = lower_type(env.store, type_var), span = e.span}
		append(&env.module.string_table, String_Table_Entry{id = fresh_ir_name(env), value = e.value})
		return IR_Expr(lit)

	case ^CExpr_Bool:
		type_var := make_primitive_type(env.store, intern(env.interner, "Bool"), e.span)
		return make_ir_lit_bool(e.value, lower_type(env.store, type_var), e.span)

	case ^CExpr_Name:
		type_var := fresh_value_var(env.store, e.span)
		v := new(IR_Var)
		v^ = IR_Var{name = e.name.name, type = lower_type(env.store, type_var), span = e.span}
		return IR_Expr(v)

	case ^CExpr_Call:
		return lower_call(e, env)

	case ^CExpr_Method_Call:
		return lower_method_call(e, env)

	case ^CExpr_Lambda:
		return lower_lambda(e, env)

	case ^CExpr_Block:
		return lower_block(e, env)

	case ^CExpr_If:
		return lower_if(e, env)

	case ^CExpr_Match:
		return lower_match(e, env)

	case ^CExpr_BinOp:
		return lower_binop(e, env)

	case ^CExpr_PrefixOp:
		return lower_prefixop(e, env)

	case ^CExpr_Tag:
		return lower_tag(e, env)

	case ^CExpr_Record:
		return lower_record(e, env)

	case ^CExpr_Field_Access:
		return lower_field_access(e, env)

	case ^CExpr_Record_Update:
		return lower_record_update(e, env)

	case ^CExpr_Assign:
		_ = lower_expr(e.target, env)
		return lower_expr(e.value, env)

	case ^CExpr_Return:
		inner := lower_expr(e.value, env)
		ret := new(IR_Return)
		ret^ = IR_Return{value = inner, span = e.span}
		return IR_Expr(ret)

	case ^CExpr_Crash:
		msg_expr := lower_expr(e.message, env)
		crash := new(IR_Crash)
		crash^ = IR_Crash{message = msg_expr, span = e.span}
		return IR_Expr(crash)

	case ^CExpr_Interpolate:
		return lower_interpolate(e, env)

	case ^CExpr_Handle:
		return lower_handle(e, env)

	case ^CExpr_List:
		return lower_list(e, env)
	}

	return make_ir_lit_int(0, IR_Type{.I64, Type_Var_ID(-1)}, Source_Span_ZERO)
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
		_ = lower_texpr(e.target, env)
		return lower_texpr(e.value, env)

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

	case ^TExpr_Interpolate:
		return lower_tinterpolate(e, env)

	case ^TExpr_Handle:
		return lower_thandle(e, env)

	case ^TExpr_List:
		return lower_tlist(e, env)
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

lower_call :: proc(e: ^CExpr_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch c in e.callee {
	case ^CExpr_Name:
		callee_name := c.name
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_expr(arg, env))
		}
		type_var := fresh_value_var(env.store, e.span)
		call := new(IR_Call)
		call^ = IR_Call{
			callee = callee_name,
			args = ir_args,
			type = lower_type(env.store, type_var),
			span = e.span,
		}
		return IR_Expr(call)

	case:
		callee_expr := lower_expr(e.callee, env)
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_expr(arg, env))
		}
		type_var := fresh_value_var(env.store, e.span)
		ccall := new(IR_Closure_Call)
		ccall^ = IR_Closure_Call{
			callee = callee_expr,
			args = ir_args,
			type = lower_type(env.store, type_var),
			span = e.span,
		}
		return IR_Expr(ccall)
	}
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
	fn_decl := lower_tlambda_as_decl(e, name, false, e.span, env)
	append(&env.pending_decls, fn_decl)
	v := new(IR_Var)
	v^ = IR_Var{name = name.name, type = e.type_, span = e.span}
	return IR_Expr(v)
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

	case ^TPattern_Int, ^TPattern_String, ^TPattern_Bool:
		result := new(IR_Pat_Var)
		result.name = Intern_ID(0)
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

lower_tbinop :: proc(e: ^TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	result := new(IR_BinOp)
	result^ = IR_BinOp{
		op = e.op,
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
		binop^ = IR_BinOp{op = .Eq_Eq, left = operand_ir, right = false_lit, type = e.type_, span = e.span}
		return IR_Expr(binop)
	case .Minus:
		zero_lit := make_ir_lit_int(0, e.type_, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{op = .Minus, left = zero_lit, right = operand_ir, type = e.type_, span = e.span}
		return IR_Expr(binop)
	case:
		return operand_ir
	}
}

lower_ttag :: proc(e: ^TExpr_Tag, env: ^Lower_Env) -> IR_Expr {
	payload := make([dynamic]IR_Expr, 0, len(e.payload))
	for p in e.payload {
		append(&payload, lower_texpr(p, env))
	}
	result := new(IR_Construct_Tag)
	result^ = IR_Construct_Tag{
		tag_name = e.name.name,
		tag_index = 0,
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

lower_tinterpolate :: proc(e: ^TExpr_Interpolate, env: ^Lower_Env) -> IR_Expr {
	if len(e.parts) == 0 {
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = "", type = e.type_, span = e.span}
		return IR_Expr(lit)
	}

	result := lower_texpr(e.parts[0], env)
	for i := 1; i < len(e.parts); i += 1 {
		right := lower_texpr(e.parts[i], env)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{
			op = .Plus,
			left = result,
			right = right,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(binop)
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
	nil_tag := new(IR_Construct_Tag)
	nil_tag^ = IR_Construct_Tag{
		tag_name = intern(env.interner, "Nil"),
		tag_index = 0,
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
			tag_name = intern(env.interner, "Cons"),
			tag_index = 0,
			payload = cons_payload,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}

lower_method_call :: proc(e: ^CExpr_Method_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch r in e.receiver {
	case ^CExpr_Tag:
		if is_declared_newtype(env.store, r.name.name) && len(r.payload) == 0 && len(e.args) >= 1 {
			inner_name := intern(env.interner, "inner")
			if e.method.name == inner_name && len(e.args) == 0 {
				return lower_expr(e.receiver, env)
			}
			payload := make([dynamic]IR_Expr, 0, len(e.args))
			for a in e.args {
				append(&payload, lower_expr(a, env))
			}
			type_var := fresh_value_var(env.store, e.span)
			tag := new(IR_Construct_Tag)
			tag^ = IR_Construct_Tag{
				tag_name = e.method.name,
				tag_index = 0,
				payload = payload,
				type = lower_type(env.store, type_var),
				span = e.span,
			}
			return IR_Expr(tag)
		}
	case:
	}

	receiver := lower_expr(e.receiver, env)

	inner_name := intern(env.interner, "inner")
	if e.method.name == inner_name && len(e.args) == 0 {
		return receiver
	}

	ir_args := make([dynamic]IR_Expr, 0, len(e.args))
	for arg in e.args {
		append(&ir_args, lower_expr(arg, env))
	}

	receiver_effect_name: Intern_ID = NO_NAME
	receiver_effect_canonical: Canonical_Name
	#partial switch r in e.receiver {
	case ^CExpr_Name:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case ^CExpr_Tag:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case:
	}

	if receiver_effect_name != NO_NAME && is_declared_effect(env.store, receiver_effect_name) {
		perf := new(IR_Perform)
		perf^ = IR_Perform{
			effect = receiver_effect_canonical,
			op = e.method.name,
			args = ir_args,
			type = IR_Type{.I32, fresh_value_var(env.store, e.span)},
			span = e.span,
		}
		return IR_Expr(perf)
	}

	if is_declared_effect(env.store, e.method.name) {
		perf := new(IR_Perform)
		perf^ = IR_Perform{
			effect = e.method,
			op = e.method.name,
			args = ir_args,
			type = IR_Type{.I32, fresh_value_var(env.store, e.span)},
			span = e.span,
		}
		return IR_Expr(perf)
	}

	type_var := fresh_value_var(env.store, e.span)
	mc := new(IR_Method_Call)
	mc^ = IR_Method_Call{
		receiver = receiver,
		method = e.method.name,
		args = ir_args,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(mc)
}

lower_lambda :: proc(e: ^CExpr_Lambda, env: ^Lower_Env) -> IR_Expr {
	fn_name := Canonical_Name{module = NO_NAME, name = fresh_ir_name(env), is_local = true}

	param_types := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		p_type_var := fresh_value_var(env.store, p.span)
		if p.type_ann != nil {
			p_type_var = convert_type_to_var(p.type_ann, env.store)
		}
		append(&param_types, IR_Param{name = p.name, type = lower_type(env.store, p_type_var)})
	}

	body := lower_expr(e.body, env)

	ret_type_var := fresh_value_var(env.store, e.span)
	if e.return_type != nil {
		ret_type_var = convert_type_to_var(e.return_type, env.store)
	}
	ir_ret_type := lower_type(env.store, ret_type_var)

	fn_type_var := fresh_value_var(env.store, e.span)
	ir_fn_type := lower_type(env.store, fn_type_var)

	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = fn_name,
		is_effectful = false,
		params = param_types,
		return_type = ir_ret_type,
		effect_row = IR_Type{.Void, fresh_effect_row(env.store, e.span)},
		effects = make([dynamic]Canonical_Name, 0),
		body = body,
		span = e.span,
	}
	append(&env.pending_decls, IR_Decl(fn_decl))

	closure_params := make([dynamic]IR_Param, len(param_types))
	for p, i in param_types {
		closure_params[i] = p
	}

	closure := new(IR_Closure)
	closure^ = IR_Closure{
		fn_name = fn_name,
		params = closure_params,
		env = IR_Expr(nil),
		body = body,
		type = ir_fn_type,
		span = e.span,
	}
	return IR_Expr(closure)
}

lower_block :: proc(e: ^CExpr_Block, env: ^Lower_Env) -> IR_Expr {
	if len(e.statements) == 0 {
		unit_type := lower_type(env.store, make_primitive_type(env.store, intern(env.interner, "Unit"), e.span))
		block := new(IR_Block)
		block^ = IR_Block{statements = make([dynamic]IR_Expr, 0), type = unit_type, span = e.span}
		return IR_Expr(block)
	}

	type_var := fresh_value_var(env.store, e.span)
	result := lower_expr(e.statements[len(e.statements)-1], env)

	for i := len(e.statements) - 2; i >= 0; i -= 1 {
		is_assign_or_skip := false
		#partial switch s in e.statements[i] {
		case ^CExpr_Assign:
			#partial switch target in s.target {
			case ^CExpr_Name:
				let_expr := new(IR_Let)
				let_expr^ = IR_Let{
					binding = target.name.name,
					type    = lower_type(env.store, type_var),
					value   = lower_expr(s.value, env),
					body    = result,
					span    = e.span,
				}
				result = IR_Expr(let_expr)
				is_assign_or_skip = true
			}
		}
		if is_assign_or_skip {
			continue
		}
		stmts := make([dynamic]IR_Expr, 2)
		stmts[0] = lower_expr(e.statements[i], env)
		stmts[1] = result
		block := new(IR_Block)
		block^ = IR_Block{statements = stmts, type = lower_type(env.store, type_var), span = e.span}
		result = IR_Expr(block)
	}

	return result
}

lower_if :: proc(e: ^CExpr_If, env: ^Lower_Env) -> IR_Expr {
	cond := lower_expr(e.condition, env)
	then_br := lower_expr(e.then_branch, env)
	else_br := lower_expr(e.else_branch, env)

	type_var := fresh_value_var(env.store, e.span)
	ir_if := new(IR_If)
	ir_if^ = IR_If{
		condition = cond,
		then_branch = then_br,
		else_branch = else_br,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(ir_if)
}

lower_match :: proc(e: ^CExpr_Match, env: ^Lower_Env) -> IR_Expr {
	scrutinee := lower_expr(e.scrutinee, env)

	arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
	for arm in e.arms {
		append(&arms, IR_Match_Arm{
			pattern = lower_pattern(arm.pattern, env),
			body = lower_expr(arm.body, env),
		})
	}

	type_var := fresh_value_var(env.store, e.span)
	m := new(IR_Match)
	m^ = IR_Match{
		scrutinee = scrutinee,
		arms = arms,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(m)
}

lower_pattern :: proc(pat: CPattern, env: ^Lower_Env) -> IR_Pattern {
	switch p in pat {
	case ^CPattern_Tag:
		payload_ids := make([dynamic]Intern_ID, 0, len(p.payload))
		for sub in p.payload {
			#partial switch s in sub {
			case ^CPattern_Identifier:
				append(&payload_ids, s.name)
			case:
				append(&payload_ids, fresh_ir_name(env))
			}
		}
		ir_pat := new(IR_Pat_Tag)
		ir_pat^ = IR_Pat_Tag{name = p.name.name, payload = payload_ids}
		return IR_Pattern(ir_pat)

	case ^CPattern_Record:
		fields := make([dynamic]IR_Pat_Field, 0, len(p.fields))
		for f in p.fields {
			append(&fields, IR_Pat_Field{name = f.name, binding = f.binding})
		}
		ir_pat := new(IR_Pat_Record)
		ir_pat^ = IR_Pat_Record{fields = fields, is_open = p.is_open}
		return IR_Pattern(ir_pat)

	case ^CPattern_Identifier:
		ir_pat := new(IR_Pat_Var)
		ir_pat^ = IR_Pat_Var{name = p.name}
		return IR_Pattern(ir_pat)

	case ^CPattern_Wildcard:
		ir_pat := new(IR_Pat_Wildcard)
		ir_pat^ = IR_Pat_Wildcard{}
		return IR_Pattern(ir_pat)

	case ^CPattern_Int, ^CPattern_String, ^CPattern_Bool, ^CPattern_List, ^CPattern_Destructure:
		ir_pat := new(IR_Pat_Wildcard)
		ir_pat^ = IR_Pat_Wildcard{}
		return IR_Pattern(ir_pat)
	}

	ir_pat := new(IR_Pat_Wildcard)
	ir_pat^ = IR_Pat_Wildcard{}
	return IR_Pattern(ir_pat)
}

lower_binop :: proc(e: ^CExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	left := lower_expr(e.left, env)
	right := lower_expr(e.right, env)

	type_var := fresh_value_var(env.store, e.span)
	binop := new(IR_BinOp)
	binop^ = IR_BinOp{
		op = e.op,
		left = left,
		right = right,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(binop)
}

lower_prefixop :: proc(e: ^CExpr_PrefixOp, env: ^Lower_Env) -> IR_Expr {
	operand := lower_expr(e.operand, env)

	#partial switch e.op {
	case .Kw_Not:
		bool_type := lower_type(env.store, make_primitive_type(env.store, intern(env.interner, "Bool"), e.span))
		false_lit := make_ir_lit_bool(false, bool_type, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{op = .Eq_Eq, left = operand, right = false_lit, type = bool_type, span = e.span}
		return IR_Expr(binop)
	case .Minus:
		type_var := fresh_value_var(env.store, e.span)
		ir_type := lower_type(env.store, type_var)
		zero_lit := make_ir_lit_int(0, ir_type, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{op = .Minus, left = zero_lit, right = operand, type = ir_type, span = e.span}
		return IR_Expr(binop)
	case:
		return operand
	}
}

lower_tag :: proc(e: ^CExpr_Tag, env: ^Lower_Env) -> IR_Expr {
	if is_declared_newtype(env.store, e.name.name) && len(e.payload) == 1 {
		return lower_expr(e.payload[0], env)
	}

	payload := make([dynamic]IR_Expr, 0, len(e.payload))
	for p in e.payload {
		append(&payload, lower_expr(p, env))
	}

	type_var := fresh_value_var(env.store, e.span)
	tag := new(IR_Construct_Tag)
	tag^ = IR_Construct_Tag{
		tag_name = e.name.name,
		tag_index = 0,
		payload = payload,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(tag)
}

lower_record :: proc(e: ^CExpr_Record, env: ^Lower_Env) -> IR_Expr {
	fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
	for f in e.fields {
		append(&fields, IR_Record_Field{name = f.name, value = lower_expr(f.value, env)})
	}

	rest := lower_expr(e.rest, env)

	type_var := fresh_value_var(env.store, e.span)
	rec := new(IR_Construct_Record)
	rec^ = IR_Construct_Record{
		fields = fields,
		rest = rest,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(rec)
}

lower_field_access :: proc(e: ^CExpr_Field_Access, env: ^Lower_Env) -> IR_Expr {
	record := lower_expr(e.record, env)

	type_var := fresh_value_var(env.store, e.span)
	access := new(IR_Field_Access)
	access^ = IR_Field_Access{
		record = record,
		field = e.field,
		field_index = 0,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(access)
}

lower_record_update :: proc(e: ^CExpr_Record_Update, env: ^Lower_Env) -> IR_Expr {
	rest := lower_expr(e.rest, env)

	fields := make([dynamic]IR_Record_Field, 0, len(e.updates))
	for u in e.updates {
		append(&fields, IR_Record_Field{name = u.name, value = lower_expr(u.value, env)})
	}

	type_var := fresh_value_var(env.store, e.span)
	rec := new(IR_Construct_Record)
	rec^ = IR_Construct_Record{
		fields = fields,
		rest = rest,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(rec)
}

lower_interpolate :: proc(e: ^CExpr_Interpolate, env: ^Lower_Env) -> IR_Expr {
	if len(e.parts) == 0 {
		str_type := lower_type(env.store, make_primitive_type(env.store, intern(env.interner, "Str"), e.span))
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = "", type = str_type, span = e.span}
		return IR_Expr(lit)
	}

	result := lower_expr(e.parts[0], env)
	for i := 1; i < len(e.parts); i += 1 {
		right := lower_expr(e.parts[i], env)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp{
			op = .Plus,
			left = result,
			right = right,
			type = IR_Type{.I32, Type_Var_ID(-1)},
			span = e.span,
		}
		result = IR_Expr(binop)
	}
	return result
}

lower_handle :: proc(e: ^CExpr_Handle, env: ^Lower_Env) -> IR_Expr {
	body := lower_expr(e.body, env)

	arms := make([dynamic]IR_Handler_Arm, 0, len(e.arms))
	for arm in e.arms {
		append(&arms, IR_Handler_Arm{
			op = arm.op,
			params = arm.params,
			body = lower_expr(arm.body, env),
		})
	}

	type_var := fresh_value_var(env.store, e.span)
	h := new(IR_Handle)
	h^ = IR_Handle{
		effect = e.effect,
		is_shallow = e.is_shallow,
		body = body,
		arms = arms,
		type = lower_type(env.store, type_var),
		span = e.span,
	}
	return IR_Expr(h)
}

lower_list :: proc(e: ^CExpr_List, env: ^Lower_Env) -> IR_Expr {
	type_var := fresh_value_var(env.store, e.span)
	ir_type := lower_type(env.store, type_var)

	nil_tag := new(IR_Construct_Tag)
	nil_tag^ = IR_Construct_Tag{
		tag_name = intern(env.interner, "Nil"),
		tag_index = 0,
		payload = make([dynamic]IR_Expr, 0),
		type = ir_type,
		span = e.span,
	}

	result: IR_Expr = IR_Expr(nil_tag)
	for i := len(e.elements) - 1; i >= 0; i -= 1 {
		elem := lower_expr(e.elements[i], env)
		cons_payload := make([dynamic]IR_Expr, 0, 2)
		append(&cons_payload, elem)
		append(&cons_payload, result)
		cons_tag := new(IR_Construct_Tag)
		cons_tag^ = IR_Construct_Tag{
			tag_name = intern(env.interner, "Cons"),
			tag_index = 0,
			payload = cons_payload,
			type = ir_type,
			span = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}

package ir

import "camp:base"
import "camp:semantics"
import "core:fmt"
import "core:strings"

lower_tfile :: proc(tfile: semantics.TFile, store: ^semantics.Type_Store) -> IR_Module {
	mod: IR_Module
	mod.decls = make([dynamic]IR_Decl, 0, len(tfile.decls))
	mod.effect_defs = make([dynamic]IR_Effect_Def, 0, 8)
	mod.string_table = make([dynamic]String_Table_Entry, 0, 16)

	env: Lower_Env = {module = &mod, store = store, interner = store.interner}
	env.pending_decls = make([dynamic]IR_Decl, 0, 8)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^semantics.TDecl_Effect:
			eff_def := lower_teffect_def(&d^, &env)
			append(&mod.effect_defs, eff_def)
		case ^semantics.TDecl_Const, ^semantics.TDecl_Trait, ^semantics.TDecl_Alias, ^semantics.TDecl_Newtype, ^semantics.TDecl_Import, ^semantics.TDecl_Test, ^semantics.TDecl_Expect, ^semantics.TDecl_Is_Impl:
		}
	}

	inject_prelude_effect_defs(&mod, store)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^semantics.TDecl_Const:
			ir_decl := lower_tdecl_const(&d^, &env)
			append(&mod.decls, ir_decl)
		case ^semantics.TDecl_Effect:
			ir_decl := lower_tdecl_effect(&d^, &env)
			append(&mod.decls, ir_decl)
		case ^semantics.TDecl_Trait:
		case ^semantics.TDecl_Alias:
		case ^semantics.TDecl_Newtype:
		// Newtypes are erased at runtime — no IR decl needed.
		case ^semantics.TDecl_Import:
		case ^semantics.TDecl_Test:
		case ^semantics.TDecl_Expect:
		case ^semantics.TDecl_Is_Impl:
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
	store:         ^semantics.Type_Store,
	interner:      ^base.Intern_Table,
	fresh_counter: int,
	pending_decls: [dynamic]IR_Decl,
}

fresh_ir_name :: proc(env: ^Lower_Env) -> base.Intern_ID {
	name := fmt.tprintf("_ir_{}", env.fresh_counter)
	env.fresh_counter += 1
	return base.intern(env.interner, name)
}

extract_effects :: proc(store: ^semantics.Type_Store, effect_row_var: base.Type_Var_ID, effect_defs: []IR_Effect_Def) -> [dynamic]base.Canonical_Name {
	effects: [dynamic]base.Canonical_Name
	effects = make([dynamic]base.Canonical_Name, 0, 4)
	collect_effects_from_row(store, effect_row_var, effect_defs, &effects)
	return effects
}

extract_effects_from_fn_binding :: proc(store: ^semantics.Type_Store, fn_name: base.Canonical_Name, effect_defs: []IR_Effect_Def) -> [dynamic]base.Canonical_Name {
	if fn_name.module != base.NO_NAME {
		return make([dynamic]base.Canonical_Name, 0)
	}
	binding_var, ok := store.bindings[fn_name.name]
	if !ok {
		return make([dynamic]base.Canonical_Name, 0)
	}
	resolved := semantics.resolve_var(store, binding_var)
	v := &store.vars[int(resolved)]
	it, it_ok := v.link.(semantics.Inferred_Type)
	inf, is_inf := it.(semantics.Inferred_Function)
	if !is_inf || !it_ok {
		return make([dynamic]base.Canonical_Name, 0)
	}
	result := extract_effects(store, inf.effect_id, effect_defs)
	return result
}

collect_effects_from_row :: proc(store: ^semantics.Type_Store, effect_var: base.Type_Var_ID, effect_defs: []IR_Effect_Def, result: ^[dynamic]base.Canonical_Name) {
	resolved := semantics.resolve_var(store, effect_var)
	v := &store.vars[int(resolved)]

	it, ok := v.link.(semantics.Inferred_Type)
	inf, is_inf := it.(semantics.Inferred_Effect_Row)
	if !is_inf || !ok {
		return
	}

	for entry in inf.effects {
		canonical := base.Canonical_Name{module = base.NO_NAME, name = entry.name}
		already := false
		for existing in result {
			if existing.module == canonical.module && existing.name == canonical.name {
				already = true
				break
			}
		}
		if !already {
			append(result, canonical)
		}
	}

	rest_resolved := semantics.resolve_var(store, inf.rest_id)
	rest_v := &store.vars[int(rest_resolved)]
	rit, rok := rest_v.link.(semantics.Inferred_Type)
	_, rest_is_inf := rit.(semantics.Inferred_Effect_Row)
	if rest_is_inf && rok {
		collect_effects_from_row(store, inf.rest_id, effect_defs, result)
	}
}

make_ir_lit_int :: proc(value: i64, type_: base.IR_Type, span: base.Source_Span) -> IR_Expr {
	lit := new(IR_Literal_Int)
	lit^ = IR_Literal_Int{value = value, type = type_, span = span}
	return IR_Expr(lit)
}

make_ir_lit_bool :: proc(value: bool, type_: base.IR_Type, span: base.Source_Span) -> IR_Expr {
	lit := new(IR_Literal_Bool)
	lit^ = IR_Literal_Bool{value = value, type = type_, span = span}
	return IR_Expr(lit)
}


lower_texpr :: proc(expr: semantics.TExpr, env: ^Lower_Env) -> IR_Expr {
	switch e in expr {
	case ^semantics.TExpr_Int:
		type_var := semantics.make_primitive_type(env.store, base.intern(env.interner, "I64"), e.span)
		return make_ir_lit_int(e.value, semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Float:
		type_var := semantics.make_primitive_type(env.store, base.intern(env.interner, "F64"), e.span)
		lit := new(IR_Literal_Float)
		lit^ = IR_Literal_Float{value = e.value, type = e.type_, span = e.span}
		return IR_Expr(lit)

	case ^semantics.TExpr_String:
		type_var := semantics.make_primitive_type(env.store, base.intern(env.interner, "Str"), e.span)
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = e.value, type = e.type_, span = e.span}
		append(&env.module.string_table, String_Table_Entry{id = fresh_ir_name(env), value = e.value})
		return IR_Expr(lit)

	case ^semantics.TExpr_Bool:
		type_var := semantics.make_primitive_type(env.store, base.intern(env.interner, "Bool"), e.span)
		return make_ir_lit_bool(e.value, semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Char:
		type_var := semantics.make_primitive_type(env.store, base.intern(env.interner, "I64"), e.span)
		return make_ir_lit_int(i64(e.value), semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Todo:
		msg: IR_Expr
		if e.message != nil {
			msg = lower_texpr(e.message, env)
		} else {
			lit := new(IR_Literal_String)
			lit^ = IR_Literal_String{value = "todo: not implemented", type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}, span = e.span}
			msg = IR_Expr(lit)
		}
		crash := new(IR_Crash)
		crash^ = IR_Crash{message = msg, span = e.span}
		return IR_Expr(crash)

	case ^semantics.TExpr_Name:
		v := new(IR_Var)
		v^ = IR_Var{name = e.name.name, type = e.type_, span = e.span}
		return IR_Expr(v)

	case ^semantics.TExpr_Call:
		return lower_tcall(e, env)

	case ^semantics.TExpr_Method_Call:
		return lower_tmethod_call(e, env)

	case ^semantics.TExpr_Lambda:
		return lower_tlambda(e, env)

	case ^semantics.TExpr_Block:
		return lower_tblock(e, env)

	case ^semantics.TExpr_If:
		return lower_tif(e, env)

	case ^semantics.TExpr_Match:
		return lower_tmatch(e, env)

	case ^semantics.TExpr_BinOp:
		return lower_tbinop(e, env)

	case ^semantics.TExpr_PrefixOp:
		return lower_tprefixop(e, env)

	case ^semantics.TExpr_Tag:
		return lower_ttag(e, env)

	case ^semantics.TExpr_Nominal_Construct:
		payload := make([dynamic]IR_Expr, 0, len(e.payload))
		for p in e.payload {
			append(&payload, lower_texpr(p, env))
		}
		ir := new(IR_Expr_Nominal_Construct)
		ir^ = IR_Expr_Nominal_Construct{
			type_name = e.type_name,
			variant   = e.variant,
			payload   = payload,
			span      = e.span,
		}
		return ir

	case ^semantics.TExpr_Record:
		return lower_trecord(e, env)

	case ^semantics.TExpr_Field_Access:
		return lower_tfield_access(e, env)

	case ^semantics.TExpr_Record_Update:
		return lower_trecord_update(e, env)

	case ^semantics.TExpr_Assign:
		#partial switch target in e.target {
		case ^semantics.TExpr_Name:
			value := lower_texpr(e.value, env)
			assign := new(IR_Assign)
			assign^ = IR_Assign{
				binding = target.name.name,
				value   = value,
				type    = e.type_,
				span    = e.span,
			}
			return IR_Expr(assign)
		case ^semantics.TExpr_Int, ^semantics.TExpr_Float, ^semantics.TExpr_String, ^semantics.TExpr_Bool, ^semantics.TExpr_Tag, ^semantics.TExpr_Nominal_Construct, ^semantics.TExpr_Record, ^semantics.TExpr_List, ^semantics.TExpr_Call, ^semantics.TExpr_Method_Call, ^semantics.TExpr_Lambda, ^semantics.TExpr_Block, ^semantics.TExpr_If, ^semantics.TExpr_Match, ^semantics.TExpr_BinOp, ^semantics.TExpr_PrefixOp, ^semantics.TExpr_Field_Access, ^semantics.TExpr_Record_Update, ^semantics.TExpr_Return, ^semantics.TExpr_Crash, ^semantics.TExpr_Interpolated_String, ^semantics.TExpr_Handle, ^semantics.TExpr_Perform, ^semantics.TExpr_For, ^semantics.TExpr_Par:
			return lower_texpr(e.value, env)
		}

	case ^semantics.TExpr_Return:
		inner := lower_texpr(e.value, env)
		ret := new(IR_Return)
		ret^ = IR_Return{value = inner, span = e.span}
		return IR_Expr(ret)

	case ^semantics.TExpr_Crash:
		msg_expr := lower_texpr(e.message, env)
		crash := new(IR_Crash)
		crash^ = IR_Crash{message = msg_expr, span = e.span}
		return IR_Expr(crash)

	case ^semantics.TExpr_Interpolated_String:
		return lower_tinterpolated_string(e, env)

	case ^semantics.TExpr_Handle:
		return lower_thandle(e, env)

	case ^semantics.TExpr_List:
		return lower_tlist(e, env)

	case ^semantics.TExpr_Perform:
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

	case ^semantics.TExpr_For:
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

	case ^semantics.TExpr_Par:
		if e.for_var != 0 {
			iterable := lower_texpr(e.for_iter, env)
			body := lower_texpr(e.for_body, env)
			loop := new(IR_Loop)
			loop^ = IR_Loop{
				var      = e.for_var,
				iterable = iterable,
				body     = body,
				type     = e.type_,
				span     = e.span,
			}
			return IR_Expr(loop)
		}

		// Named par { name: expr, ... } — lower to IR_Construct_Record
		if len(e.names) > 0 {
			fields := make([dynamic]IR_Record_Field, 0, len(e.names))
			for idx in 0..<len(e.names) {
				append(&fields, IR_Record_Field{
					name  = e.names[idx],
					value = lower_texpr(e.expressions[idx], env),
				})
			}
			record := new(IR_Construct_Record)
			record^ = IR_Construct_Record{
				fields     = fields,
				rest       = nil,
				reuse_addr = NO_REUSE_ADDR,
				type       = e.type_,
				span       = e.span,
			}
			return IR_Expr(record)
		}

		// Unnamed par (legacy) — lower as block
		stmts := make([dynamic]IR_Expr, 0, len(e.expressions))
		for expr in e.expressions {
			append(&stmts, lower_texpr(expr, env))
		}
		block := new(IR_Block)
		block^ = IR_Block{
			statements = stmts,
			type        = e.type_,
			span        = e.span,
		}
		return IR_Expr(block)
	}

	return make_ir_lit_int(0, base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(-1)}, base.Source_Span_ZERO)
}

lower_tdecl_const :: proc(d: ^semantics.TDecl_Const, env: ^Lower_Env) -> IR_Decl {
	#partial switch body_expr in d.body {
	case ^semantics.TExpr_Lambda:
		return lower_tlambda_as_decl(body_expr, d.name, d.is_effectful, d.span, env)
	case ^semantics.TExpr_Int, ^semantics.TExpr_Float, ^semantics.TExpr_String, ^semantics.TExpr_Bool, ^semantics.TExpr_Tag, ^semantics.TExpr_Nominal_Construct, ^semantics.TExpr_Record, ^semantics.TExpr_List, ^semantics.TExpr_Name, ^semantics.TExpr_Call, ^semantics.TExpr_Method_Call, ^semantics.TExpr_Block, ^semantics.TExpr_If, ^semantics.TExpr_Match, ^semantics.TExpr_BinOp, ^semantics.TExpr_PrefixOp, ^semantics.TExpr_Field_Access, ^semantics.TExpr_Record_Update, ^semantics.TExpr_Assign, ^semantics.TExpr_Return, ^semantics.TExpr_Crash, ^semantics.TExpr_Interpolated_String, ^semantics.TExpr_Handle, ^semantics.TExpr_Perform, ^semantics.TExpr_For, ^semantics.TExpr_Par:
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

lower_tlambda_as_decl :: proc(e: ^semantics.TExpr_Lambda, name: base.Canonical_Name, is_effectful: bool, span: base.Source_Span, env: ^Lower_Env) -> IR_Decl {
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

	// `!` suffix sets is_effectful syntactically, but every downstream pass
	// (effect_lower, closure_convert, cps, codegen) treats this flag as
	// "performs at least one effect" — evidence params, CPS continuation,
	// default handlers. Normalize here so the whole pipeline sees a
	// consistent view; otherwise `main! = || { 42 }` is half-effectful and
	// produces invalid WASM.
	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = name,
		is_effectful = is_effectful && len(effects) > 0,
		params = params,
		return_type = e.return_type,
		effect_row = e.effects,
		effects = effects,
		body = body,
		span = span,
	}
	return IR_Decl(fn_decl)
}

lower_tdecl_effect :: proc(d: ^semantics.TDecl_Effect, env: ^Lower_Env) -> IR_Decl {
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

lower_teffect_def :: proc(d: ^semantics.TDecl_Effect, env: ^Lower_Env) -> IR_Effect_Def {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_teffect_op(op, env)
		append(&ops, ir_op)
	}
	type_params := make([dynamic]base.Intern_ID, 0, len(d.type_params))
	for tp in d.type_params {
		append(&type_params, tp.name)
	}
	return IR_Effect_Def{name = d.name, operations = ops, type_params = type_params}
}

lower_teffect_op :: proc(op: semantics.TEffect_Op, env: ^Lower_Env) -> IR_Effect_Op {
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

inject_prelude_effect_defs :: proc(mod: ^IR_Module, store: ^semantics.Type_Store) {
	inject_prelude_effects_lower(mod, store)
}

lower_tcall :: proc(e: ^semantics.TExpr_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch c in e.callee {
	case ^semantics.TExpr_Name:
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

	case ^semantics.TExpr_Int, ^semantics.TExpr_Float, ^semantics.TExpr_String, ^semantics.TExpr_Bool, ^semantics.TExpr_Tag, ^semantics.TExpr_Nominal_Construct, ^semantics.TExpr_Record, ^semantics.TExpr_List, ^semantics.TExpr_Call, ^semantics.TExpr_Method_Call, ^semantics.TExpr_Lambda, ^semantics.TExpr_Block, ^semantics.TExpr_If, ^semantics.TExpr_Match, ^semantics.TExpr_BinOp, ^semantics.TExpr_PrefixOp, ^semantics.TExpr_Field_Access, ^semantics.TExpr_Record_Update, ^semantics.TExpr_Assign, ^semantics.TExpr_Return, ^semantics.TExpr_Crash, ^semantics.TExpr_Interpolated_String, ^semantics.TExpr_Handle, ^semantics.TExpr_Perform, ^semantics.TExpr_For, ^semantics.TExpr_Par:
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
	return IR_Expr(nil)
}

lower_tmethod_call :: proc(e: ^semantics.TExpr_Method_Call, env: ^Lower_Env) -> IR_Expr {
	receiver_ir := lower_texpr(e.receiver, env)

	// Check if this is an effect operation call
	receiver_effect_name: base.Intern_ID = base.NO_NAME
	receiver_effect_canonical: base.Canonical_Name
	#partial switch r in e.receiver {
	case ^semantics.TExpr_Name:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case ^semantics.TExpr_Tag:
		receiver_effect_name = r.name.name
		receiver_effect_canonical = r.name
	case ^semantics.TExpr_Int, ^semantics.TExpr_Float, ^semantics.TExpr_String, ^semantics.TExpr_Bool, ^semantics.TExpr_Nominal_Construct, ^semantics.TExpr_Record, ^semantics.TExpr_List, ^semantics.TExpr_Call, ^semantics.TExpr_Method_Call, ^semantics.TExpr_Lambda, ^semantics.TExpr_Block, ^semantics.TExpr_If, ^semantics.TExpr_Match, ^semantics.TExpr_BinOp, ^semantics.TExpr_PrefixOp, ^semantics.TExpr_Field_Access, ^semantics.TExpr_Record_Update, ^semantics.TExpr_Assign, ^semantics.TExpr_Return, ^semantics.TExpr_Crash, ^semantics.TExpr_Interpolated_String, ^semantics.TExpr_Handle, ^semantics.TExpr_Perform, ^semantics.TExpr_For, ^semantics.TExpr_Par:
	}

	if receiver_effect_name != base.NO_NAME && semantics.is_declared_effect(env.store, receiver_effect_name) {
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
						resolved_type := semantics.lower_type(env.store, op_def.return_type.type_id)
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
	method_str := base.intern_get(env.interner, e.method.name)
	receiver_type_var: base.Type_Var_ID = 0
	#partial switch r in e.receiver {
	case ^semantics.TExpr_Name:
		receiver_type_var = r.type_.type_id
	case ^semantics.TExpr_String:
		receiver_type_var = r.type_.type_id
	case ^semantics.TExpr_Method_Call:
		receiver_type_var = r.type_.type_id
	case ^semantics.TExpr_Field_Access:
		receiver_type_var = r.type_.type_id
	case ^semantics.TExpr_Call:
		receiver_type_var = r.type_.type_id
	case ^semantics.TExpr_Int, ^semantics.TExpr_Float, ^semantics.TExpr_Bool, ^semantics.TExpr_Tag, ^semantics.TExpr_Nominal_Construct, ^semantics.TExpr_Record, ^semantics.TExpr_List, ^semantics.TExpr_Lambda, ^semantics.TExpr_Block, ^semantics.TExpr_If, ^semantics.TExpr_Match, ^semantics.TExpr_BinOp, ^semantics.TExpr_PrefixOp, ^semantics.TExpr_Record_Update, ^semantics.TExpr_Assign, ^semantics.TExpr_Return, ^semantics.TExpr_Crash, ^semantics.TExpr_Interpolated_String, ^semantics.TExpr_Handle, ^semantics.TExpr_Perform, ^semantics.TExpr_For, ^semantics.TExpr_Par:
	}

	if receiver_type_var != 0 {
		resolved_type := semantics.resolve_var(env.store, receiver_type_var)
		v := &env.store.vars[int(resolved_type)]
		if it, ok := v.link.(semantics.Inferred_Type); ok {
			prim, prim_ok := it.(semantics.Inferred_Primitive)
			if prim_ok {
				type_name_str := base.intern_get(env.interner, prim.primitive_name)
				if type_name_str == "Str" {
					if method_str == "len" && len(e.args) == 0 {
						str_name := base.intern(env.interner, "Str")
						len_name := base.intern(env.interner, "length")
						args := make([dynamic]IR_Expr, 0, 1)
						append(&args, receiver_ir)
						call := new(IR_Call)
						call^ = IR_Call{
							callee = base.Canonical_Name{module = str_name, name = len_name},
							args = args,
							type = e.type_,
							span = e.span,
						}
						return IR_Expr(call)
					}
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

lower_tlambda :: proc(e: ^semantics.TExpr_Lambda, env: ^Lower_Env) -> IR_Expr {
	name := base.Canonical_Name{
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
		return_type = e.return_type,
		span = e.span,
	}
	return IR_Expr(closure)
}

lower_tblock :: proc(e: ^semantics.TExpr_Block, env: ^Lower_Env) -> IR_Expr {
	if len(e.statements) == 0 {
		return make_ir_lit_int(0, e.type_, e.span)
	}
	if len(e.statements) == 1 {
		return lower_texpr(e.statements[0], env)
	}
	stmts := make([dynamic]IR_Expr, 0, len(e.statements))
	for stmt in e.statements {
		append(&stmts, lower_texpr(stmt, env))
	}
	block := new(IR_Block)
	block^ = IR_Block{statements = stmts, type = e.type_, span = e.span}
	return IR_Expr(block)
}

lower_tif :: proc(e: ^semantics.TExpr_If, env: ^Lower_Env) -> IR_Expr {
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

texpr_type_id :: proc(e: semantics.TExpr) -> base.Type_Var_ID {
	if e == nil do return base.Type_Var_ID(0)
	#partial switch expr in e {
	case ^semantics.TExpr_Int: return expr.type_.type_id
	case ^semantics.TExpr_Float: return expr.type_.type_id
	case ^semantics.TExpr_String: return expr.type_.type_id
	case ^semantics.TExpr_Bool: return expr.type_.type_id
	case ^semantics.TExpr_Char: return expr.type_.type_id
	case ^semantics.TExpr_Todo: return expr.type_.type_id
	case ^semantics.TExpr_Tag: return expr.type_.type_id
	case ^semantics.TExpr_Nominal_Construct: return expr.resolved_type
	case ^semantics.TExpr_Record: return expr.type_.type_id
	case ^semantics.TExpr_List: return expr.type_.type_id
	case ^semantics.TExpr_Name: return expr.type_.type_id
	case ^semantics.TExpr_Call: return expr.type_.type_id
	case ^semantics.TExpr_Method_Call: return expr.type_.type_id
	case ^semantics.TExpr_Lambda: return expr.type_.type_id
	case ^semantics.TExpr_Block: return expr.type_.type_id
	case ^semantics.TExpr_If: return expr.type_.type_id
	case ^semantics.TExpr_Match: return expr.type_.type_id
	case ^semantics.TExpr_BinOp: return expr.type_.type_id
	case ^semantics.TExpr_PrefixOp: return expr.type_.type_id
	case ^semantics.TExpr_Field_Access: return expr.type_.type_id
	case ^semantics.TExpr_Record_Update: return expr.type_.type_id
	case ^semantics.TExpr_Assign: return expr.type_.type_id
	case ^semantics.TExpr_Return: return expr.type_.type_id
	case ^semantics.TExpr_Crash: return expr.type_.type_id
	case ^semantics.TExpr_Interpolated_String: return expr.type_.type_id
	case ^semantics.TExpr_Handle: return expr.type_.type_id
	case ^semantics.TExpr_Perform: return expr.type_.type_id
	case ^semantics.TExpr_For: return expr.type_.type_id
	case ^semantics.TExpr_Par: return expr.type_.type_id
	}
	return base.Type_Var_ID(0)
}

resolve_tag_payload_wasm_types :: proc(store: ^semantics.Type_Store, scrutinee_type_id: base.Type_Var_ID, tag_name: base.Intern_ID) -> []base.IR_Wasm_Type {
	if scrutinee_type_id == base.Type_Var_ID(0) {
		return nil
	}
	resolved := semantics.resolve_var(store, scrutinee_type_id)
	v := store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf {
		return nil
	}
	#partial switch vi in inf {
	case semantics.Inferred_Newtype:
		return resolve_tag_payload_wasm_types(store, vi.inner_id, tag_name)
	case semantics.Inferred_Tag_Union_Row:
		for entry in vi.tag_entries {
			if entry.name == tag_name {
				types := make([]base.IR_Wasm_Type, len(entry.payload))
				for i in 0..<len(entry.payload) {
					types[i] = semantics.lower_type(store, entry.payload[i]).wasm_type
				}
				return types
			}
		}
	}
	return nil
}

lower_tmatch :: proc(e: ^semantics.TExpr_Match, env: ^Lower_Env) -> IR_Expr {
	scrut_ir := lower_texpr(e.scrutinee, env)
	scrutinee_type_id := texpr_type_id(e.scrutinee)
	arms := make([dynamic]IR_Match_Arm, len(e.arms))
	for i in 0..<len(e.arms) {
		arms[i] = IR_Match_Arm{
			pattern = lower_tpattern(e.arms[i].pattern, env, scrutinee_type_id),
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

lower_tpattern :: proc(pattern: semantics.TPattern, env: ^Lower_Env, scrutinee_type_id: base.Type_Var_ID = base.Type_Var_ID(0)) -> IR_Pattern {
	switch p in pattern {
	case ^semantics.TPattern_Tag:
		payload_ids := make([dynamic]base.Intern_ID, 0, len(p.payload))
		for sub in p.payload {
			#partial switch s in sub {
			case ^semantics.TPattern_Identifier:
				append(&payload_ids, s.name)
			case ^semantics.TPattern_Tag, ^semantics.TPattern_Record, ^semantics.TPattern_List, ^semantics.TPattern_Int, ^semantics.TPattern_String, ^semantics.TPattern_Bool, ^semantics.TPattern_Wildcard, ^semantics.TPattern_Destructure, ^semantics.TPattern_Or:
				append(&payload_ids, base.Intern_ID(0))
			}
		}
		result := new(IR_Pat_Tag)
		result.name = p.name.name
		result.payload = payload_ids
		result.payload_wasm_types = resolve_tag_payload_wasm_types(env.store, scrutinee_type_id, p.name.name)
		return IR_Pattern(result)

	case ^semantics.TPattern_Record:
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

	case ^semantics.TPattern_List:
		// Determine the tail variable: rest pattern or fresh name
		tail_var: base.Intern_ID
		has_rest := p.rest != nil
		if has_rest {
			rest_pat := lower_tpattern(p.rest, env)
			if rv, ok := rest_pat.(^IR_Pat_Var); ok {
				tail_var = rv.name
			} else {
				// Wildcard or non-variable rest: use anonymous variable
				tail_var = fresh_ir_name(env)
			}
		} else {
			tail_var = fresh_ir_name(env)
		}

		// Handle [..rest] (pure rest, no elements)
		if len(p.elements) == 0 && has_rest {
			rest_pat := lower_tpattern(p.rest, env)
			return rest_pat
		}

		// Build elements from right to left, wrapping Cons around the tail
		list_var := tail_var
		pat: IR_Pattern
		for i := len(p.elements) - 1; i >= 0; i -= 1 {
			elem_pat := lower_tpattern(p.elements[i], env)
			if elem_pat != nil {
				if elem_var, ok := elem_pat.(^IR_Pat_Var); ok {
					prev_cons := new(IR_Pat_Tag)
					prev_cons.name = base.intern(env.interner, "Cons")
					prev_cons.payload = make([dynamic]base.Intern_ID, 0)
					append(&prev_cons.payload, elem_var.name)
					append(&prev_cons.payload, list_var)
					prev_cons.payload_wasm_types = []base.IR_Wasm_Type{.I32, .I32}
					list_var = elem_var.name
					pat = IR_Pattern(prev_cons)
				}
			}
		}
		return pat

	case ^semantics.TPattern_Bool:
		result := new(IR_Pat_Bool)
		result.value = p.value
		return IR_Pattern(result)

	case ^semantics.TPattern_Int:
		result := new(IR_Pat_Int)
		result.value = p.value
		return IR_Pattern(result)

	case ^semantics.TPattern_String:
		string_id := fresh_ir_name(env)
		append(&env.module.string_table, String_Table_Entry{id = string_id, value = p.value})
		result := new(IR_Pat_String)
		result.string_id = string_id
		return IR_Pattern(result)

	case ^semantics.TPattern_Char:
		result := new(IR_Pat_Int)
		result.value = i64(p.value)
		return IR_Pattern(result)

	case ^semantics.TPattern_Identifier:
		// Treat `_` as a wildcard: it shouldn't reserve a local or emit a
		// binding store. The parser produces Pattern_Identifier for any
		// lowercase name including `_`, so the wildcard distinction has to
		// happen here.
		if base.intern_get(env.interner, p.name) == "_" {
			result := new(IR_Pat_Wildcard)
			return IR_Pattern(result)
		}
		result := new(IR_Pat_Var)
		result.name = p.name
		return IR_Pattern(result)

	case ^semantics.TPattern_Wildcard:
		result := new(IR_Pat_Wildcard)
		return IR_Pattern(result)

	case ^semantics.TPattern_Destructure:
		result := new(IR_Pat_Var)
		result.name = base.Intern_ID(0)
		return IR_Pattern(result)

	case ^semantics.TPattern_Or:
		// For now, just lower the first alternative
		// Full or-pattern support requires IR patching
		if len(p.alternatives) > 0 {
			return lower_tpattern(p.alternatives[0], env)
		}
		return IR_Pattern(nil)
	}
	return IR_Pattern(nil)
}

lower_binop_kind :: proc(op: base.Token_Kind) -> IR_BinOp_Kind {
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

lower_tbinop :: proc(e: ^semantics.TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	// String concatenation: convert `a + b` (when both operands are Str) to Str.concat(a, b)
	if e.op == .Plus {
		resolved := semantics.resolve_var(env.store, e.type_.type_id)
		v := &env.store.vars[int(resolved)]
		if it, ok := v.link.(semantics.Inferred_Type); ok {
			prim, prim_ok := it.(semantics.Inferred_Primitive)
			if prim_ok {
				name_str := base.intern_get(env.interner, prim.primitive_name)
				if name_str == "Str" {
					left_ir := lower_texpr(e.left, env)
					right_ir := lower_texpr(e.right, env)
					args := make([dynamic]IR_Expr, 0, 2)
					append(&args, left_ir)
					append(&args, right_ir)
					call := new(IR_Call)
					str_name := base.intern(env.interner, "Str")
					concat_name := base.intern(env.interner, "concat")
					call^ = IR_Call{
						callee = base.Canonical_Name{module = str_name, name = concat_name},
						args = args,
						type = e.type_,
						span = e.span,
					}
					return IR_Expr(call)
				}
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

lower_tprefixop :: proc(e: ^semantics.TExpr_PrefixOp, env: ^Lower_Env) -> IR_Expr {
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
	case .Int_Literal, .Float_Literal, .String_Literal, .Interpolated_String_Literal, .Identifier, .Upper_Id, .Kw_If, .Kw_Else, .Kw_Match, .Kw_Is, .Kw_Derives, .Kw_Handle, .Kw_In, .Kw_With, .Kw_Import, .Kw_As, .Kw_For, .Kw_And, .Kw_Or, .Kw_Expect, .Kw_Test, .Kw_Pub, .Kw_Self, .Kw_Par, .Kw_Where, .Pipe, .Arrow, .Fat_Arrow, .Eq, .Colon_Eq, .Colon, .Comma, .Dot, .Dot_Dot, .Dollar, .Hash, .At, .Lt, .Gt, .Lt_Eq, .Gt_Eq, .Eq_Eq, .Bang_Eq, .Plus, .Star, .Slash, .Percent, .Amp, .Caret, .Tilde, .Backslash, .LParen, .RParen, .LBrack, .RBrack, .LBrace, .RBrace, .Newline, .Eof:
		return operand_ir
	}
	return operand_ir
}

resolve_tag_index :: proc(store: ^semantics.Type_Store, type_var: base.Type_Var_ID, tag_name: base.Intern_ID) -> int {
	resolved := semantics.resolve_var(store, type_var)
	v := store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf {
		return 0
	}
	#partial switch vi in inf {
	case semantics.Inferred_Newtype:
		return resolve_tag_index(store, vi.inner_id, tag_name)
	case semantics.Inferred_Tag_Union_Row:
		for entry, i in vi.tag_entries {
			if entry.name == tag_name {
				return i
			}
		}
	}
	return 0
}

lower_ttag :: proc(e: ^semantics.TExpr_Tag, env: ^Lower_Env) -> IR_Expr {
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
		reuse_addr = NO_REUSE_ADDR,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_trecord :: proc(e: ^semantics.TExpr_Record, env: ^Lower_Env) -> IR_Expr {
	fields := make([dynamic]IR_Record_Field, 0, len(e.fields))
	for f in e.fields {
		append(&fields, IR_Record_Field{name = f.name, value = lower_texpr(f.value, env)})
	}
	rest := lower_texpr(e.rest, env)
	result := new(IR_Construct_Record)
	result^ = IR_Construct_Record{
		fields = fields,
		rest = rest,
		reuse_addr = NO_REUSE_ADDR,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tfield_access :: proc(e: ^semantics.TExpr_Field_Access, env: ^Lower_Env) -> IR_Expr {
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

lower_trecord_update :: proc(e: ^semantics.TExpr_Record_Update, env: ^Lower_Env) -> IR_Expr {
	rest_ir := lower_texpr(e.rest, env)
	fields := make([dynamic]IR_Record_Field, 0, len(e.updates))
	for f in e.updates {
		append(&fields, IR_Record_Field{name = f.name, value = lower_texpr(f.value, env)})
	}
	result := new(IR_Construct_Record)
	result^ = IR_Construct_Record{
		fields = fields,
		rest = rest_ir,
		reuse_addr = NO_REUSE_ADDR,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tinterpolated_string :: proc(e: ^semantics.TExpr_Interpolated_String, env: ^Lower_Env) -> IR_Expr {
	if len(e.parts) == 0 {
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String{value = "", type = e.type_, span = e.span}
		return IR_Expr(lit)
	}

	str_name_id := base.intern(env.interner, "Str")
	concat_name := base.intern(env.interner, "concat")

	lower_part :: proc(part: semantics.TExpr_String_Part, env: ^Lower_Env, str_type: base.IR_Type, span: base.Source_Span) -> IR_Expr {
		switch p in part {
		case ^semantics.TExpr_String_Literal:
			lit := new(IR_Literal_String)
			lit^ = IR_Literal_String{value = p.value, type = p.type_, span = p.span}
			append(&env.module.string_table, String_Table_Entry{id = fresh_ir_name(env), value = p.value})
			return IR_Expr(lit)
		case ^semantics.TExpr_String_Expr:
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
		return make_ir_lit_int(0, base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(-1)}, base.Source_Span_ZERO)
	}

	result := lower_part(e.parts[0], env, e.type_, e.span)
	for i := 1; i < len(e.parts); i += 1 {
		right := lower_part(e.parts[i], env, e.type_, e.span)
		args := make([dynamic]IR_Expr, 0, 2)
		append(&args, result)
		append(&args, right)
		call := new(IR_Call)
		call^ = IR_Call{
			callee = base.Canonical_Name{module = str_name_id, name = concat_name},
			args = args,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(call)
	}
	return result
}

lower_thandle :: proc(e: ^semantics.TExpr_Handle, env: ^Lower_Env) -> IR_Expr {
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
		effects = e.effects,
		body = body_ir,
		arms = arms,
		type = e.type_,
		span = e.span,
	}
	return IR_Expr(result)
}

lower_tlist :: proc(e: ^semantics.TExpr_List, env: ^Lower_Env) -> IR_Expr {
	nil_name := base.intern(env.interner, "Nil")
	cons_name := base.intern(env.interner, "Cons")
	nil_index := resolve_tag_index(env.store, e.type_.type_id, nil_name)
	cons_index := resolve_tag_index(env.store, e.type_.type_id, cons_name)

	result: IR_Expr
	if e.rest != nil {
		result = lower_texpr(e.rest, env)
	} else {
		nil_tag := new(IR_Construct_Tag)
		nil_tag^ = IR_Construct_Tag{
			tag_name = nil_name,
			tag_index = nil_index,
			payload = make([dynamic]IR_Expr, 0),
			reuse_addr = NO_REUSE_ADDR,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(nil_tag)
	}

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
			reuse_addr = NO_REUSE_ADDR,
			type = e.type_,
			span = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}



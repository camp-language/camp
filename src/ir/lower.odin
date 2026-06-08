package ir

import "camp:base"
import "camp:semantics"
import "core:fmt"
import "core:strings"

// lower_string_content strips the surrounding double quotes from a string
// literal's source text and resolves escape sequences, producing the raw byte
// content that lives in the module's string table at runtime.
lower_string_content :: proc(raw: string) -> string {
	if len(raw) < 2 {
		return raw
	}
	inner := raw[1:len(raw) - 1]
	if strings.index_byte(inner, '\\') < 0 {
		return inner
	}
	b: strings.Builder
	strings.builder_init(&b)
	i := 0
	for i < len(inner) {
		c := inner[i]
		if c == '\\' && i + 1 < len(inner) {
			switch inner[i + 1] {
			case 'n':
				strings.write_byte(&b, '\n')
			case 't':
				strings.write_byte(&b, '\t')
			case 'r':
				strings.write_byte(&b, '\r')
			case '0':
				strings.write_byte(&b, 0)
			case '\\':
				strings.write_byte(&b, '\\')
			case '"':
				strings.write_byte(&b, '"')
			case '\'':
				strings.write_byte(&b, '\'')
			case '$':
				strings.write_byte(&b, '$')
			case:
				strings.write_byte(&b, inner[i + 1])
			}
			i += 2
		} else {
			strings.write_byte(&b, c)
			i += 1
		}
	}
	return strings.to_string(b)
}

lower_tfile :: proc(tfile: semantics.TFile, store: ^semantics.Type_Store) -> IR_Module {
	mod: IR_Module
	mod.decls = make([dynamic]IR_Decl, 0, len(tfile.decls))
	mod.effect_defs = make([dynamic]IR_Effect_Def, 0, 8)
	mod.string_table = make([dynamic]String_Table_Entry, 0, 16)

	env: Lower_Env = {
		module   = &mod,
		store    = store,
		interner = store.interner,
	}
	env.pending_decls = make([dynamic]IR_Decl, 0, 8)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^semantics.TDecl_Effect:
			eff_def := lower_teffect_def(&d^, &env)
			append(&mod.effect_defs, eff_def)
		case ^semantics.TDecl_Effect_Alias,
		     ^semantics.TDecl_Const,
		     ^semantics.TDecl_Trait,
		     ^semantics.TDecl_Alias,
		     ^semantics.TDecl_Newtype,
		     ^semantics.TDecl_Import,
		     ^semantics.TDecl_Test,
		     ^semantics.TDecl_Is_Impl:
		}
	}
	inject_prelude_effect_defs(&mod, store)

	for &decl in tfile.decls {
		#partial switch d in decl {
		case ^semantics.TDecl_Const:
			ir_decl := lower_tdecl_const(&d^, &env)
			// lower_tlambda_as_decl pre-registers lambda declarations in
			// env.module.decls so self-referential calls are classified as
			// direct IR_Call.  Don't double-append the same pointer.
			already_registered := false
			#partial switch new_decl in ir_decl {
			case ^IR_Decl_Fn:
				for existing in mod.decls {
					#partial switch d in existing {
					case ^IR_Decl_Fn:
						if d == new_decl {
							already_registered = true
							break
						}
					}
					if already_registered {
						break
					}
				}
			}
			if !already_registered {
				append(&mod.decls, ir_decl)
			}
		case ^semantics.TDecl_Effect:
			ir_decl := lower_tdecl_effect(&d^, &env)
			append(&mod.decls, ir_decl)
		case ^semantics.TDecl_Effect_Alias:
		case ^semantics.TDecl_Trait:
		case ^semantics.TDecl_Alias:
		case ^semantics.TDecl_Newtype:
		// Newtypes are erased at runtime — no IR decl needed.
		case ^semantics.TDecl_Import:
		case ^semantics.TDecl_Test:
		case ^semantics.TDecl_Expect:
			ir_decl := lower_tdecl_expect(&d^, &env)
			append(&mod.decls, ir_decl)
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

extract_effects :: proc(
	store: ^semantics.Type_Store,
	effect_row_var: base.Type_Var_ID,
	effect_defs: []IR_Effect_Def,
) -> [dynamic]base.Canonical_Name {
	effects: [dynamic]base.Canonical_Name
	effects = make([dynamic]base.Canonical_Name, 0, 4)
	collect_effects_from_row(store, effect_row_var, effect_defs, &effects)
	return effects
}

extract_effects_from_fn_binding :: proc(
	store: ^semantics.Type_Store,
	fn_name: base.Canonical_Name,
	effect_defs: []IR_Effect_Def,
) -> [dynamic]base.Canonical_Name {
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

collect_effects_from_row :: proc(
	store: ^semantics.Type_Store,
	effect_var: base.Type_Var_ID,
	effect_defs: []IR_Effect_Def,
	result: ^[dynamic]base.Canonical_Name,
) {
	resolved := semantics.resolve_var(store, effect_var)
	v := &store.vars[int(resolved)]

	it, ok := v.link.(semantics.Inferred_Type)
	inf, is_inf := it.(semantics.Inferred_Effect_Row)
	if !is_inf || !ok {
		return
	}

	for entry in inf.effects {
		canonical := base.Canonical_Name {
			module = base.NO_NAME,
			name   = entry.name,
		}
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
	lit^ = IR_Literal_Int {
		value = value,
		type  = type_,
		span  = span,
	}
	return IR_Expr(lit)
}

make_ir_lit_bool :: proc(value: bool, type_: base.IR_Type, span: base.Source_Span) -> IR_Expr {
	lit := new(IR_Literal_Bool)
	lit^ = IR_Literal_Bool {
		value = value,
		type  = type_,
		span  = span,
	}
	return IR_Expr(lit)
}


lower_texpr :: proc(expr: semantics.TExpr, env: ^Lower_Env) -> IR_Expr {
	switch e in expr {
	case ^semantics.TExpr_Int:
		type_var := semantics.make_primitive_type(
			env.store,
			base.intern(env.interner, "I64"),
			e.span,
		)
		return make_ir_lit_int(e.value, semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Float:
		type_var := semantics.make_primitive_type(
			env.store,
			base.intern(env.interner, "F64"),
			e.span,
		)
		lit := new(IR_Literal_Float)
		lit^ = IR_Literal_Float {
			value = e.value,
			type  = e.type_,
			span  = e.span,
		}
		return IR_Expr(lit)

	case ^semantics.TExpr_String:
		type_var := semantics.make_primitive_type(
			env.store,
			base.intern(env.interner, "Str"),
			e.span,
		)
		sid := fresh_ir_name(env)
		content := lower_string_content(e.value)
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String {
			id    = sid,
			value = content,
			type  = e.type_,
			span  = e.span,
		}
		append(&env.module.string_table, String_Table_Entry{id = sid, value = content})
		return IR_Expr(lit)

	case ^semantics.TExpr_Bool:
		type_var := semantics.make_primitive_type(
			env.store,
			base.intern(env.interner, "Bool"),
			e.span,
		)
		return make_ir_lit_bool(e.value, semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Char:
		type_var := semantics.make_primitive_type(
			env.store,
			base.intern(env.interner, "I64"),
			e.span,
		)
		return make_ir_lit_int(i64(e.value), semantics.lower_type(env.store, type_var), e.span)

	case ^semantics.TExpr_Todo:
		msg: IR_Expr
		if e.message != nil {
			msg = lower_texpr(e.message, env)
		} else {
			lit := new(IR_Literal_String)
			lit^ = IR_Literal_String {
				value = "todo: not implemented",
				type = base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)},
				span = e.span,
			}
			msg = IR_Expr(lit)
		}
		crash := new(IR_Crash)
		crash^ = IR_Crash {
			message = msg,
			span    = e.span,
		}
		return IR_Expr(crash)

	case ^semantics.TExpr_Name:
		// Re-resolve the wasm type from the final type var. The type snapshot taken
		// during inference can be stale for recursive bindings — e.g. a list tail
		// bound by `Cons(_, t)` only resolves to an i32 heap pointer after the
		// recursive call unifies it, so the snapshot would still read i64.
		var_type := e.type_
		if var_type.type_id != base.Type_Var_ID(0) {
			var_type = semantics.lower_type(env.store, var_type.type_id)
		}
		v := new(IR_Var)
		v^ = IR_Var {
			name = e.name.name,
			type = var_type,
			span = e.span,
		}
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
		ir^ = IR_Expr_Nominal_Construct {
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
	case ^semantics.TExpr_Tuple:
		elements := make([dynamic]IR_Expr, 0, len(e.elements))
		for el in e.elements {
			append(&elements, lower_texpr(el, env))
		}
		result := new(IR_Construct_Tuple)
		result^ = IR_Construct_Tuple {
			elements   = elements,
			reuse_addr = NO_REUSE_ADDR,
			type       = e.type_,
			span       = e.span,
		}
		return IR_Expr(result)

	case ^semantics.TExpr_Field_Index:
		record_ir := lower_texpr(e.record, env)
		resolved_type := semantics.lower_type(env.store, e.type_.type_id)
		result := new(IR_Field_Access)
		result^ = IR_Field_Access {
			record      = record_ir,
			field       = base.NO_NAME,
			field_index = e.field_index,
			type        = resolved_type,
			span        = e.span,
		}
		return IR_Expr(result)

	case ^semantics.TExpr_Record_Update:
		return lower_trecord_update(e, env)

	case ^semantics.TExpr_Assign:
		#partial switch target in e.target {
		case ^semantics.TExpr_Name:
			value := lower_texpr(e.value, env)
			assign := new(IR_Assign)
			assign^ = IR_Assign {
				binding = target.name.name,
				value   = value,
				type    = e.type_,
				span    = e.span,
			}
			return IR_Expr(assign)
		case ^semantics.TExpr_Int,
		     ^semantics.TExpr_Float,
		     ^semantics.TExpr_String,
		     ^semantics.TExpr_Bool,
		     ^semantics.TExpr_Tag,
		     ^semantics.TExpr_Nominal_Construct,
		     ^semantics.TExpr_Record,
		     ^semantics.TExpr_List,
		     ^semantics.TExpr_Call,
		     ^semantics.TExpr_Method_Call,
		     ^semantics.TExpr_Lambda,
		     ^semantics.TExpr_Block,
		     ^semantics.TExpr_If,
		     ^semantics.TExpr_Match,
		     ^semantics.TExpr_BinOp,
		     ^semantics.TExpr_PrefixOp,
		     ^semantics.TExpr_Field_Access,
		     ^semantics.TExpr_Record_Update,
		     ^semantics.TExpr_Return,
		     ^semantics.TExpr_Crash,
		     ^semantics.TExpr_Interpolated_String,
		     ^semantics.TExpr_Handle,
		     ^semantics.TExpr_Perform,
		     ^semantics.TExpr_For,
		     ^semantics.TExpr_Par:
			return lower_texpr(e.value, env)
		}

	case ^semantics.TExpr_Return:
		inner := lower_texpr(e.value, env)
		ret := new(IR_Return)
		ret^ = IR_Return {
			value = inner,
			span  = e.span,
		}
		return IR_Expr(ret)

	case ^semantics.TExpr_Crash:
		msg_expr := lower_texpr(e.message, env)
		crash := new(IR_Crash)
		crash^ = IR_Crash {
			message = msg_expr,
			span    = e.span,
		}
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
		perf^ = IR_Perform {
			effect = e.effect,
			op     = e.op,
			args   = ir_args,
			type   = e.type_,
			span   = e.span,
		}
		return IR_Expr(perf)

	case ^semantics.TExpr_For:
		iterable := lower_texpr(e.iterable, env)
		body := lower_texpr(e.body, env)
		loop := new(IR_Loop)
		loop^ = IR_Loop {
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
			loop^ = IR_Loop {
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
			for idx in 0 ..< len(e.names) {
				append(
					&fields,
					IR_Record_Field {
						name = e.names[idx],
						value = lower_texpr(e.expressions[idx], env),
					},
				)
			}
			record := new(IR_Construct_Record)
			record^ = IR_Construct_Record {
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
		block^ = IR_Block {
			statements = stmts,
			type       = e.type_,
			span       = e.span,
		}
		return IR_Expr(block)
	}

	return make_ir_lit_int(
		0,
		base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(-1)},
		base.Source_Span_ZERO,
	)
}

lower_tdecl_const :: proc(d: ^semantics.TDecl_Const, env: ^Lower_Env) -> IR_Decl {
	#partial switch body_expr in d.body {
	case ^semantics.TExpr_Lambda:
		return lower_tlambda_as_decl(body_expr, d.name, d.is_effectful, d.span, env)
	case ^semantics.TExpr_Int,
	     ^semantics.TExpr_Float,
	     ^semantics.TExpr_String,
	     ^semantics.TExpr_Bool,
	     ^semantics.TExpr_Tag,
	     ^semantics.TExpr_Nominal_Construct,
	     ^semantics.TExpr_Record,
	     ^semantics.TExpr_List,
	     ^semantics.TExpr_Name,
	     ^semantics.TExpr_Call,
	     ^semantics.TExpr_Method_Call,
	     ^semantics.TExpr_Block,
	     ^semantics.TExpr_If,
	     ^semantics.TExpr_Match,
	     ^semantics.TExpr_BinOp,
	     ^semantics.TExpr_PrefixOp,
	     ^semantics.TExpr_Field_Access,
	     ^semantics.TExpr_Record_Update,
	     ^semantics.TExpr_Assign,
	     ^semantics.TExpr_Return,
	     ^semantics.TExpr_Crash,
	     ^semantics.TExpr_Interpolated_String,
	     ^semantics.TExpr_Handle,
	     ^semantics.TExpr_Perform,
	     ^semantics.TExpr_For,
	     ^semantics.TExpr_Par:
	}

	ir_type := d.type_
	body := lower_texpr(d.body, env)

	if d.is_effectful {
		fn_decl := new(IR_Decl_Fn)
		fn_decl^ = IR_Decl_Fn {
			name         = d.name,
			is_effectful = true,
			params       = make([dynamic]IR_Param, 0, 4),
			return_type  = ir_type,
			effect_row   = d.eff_,
			effects      = extract_effects_from_fn_binding(
				env.store,
				d.name,
				env.module.effect_defs[:],
			),
			body         = body,
			span         = d.span,
		}
		return IR_Decl(fn_decl)
	}

	decl := new(IR_Decl_Const)
	decl^ = IR_Decl_Const {
		name  = d.name,
		type  = ir_type,
		value = body,
		span  = d.span,
	}
	return IR_Decl(decl)
}

lower_tlambda_as_decl :: proc(
	e: ^semantics.TExpr_Lambda,
	name: base.Canonical_Name,
	is_effectful: bool,
	span: base.Source_Span,
	env: ^Lower_Env,
) -> IR_Decl {
	params := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		append(&params, IR_Param{name = p.name, type = p.type_})
	}

	// Pre-register a placeholder declaration so that self-referential calls
	// (e.g., `sum(t)` inside `sum = |xs| -> ...`) are classified as direct
	// IR_Call (not IR_Closure_Call) by lower_tcall's is_module_decl check.
	placeholder := new(IR_Decl_Fn)
	placeholder^ = IR_Decl_Fn {
		name        = name,
		params      = params,
		return_type = e.return_type,
		span        = span,
	}
	append(&env.module.decls, IR_Decl(placeholder))

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
	placeholder.is_effectful = is_effectful && len(effects) > 0
	placeholder.effects = effects
	placeholder.effect_row = e.effects
	placeholder.body = body
	return IR_Decl(placeholder)
}

lower_tdecl_effect :: proc(d: ^semantics.TDecl_Effect, env: ^Lower_Env) -> IR_Decl {
	ops := make([dynamic]IR_Effect_Op, 0, len(d.operations))
	for op in d.operations {
		ir_op := lower_teffect_op(op, env)
		append(&ops, ir_op)
	}

	decl := new(IR_Decl_Effect)
	decl^ = IR_Decl_Effect {
		name       = d.name,
		operations = ops,
		span       = d.span,
	}
	return IR_Decl(decl)
}

lower_tdecl_expect :: proc(d: ^semantics.TDecl_Expect, env: ^Lower_Env) -> IR_Decl {
	cond := lower_texpr(d.condition, env)
	msg := d.doc_comment
	if msg == "" {
		msg = "expectation failed"
	}
	msg_id := base.intern(env.interner, msg)
	append(&env.module.string_table, String_Table_Entry{id = msg_id, value = msg})
	decl := new(IR_Decl_Expect)
	decl^ = IR_Decl_Expect {
		condition  = cond,
		message_id = msg_id,
		span       = d.span,
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

	return IR_Effect_Op{name = op.name, params = params, return_type = op.return_type}
}

inject_prelude_effect_defs :: proc(mod: ^IR_Module, store: ^semantics.Type_Store) {
	inject_prelude_effects_lower(mod, store)
}

is_module_decl :: proc(mod: ^IR_Module, name: base.Intern_ID) -> bool {
	for d in mod.decls {
		#partial switch dd in d {
		case ^IR_Decl_Fn:
			if dd.name.name == name do return true
		case ^IR_Decl_Const:
			if dd.name.name == name do return true
		}
	}
	return false
}

lower_tcall :: proc(e: ^semantics.TExpr_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch c in e.callee {
	case ^semantics.TExpr_Name:
		callee_name := c.name
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		// A let-bound name refers to a closure record on the heap, not a
		// top-level function decl — dispatch through the closure.
		if callee_name.is_local && !is_module_decl(env.module, callee_name.name) {
			callee_expr := lower_texpr(e.callee, env)
			ccall := new(IR_Closure_Call)
			ccall^ = IR_Closure_Call {
				callee = callee_expr,
				args   = ir_args,
				type   = e.type_,
				span   = e.span,
			}
			return IR_Expr(ccall)
		}
		call := new(IR_Call)
		call^ = IR_Call {
			callee           = callee_name,
			args             = ir_args,
			type             = e.type_,
			span             = e.span,
			ord_compare_func = resolve_ord_compare(callee_name, e.args, env),
		}
		return IR_Expr(call)

	case ^semantics.TExpr_Int,
	     ^semantics.TExpr_Float,
	     ^semantics.TExpr_String,
	     ^semantics.TExpr_Bool,
	     ^semantics.TExpr_Tag,
	     ^semantics.TExpr_Nominal_Construct,
	     ^semantics.TExpr_Record,
	     ^semantics.TExpr_List,
	     ^semantics.TExpr_Call,
	     ^semantics.TExpr_Method_Call,
	     ^semantics.TExpr_Lambda,
	     ^semantics.TExpr_Block,
	     ^semantics.TExpr_If,
	     ^semantics.TExpr_Match,
	     ^semantics.TExpr_BinOp,
	     ^semantics.TExpr_PrefixOp,
	     ^semantics.TExpr_Field_Access,
	     ^semantics.TExpr_Record_Update,
	     ^semantics.TExpr_Assign,
	     ^semantics.TExpr_Return,
	     ^semantics.TExpr_Crash,
	     ^semantics.TExpr_Interpolated_String,
	     ^semantics.TExpr_Handle,
	     ^semantics.TExpr_Perform,
	     ^semantics.TExpr_For,
	     ^semantics.TExpr_Par:
		callee_expr := lower_texpr(e.callee, env)
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_texpr(arg, env))
		}
		ccall := new(IR_Closure_Call)
		ccall^ = IR_Closure_Call {
			callee = callee_expr,
			args   = ir_args,
			type   = e.type_,
			span   = e.span,
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
	case ^semantics.TExpr_Int,
	     ^semantics.TExpr_Float,
	     ^semantics.TExpr_String,
	     ^semantics.TExpr_Bool,
	     ^semantics.TExpr_Nominal_Construct,
	     ^semantics.TExpr_Record,
	     ^semantics.TExpr_List,
	     ^semantics.TExpr_Call,
	     ^semantics.TExpr_Method_Call,
	     ^semantics.TExpr_Lambda,
	     ^semantics.TExpr_Block,
	     ^semantics.TExpr_If,
	     ^semantics.TExpr_Match,
	     ^semantics.TExpr_BinOp,
	     ^semantics.TExpr_PrefixOp,
	     ^semantics.TExpr_Field_Access,
	     ^semantics.TExpr_Record_Update,
	     ^semantics.TExpr_Assign,
	     ^semantics.TExpr_Return,
	     ^semantics.TExpr_Crash,
	     ^semantics.TExpr_Interpolated_String,
	     ^semantics.TExpr_Handle,
	     ^semantics.TExpr_Perform,
	     ^semantics.TExpr_For,
	     ^semantics.TExpr_Par,
	     ^semantics.TExpr_Tuple,
	     ^semantics.TExpr_Field_Index:
	}

	if receiver_effect_name != base.NO_NAME &&
	   semantics.is_declared_effect(env.store, receiver_effect_name) {
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
						resolved_type := semantics.lower_type(
							env.store,
							op_def.return_type.type_id,
						)
						perf_type = resolved_type
						break
					}
				}
				break
			}
		}
		perf := new(IR_Perform)
		perf^ = IR_Perform {
			effect = receiver_effect_canonical,
			op     = e.method.name,
			args   = ir_args,
			type   = perf_type,
			span   = e.span,
		}
		return IR_Expr(perf)
	}

	// Check for string method intrinsics: .len() and .slice()
	// We check the receiver type to see if it's a Str
	method_str := base.intern_get(env.interner, e.method.name)
	receiver_type_var := texpr_type_id(e.receiver)

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
						call^ = IR_Call {
							callee = base.Canonical_Name{module = str_name, name = len_name},
							args = args,
							type = e.type_,
							span = e.span,
							ord_compare_func = base.Canonical_Name{},
						}
						return IR_Expr(call)
					}
				}
			}
		}
	}


	// Try resolving via trait implementations for newtypes
	if receiver_type_var != 0 {
		resolved_type := semantics.resolve_var(env.store, receiver_type_var)
		v := &env.store.vars[int(resolved_type)]
		if inf, ok := v.link.(semantics.Inferred_Type); ok {
			if nt, ok2 := inf.(semantics.Inferred_Newtype); ok2 {
				for impl in env.store.trait_impls {
					if impl.type_name == nt.primitive_name {
						if fn_name, has := impl.methods[e.method.name]; has {
							ir_args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
							append(&ir_args, receiver_ir)
							for arg in e.args {
								append(&ir_args, lower_texpr(arg, env))
							}
							call := new(IR_Call)
							call^ = IR_Call {
								callee           = fn_name,
								args             = ir_args,
								type             = e.type_,
								span             = e.span,
								ord_compare_func = base.Canonical_Name{},
							}
							return IR_Expr(call)
						}
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
		meth_call^ = IR_Call {
			callee           = e.resolved_,
			args             = ir_args,
			type             = e.type_,
			span             = e.span,
			ord_compare_func = base.Canonical_Name{},
		}
		return IR_Expr(meth_call)
	}

	ccall := new(IR_Closure_Call)
	ccall^ = IR_Closure_Call {
		callee = receiver_ir,
		args   = ir_args,
		type   = e.type_,
		span   = e.span,
	}
	return IR_Expr(ccall)
}

lower_tlambda :: proc(e: ^semantics.TExpr_Lambda, env: ^Lower_Env) -> IR_Expr {
	name := base.Canonical_Name {
		module   = 0,
		name     = fresh_ir_name(env),
		is_local = true,
	}

	params := make([dynamic]IR_Param, 0, len(e.params))
	for p in e.params {
		append(&params, IR_Param{name = p.name, type = p.type_})
	}

	body := lower_texpr(e.body, env)

	effects := extract_effects_from_fn_binding(env.store, name, env.module.effect_defs[:])

	_ = effects

	closure_params := make([dynamic]IR_Param, len(params))
	for p, i in params {
		closure_params[i] = p
	}

	// closure_convert produces the IR_Decl_Fn (rewriting free-var access
	// through the env record) — emitting a separate, unrewritten decl here
	// would leave free vars unbound at codegen.
	closure := new(IR_Closure)
	closure^ = IR_Closure {
		fn_name     = name,
		params      = closure_params,
		env         = IR_Expr(nil),
		body        = body,
		type        = e.type_,
		return_type = e.return_type,
		span        = e.span,
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
	block^ = IR_Block {
		statements = stmts,
		type       = e.type_,
		span       = e.span,
	}
	return IR_Expr(block)
}

lower_tif :: proc(e: ^semantics.TExpr_If, env: ^Lower_Env) -> IR_Expr {
	cond_ir := lower_texpr(e.condition, env)
	then_ir := lower_texpr(e.then_branch, env)
	else_ir := lower_texpr(e.else_branch, env)
	result := new(IR_If)
	result^ = IR_If {
		condition   = cond_ir,
		then_branch = then_ir,
		else_branch = else_ir,
		type        = e.type_,
		span        = e.span,
	}
	return IR_Expr(result)
}

texpr_type_id :: proc(e: semantics.TExpr) -> base.Type_Var_ID {
	if e == nil do return base.Type_Var_ID(0)
	#partial switch expr in e {
	case ^semantics.TExpr_Int:
		return expr.type_.type_id
	case ^semantics.TExpr_Float:
		return expr.type_.type_id
	case ^semantics.TExpr_String:
		return expr.type_.type_id
	case ^semantics.TExpr_Bool:
		return expr.type_.type_id
	case ^semantics.TExpr_Char:
		return expr.type_.type_id
	case ^semantics.TExpr_Todo:
		return expr.type_.type_id
	case ^semantics.TExpr_Tag:
		return expr.type_.type_id
	case ^semantics.TExpr_Nominal_Construct:
		return expr.resolved_type
	case ^semantics.TExpr_Record:
		return expr.type_.type_id
	case ^semantics.TExpr_List:
		return expr.type_.type_id
	case ^semantics.TExpr_Name:
		return expr.type_.type_id
	case ^semantics.TExpr_Call:
		return expr.type_.type_id
	case ^semantics.TExpr_Method_Call:
		return expr.type_.type_id
	case ^semantics.TExpr_Lambda:
		return expr.type_.type_id
	case ^semantics.TExpr_Block:
		return expr.type_.type_id
	case ^semantics.TExpr_If:
		return expr.type_.type_id
	case ^semantics.TExpr_Match:
		return expr.type_.type_id
	case ^semantics.TExpr_BinOp:
		return expr.type_.type_id
	case ^semantics.TExpr_PrefixOp:
		return expr.type_.type_id
	case ^semantics.TExpr_Field_Access:
		return expr.type_.type_id
	case ^semantics.TExpr_Tuple:
		return expr.type_.type_id
	case ^semantics.TExpr_Field_Index:
		return expr.type_.type_id
	case ^semantics.TExpr_Record_Update:
		return expr.type_.type_id
	case ^semantics.TExpr_Assign:
		return expr.type_.type_id
	case ^semantics.TExpr_Return:
		return expr.type_.type_id
	case ^semantics.TExpr_Crash:
		return expr.type_.type_id
	case ^semantics.TExpr_Interpolated_String:
		return expr.type_.type_id
	case ^semantics.TExpr_Handle:
		return expr.type_.type_id
	case ^semantics.TExpr_Perform:
		return expr.type_.type_id
	case ^semantics.TExpr_For:
		return expr.type_.type_id
	case ^semantics.TExpr_Par:
		return expr.type_.type_id
	}
	return base.Type_Var_ID(0)
}

resolve_tag_payload_wasm_types :: proc(
	store: ^semantics.Type_Store,
	scrutinee_type_id: base.Type_Var_ID,
	tag_name: base.Intern_ID,
) -> []base.IR_Wasm_Type {
	if scrutinee_type_id == base.Type_Var_ID(0) {
		return nil
	}
	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(store, scrutinee_type_id, &entries)
	for entry in entries {
		if entry.name == tag_name {
			types := make([]base.IR_Wasm_Type, len(entry.payload))
			for i in 0 ..< len(entry.payload) {
				types[i] = semantics.lower_type(store, entry.payload[i]).wasm_type
			}
			return types
		}
	}
	return nil
}

lower_tmatch :: proc(e: ^semantics.TExpr_Match, env: ^Lower_Env) -> IR_Expr {
	scrut_ir := lower_texpr(e.scrutinee, env)
	scrutinee_type_id := texpr_type_id(e.scrutinee)

	// Desugar or-patterns: A | B | C => body becomes three separate arms.
	// This avoids adding IR_Pat_Or and updating every IR pass + codegen.
	arms := make([dynamic]IR_Match_Arm, 0, len(e.arms))
	for i in 0 ..< len(e.arms) {
		guard_ir: IR_Expr
		if e.arms[i].guard != nil {
			guard_ir = lower_texpr(e.arms[i].guard, env)
		}
		body_ir := lower_texpr(e.arms[i].body, env)

		or_pat, is_or := e.arms[i].pattern.(^semantics.TPattern_Or)
		if is_or {
			for alt in or_pat.alternatives {
				append(
					&arms,
					IR_Match_Arm {
						pattern = lower_tpattern(alt, env, scrutinee_type_id),
						guard = guard_ir,
						body = body_ir,
					},
				)
			}
		} else {
			append(
				&arms,
				IR_Match_Arm {
					pattern = lower_tpattern(e.arms[i].pattern, env, scrutinee_type_id),
					guard = guard_ir,
					body = body_ir,
				},
			)
		}
	}

	result := new(IR_Match)
	result^ = IR_Match {
		scrutinee = scrut_ir,
		arms      = arms,
		type      = e.type_,
		span      = e.span,
	}
	return IR_Expr(result)
}

lower_tpattern :: proc(
	pattern: semantics.TPattern,
	env: ^Lower_Env,
	scrutinee_type_id: base.Type_Var_ID = base.Type_Var_ID(0),
) -> IR_Pattern {
	switch p in pattern {
	case ^semantics.TPattern_Tag:
		payload_ids := make([dynamic]base.Intern_ID, 0, len(p.payload))
		for sub in p.payload {
			#partial switch s in sub {
			case ^semantics.TPattern_Identifier:
				append(&payload_ids, s.name)
			case ^semantics.TPattern_Tag,
			     ^semantics.TPattern_Record,
			     ^semantics.TPattern_List,
			     ^semantics.TPattern_Int,
			     ^semantics.TPattern_String,
			     ^semantics.TPattern_Bool,
			     ^semantics.TPattern_Wildcard,
			     ^semantics.TPattern_Destructure,
			     ^semantics.TPattern_Or:
				append(&payload_ids, base.Intern_ID(0))
			}
		}
		result := new(IR_Pat_Tag)
		result.name = p.name.name
		result.tag_index = resolve_tag_index(env.store, scrutinee_type_id, p.name.name)
		result.payload = payload_ids
		result.payload_wasm_types = resolve_tag_payload_wasm_types(
			env.store,
			scrutinee_type_id,
			p.name.name,
		)
		return IR_Pattern(result)

	case ^semantics.TPattern_Record:
		fields_ir := make([dynamic]IR_Pat_Field, len(p.fields))
		canonical := canonical_field_order(env.store, scrutinee_type_id)
		defer delete(canonical)
		for i in 0 ..< len(p.fields) {
			f := p.fields[i]
			idx := 0
			wt: base.IR_Wasm_Type = .I64
			for c, ci in canonical {
				if c.name == f.name {
					idx = ci
					field_type := semantics.lower_type(env.store, c.var)
					wt = field_type.wasm_type
					break
				}
			}
			fields_ir[i] = IR_Pat_Field {
				name        = f.name,
				binding     = f.binding,
				field_index = idx,
				wasm_type   = wt,
			}
		}
		result := new(IR_Pat_Record)
		result.fields = fields_ir
		result.is_open = p.is_open
		result.rest = p.rest
		return IR_Pattern(result)
	case ^semantics.TPattern_Tuple:
		elements_ir := make([dynamic]IR_Pat_Tuple_Element, len(p.elements))
		for i in 0 ..< len(p.elements) {
			sub := p.elements[i]
			binding: base.Intern_ID = 0
			#partial switch s in sub {
			case ^semantics.TPattern_Identifier:
				binding = s.name
			case ^semantics.TPattern_Tag,
			     ^semantics.TPattern_Record,
			     ^semantics.TPattern_Tuple,
			     ^semantics.TPattern_List,
			     ^semantics.TPattern_Int,
			     ^semantics.TPattern_String,
			     ^semantics.TPattern_Bool,
			     ^semantics.TPattern_Wildcard,
			     ^semantics.TPattern_Destructure,
			     ^semantics.TPattern_Or:
				binding = base.Intern_ID(0)
			}
			wt: base.IR_Wasm_Type = .I64
			elements_ir[i] = IR_Pat_Tuple_Element {
				binding     = binding,
				field_index = i,
				wasm_type   = wt,
			}
		}
		result := new(IR_Pat_Tuple)
		result.elements = elements_ir
		result.span = p.span
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
					prev_cons.tag_index = resolve_tag_index(
						env.store,
						scrutinee_type_id,
						prev_cons.name,
						// Char patterns are intentionally lowered as integer patterns.
						// WASM has no native char type; chars are represented as i64 (Unicode codepoint).
						// Char-specific error messages are lost, but runtime behavior is correct.
					)
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
		append(
			&env.module.string_table,
			String_Table_Entry{id = string_id, value = lower_string_content(p.value)},
		)
		result := new(IR_Pat_String)
		result.string_id = string_id
		return IR_Pattern(result)

	// Char patterns are intentionally lowered as integer patterns.
	// WASM has no native char type; chars are represented as i64 (Unicode codepoint).
	// Char-specific error messages are lost, but runtime behavior is correct.
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
		return lower_tpattern(p.inner, env, scrutinee_type_id)

	case ^semantics.TPattern_Or:
		// Or-patterns are desugared in lower_tmatch before this function is called.
		// This case should be unreachable; if hit, it's a bug in the desugaring.
		if len(p.alternatives) > 0 {
			return lower_tpattern(p.alternatives[0], env)
		}
		return IR_Pattern(nil)
	case ^semantics.TPattern_As:
		return lower_tpattern(p.inner, env)
	case ^semantics.TPattern_Interpolated_String:
		result := new(IR_Pat_Wildcard)
		return IR_Pattern(result)
	}
	return IR_Pattern(nil)
}

lower_binop_kind :: proc(op: base.Token_Kind) -> IR_BinOp_Kind {
	#partial switch op {
	case .Plus:
		return .Add
	case .Minus:
		return .Sub
	case .Star:
		return .Mul
	case .Slash:
		return .Div
	case .Percent:
		return .Mod
	case .Caret:
		return .Exp
	case .Eq_Eq:
		return .Eq
	case .Bang_Eq:
		return .Ne
	case .Lt:
		return .Lt
	case .Gt:
		return .Gt
	case .Lt_Eq:
		return .Le
	case .Gt_Eq:
		return .Ge
	case .Kw_And:
		return .And
	case .Kw_Or:
		return .Or
	case .Lt_Lt:
		return .Shl
	case .Gt_Gt:
		return .Shr
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
					call^ = IR_Call {
						callee = base.Canonical_Name{module = str_name, name = concat_name},
						args = args,
						type = e.type_,
						span = e.span,
						ord_compare_func = base.Canonical_Name{},
					}
					return IR_Expr(call)
				}
			}
		}
	}
	// Structural Eq: for records, tag unions, and tuples, generate
	// field-by-field comparison instead of a pointer-level BinOp.
	if e.op == .Eq_Eq || e.op == .Bang_Eq {
		left_type_id := texpr_type_id(e.left)
		resolved := semantics.resolve_var(env.store, left_type_id)
		v := &env.store.vars[int(resolved)]
		if inf, ok := v.link.(semantics.Inferred_Type); ok {
			#partial switch tin in inf {
			case semantics.Inferred_Record_Row:
				return lower_structural_eq(e, env, tin.record_fields, tin.record_rest)
			case semantics.Inferred_Tuple:
				return lower_tuple_eq(e, env, tin)
			case semantics.Inferred_Tag_Union_Row:
				// List literals are typed as Tag_Union_Row with Nil/Cons.
				// Inline comparison fails for List because tails are different
				// heap objects — redirect to the List_Eq runtime function.
				if is_list_tag_union(env.store, env.interner, left_type_id) {
					return lower_container_eq_from_type(e, env, "List", left_type_id, 0)
				}
				return lower_tag_union_eq(e, env)
			case semantics.Inferred_Newtype:
				// Nominal tag unions (Result, etc.) get structural tag union Eq.
				// Container types (List, Map, Set) are excluded — their linked-list
				// structure makes inline comparison infinite; they need runtime funcs.
				name_str := base.intern_get(env.interner, tin.primitive_name)
				if name_str == "List" {
					return lower_container_eq(e, env, "List", tin, 0)
				} else if name_str != "Map" && name_str != "Set" {
					tag_entries: [dynamic]semantics.Type_Tag_Entry
					tag_entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
					defer delete(tag_entries)
					flatten_tag_entries(env.store, left_type_id, &tag_entries)
					if len(tag_entries) > 0 {
						return lower_tag_union_eq(e, env)
					}
				}
			}
		}
	}
	// Structural Ord: for records, tag unions, tuples, and nominal tag
	// unions (Result, etc.), generate lexicographic comparison.
	if e.op == .Lt || e.op == .Gt || e.op == .Lt_Eq || e.op == .Gt_Eq {
		left_type_id := texpr_type_id(e.left)
		resolved := semantics.resolve_var(env.store, left_type_id)
		v := &env.store.vars[int(resolved)]
		if inf, ok := v.link.(semantics.Inferred_Type); ok {
			#partial switch tin in inf {
			case semantics.Inferred_Record_Row:
				return lower_structural_ord(e, env, tin.record_fields)
			case semantics.Inferred_Tuple:
				return lower_tuple_ord(e, env, tin)
			case semantics.Inferred_Tag_Union_Row:
				return lower_tag_union_ord(e, env)
			case semantics.Inferred_Newtype:
				name_str := base.intern_get(env.interner, tin.primitive_name)
				if name_str != "List" && name_str != "Map" && name_str != "Set" {
					tag_entries: [dynamic]semantics.Type_Tag_Entry
					tag_entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
					defer delete(tag_entries)
					flatten_tag_entries(env.store, left_type_id, &tag_entries)
					if len(tag_entries) > 0 {
						return lower_tag_union_ord(e, env)
					}
				}
			}
		}
	}
	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	result := new(IR_BinOp)
	result^ = IR_BinOp {
		op    = lower_binop_kind(e.op),
		left  = left_ir,
		right = right_ir,
		type  = e.type_,
		span  = e.span,
	}
	return IR_Expr(result)
}
// lower_structural_eq generates field-by-field == for records:
// (a.f1 == b.f1) && (a.f2 == b.f2) && ...
// For !=, wraps the result in a not-equal comparison.
lower_structural_eq :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	fields: []semantics.Type_Field_Entry,
	rest: base.Type_Var_ID,
) -> IR_Expr {
	if len(fields) == 0 {
		left_ir := lower_texpr(e.left, env)
		right_ir := lower_texpr(e.right, env)
		result := new(IR_BinOp)
		result^ = IR_BinOp {
			op    = .Eq,
			left  = left_ir,
			right = right_ir,
			type  = e.type_,
			span  = e.span,
		}
		ir_expr := IR_Expr(result)
		if e.op == .Bang_Eq {
			return wrap_not(ir_expr, e)
		}
		return ir_expr
	}
	// Canonical alphabetical order
	sorted := make([dynamic]semantics.Type_Field_Entry, 0, len(fields))
	for f in fields do append(&sorted, f)
	for i := 1; i < len(sorted); i += 1 {
		for j := i; j > 0; j -= 1 {
			a := base.intern_get(env.interner, sorted[j].name)
			b := base.intern_get(env.interner, sorted[j - 1].name)
			if a < b {
				sorted[j], sorted[j - 1] = sorted[j - 1], sorted[j]
			} else {
				break
			}
		}
	}
	defer delete(sorted)
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}
	chain: IR_Expr = nil
	for fi in 0 ..< len(sorted) {
		f := sorted[fi]
		f_type := semantics.lower_type(env.store, f.var)
		left_fa := new(IR_Field_Access)
		left_fa^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}
		right_fa := new(IR_Field_Access)
		right_fa^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}
		field_eq := new(IR_BinOp)
		field_eq^ = IR_BinOp {
			op    = .Eq,
			left  = IR_Expr(left_fa),
			right = IR_Expr(right_fa),
			type  = bool_type,
			span  = e.span,
		}
		if chain == nil {
			chain = IR_Expr(field_eq)
		} else {
			both := new(IR_BinOp)
			both^ = IR_BinOp {
				op    = .And,
				left  = chain,
				right = IR_Expr(field_eq),
				type  = bool_type,
				span  = e.span,
			}
			chain = IR_Expr(both)
		}
	}
	if chain == nil {
		chain = make_ir_lit_bool(true, e.type_, e.span)
	}
	if e.op == .Bang_Eq {
		return wrap_not(chain, e)
	}
	return chain
}
lower_tuple_eq :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	tin: semantics.Inferred_Tuple,
) -> IR_Expr {
	if tin.element_count == 0 {
		left_ir := lower_texpr(e.left, env)
		right_ir := lower_texpr(e.right, env)
		result := new(IR_BinOp)
		result^ = IR_BinOp {
			op    = .Eq,
			left  = left_ir,
			right = right_ir,
			type  = e.type_,
			span  = e.span,
		}
		ir_expr := IR_Expr(result)
		if e.op == .Bang_Eq {
			return wrap_not(ir_expr, e)
		}
		return ir_expr
	}
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}
	chain: IR_Expr = nil
	for i in 0 ..< tin.element_count {
		field_name := base.intern(env.interner, fmt.tprintf("_%d", i))
		elem_type := semantics.lower_type(env.store, tin.element_types[i])
		left_fa := new(IR_Field_Access)
		left_fa^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}
		right_fa := new(IR_Field_Access)
		right_fa^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}
		field_eq := new(IR_BinOp)
		field_eq^ = IR_BinOp {
			op    = .Eq,
			left  = IR_Expr(left_fa),
			right = IR_Expr(right_fa),
			type  = bool_type,
			span  = e.span,
		}
		if chain == nil {
			chain = IR_Expr(field_eq)
		} else {
			both := new(IR_BinOp)
			both^ = IR_BinOp {
				op    = .And,
				left  = chain,
				right = IR_Expr(field_eq),
				type  = bool_type,
				span  = e.span,
			}
			chain = IR_Expr(both)
		}
	}
	if chain == nil {
		chain = make_ir_lit_bool(true, e.type_, e.span)
	}
	if e.op == .Bang_Eq {
		return wrap_not(chain, e)
	}
	return chain
}
// lower_tag_union_eq generates tag-byte + per-variant payload == for tag unions.
// Compare discriminants first; if equal, match on the left to compare
// payload fields of the matched variant.
lower_tag_union_eq :: proc(e: ^semantics.TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}
	left_type_id := texpr_type_id(e.left)

	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(env.store, left_type_id, &entries)

	// Build IR_Match arms on the left operand.  In each arm, compare the
	// right's tag index and payload fields.
	arms := make([dynamic]IR_Match_Arm, 0, len(entries))
	for i in 0 ..< len(entries) {
		entry := entries[i]

		// Build the arm body: compare right's tag index, then payload fields.
		// right_tag == i  (mask to byte: IR_I32_Load reads 4 bytes but tag is 1 byte)
		right_tag_load := new(IR_I32_Load)
		right_tag_load^ = IR_I32_Load {
			base   = right_ir,
			offset = 4, // CAMP_TAG_TAG_OFFSET — tag discriminant byte
			span   = e.span,
		}
		right_tag_masked := new(IR_BinOp)
		right_tag_masked^ = IR_BinOp {
			op    = .And,
			left  = IR_Expr(right_tag_load),
			right = make_ir_lit_int(0xFF, bool_type, e.span),
			type  = bool_type,
			span  = e.span,
		}
		expected_tag := make_ir_lit_int(i64(i), bool_type, e.span)
		tag_check := new(IR_BinOp)
		tag_check^ = IR_BinOp {
			op    = .Eq,
			left  = IR_Expr(right_tag_masked),
			right = expected_tag,
			type  = bool_type,
			span  = e.span,
		}

		chain: IR_Expr = IR_Expr(tag_check)
		for j in 0 ..< len(entry.payload) {
			f_type := semantics.lower_type(env.store, entry.payload[j])
			left_fa := new(IR_Field_Access)
			left_fa^ = IR_Field_Access {
				record      = left_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}
			right_fa := new(IR_Field_Access)
			right_fa^ = IR_Field_Access {
				record      = right_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}
			field_eq := new(IR_BinOp)
			field_eq^ = IR_BinOp {
				op    = .Eq,
				left  = IR_Expr(left_fa),
				right = IR_Expr(right_fa),
				type  = bool_type,
				span  = e.span,
			}
			both := new(IR_BinOp)
			both^ = IR_BinOp {
				op    = .And,
				left  = chain,
				right = IR_Expr(field_eq),
				type  = bool_type,
				span  = e.span,
			}
			chain = IR_Expr(both)
		}

		// Build pattern (wildcard payload bindings — we access fields
		// via IR_Field_Access, not via pattern bindings).
		pat := new(IR_Pat_Tag)
		pat^ = IR_Pat_Tag {
			name      = entry.name,
			tag_index = i,
		}
		append(&arms, IR_Match_Arm{pattern = IR_Pattern(pat), body = chain})
	}

	match_ir := new(IR_Match)
	match_ir^ = IR_Match {
		scrutinee = left_ir,
		arms      = arms,
		type      = bool_type,
		span      = e.span,
	}
	result := IR_Expr(match_ir)
	if e.op == .Bang_Eq {
		return wrap_not(result, e)
	}
	return result
}

wrap_not :: proc(expr: IR_Expr, e: ^semantics.TExpr_BinOp) -> IR_Expr {
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}
	false_lit := make_ir_lit_bool(false, bool_type, e.span)
	result := new(IR_BinOp)
	result^ = IR_BinOp {
		op    = .Eq,
		left  = expr,
		right = false_lit,
		type  = bool_type,
		span  = e.span,
	}
	return IR_Expr(result)
}

// lower_structural_ord generates lexicographic < / > / <= / >= for records.
// Fields are sorted alphabetically.  For each pair, check "less_op" (True)
// then "greater_op" (False), falling through to the next field.  The base
// case depends on whether the operator is strict (< / > → false) or
// reflexive (<= / >= → true).
lower_structural_ord :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	fields: []semantics.Type_Field_Entry,
) -> IR_Expr {
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}

	less_op, greater_op: IR_BinOp_Kind
	base_val: bool
	if e.op == .Lt {
		less_op = .Lt; greater_op = .Gt; base_val = false
	} else if e.op == .Gt {
		less_op = .Gt; greater_op = .Lt; base_val = false
	} else if e.op == .Lt_Eq {
		less_op = .Lt; greater_op = .Gt; base_val = true
	} else if e.op == .Gt_Eq {
		less_op = .Gt; greater_op = .Lt; base_val = true
	} else {
		return make_ir_lit_bool(false, bool_type, e.span)
	}

	if len(fields) == 0 {
		return make_ir_lit_bool(base_val, bool_type, e.span)
	}

	sorted := make([dynamic]semantics.Type_Field_Entry, 0, len(fields))
	for f in fields do append(&sorted, f)
	for i := 1; i < len(sorted); i += 1 {
		for j := i; j > 0; j -= 1 {
			a := base.intern_get(env.interner, sorted[j].name)
			b := base.intern_get(env.interner, sorted[j - 1].name)
			if a < b {
				sorted[j], sorted[j - 1] = sorted[j - 1], sorted[j]
			} else {
				break
			}
		}
	}
	defer delete(sorted)

	// Build from the inside out: start with the base case, then wrap
	// each field pair's checks around it.
	chain := make_ir_lit_bool(base_val, bool_type, e.span)
	for fi := len(sorted) - 1; fi >= 0; fi -= 1 {
		f := sorted[fi]
		f_type := semantics.lower_type(env.store, f.var)
		left_fa := new(IR_Field_Access)
		left_fa^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}
		right_fa := new(IR_Field_Access)
		right_fa^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}

		// if a.f <op> b.f { true } else { ... }
		less_check := new(IR_BinOp)
		less_check^ = IR_BinOp {
			op    = less_op,
			left  = IR_Expr(left_fa),
			right = IR_Expr(right_fa),
			type  = bool_type,
			span  = e.span,
		}
		true_lit := make_ir_lit_bool(true, bool_type, e.span)
		if_less := new(IR_If)
		if_less^ = IR_If {
			condition   = IR_Expr(less_check),
			then_branch = true_lit,
			else_branch = chain,
			type        = bool_type,
			span        = e.span,
		}

		// if a.f <greater_op> b.f { false } else { if_less }
		greater_fa_l := new(IR_Field_Access)
		greater_fa_l^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}
		greater_fa_r := new(IR_Field_Access)
		greater_fa_r^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = f.name,
			field_index = fi,
			type        = f_type,
			span        = e.span,
		}
		greater_check := new(IR_BinOp)
		greater_check^ = IR_BinOp {
			op    = greater_op,
			left  = IR_Expr(greater_fa_l),
			right = IR_Expr(greater_fa_r),
			type  = bool_type,
			span  = e.span,
		}
		false_lit := make_ir_lit_bool(false, bool_type, e.span)
		if_greater := new(IR_If)
		if_greater^ = IR_If {
			condition   = IR_Expr(greater_check),
			then_branch = false_lit,
			else_branch = IR_Expr(if_less),
			type        = bool_type,
			span        = e.span,
		}
		chain = IR_Expr(if_greater)
	}
	return chain
}

// lower_tuple_ord generates lexicographic < / > / <= / >= for tuples.
lower_tuple_ord :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	tin: semantics.Inferred_Tuple,
) -> IR_Expr {
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}

	less_op, greater_op: IR_BinOp_Kind
	base_val: bool
	if e.op == .Lt {
		less_op = .Lt; greater_op = .Gt; base_val = false
	} else if e.op == .Gt {
		less_op = .Gt; greater_op = .Lt; base_val = false
	} else if e.op == .Lt_Eq {
		less_op = .Lt; greater_op = .Gt; base_val = true
	} else if e.op == .Gt_Eq {
		less_op = .Gt; greater_op = .Lt; base_val = true
	} else {
		return make_ir_lit_bool(false, bool_type, e.span)
	}

	if tin.element_count == 0 {
		return make_ir_lit_bool(base_val, bool_type, e.span)
	}

	chain := make_ir_lit_bool(base_val, bool_type, e.span)
	for i := tin.element_count - 1; i >= 0; i -= 1 {
		field_name := base.intern(env.interner, fmt.tprintf("_%d", i))
		elem_type := semantics.lower_type(env.store, tin.element_types[i])
		left_fa := new(IR_Field_Access)
		left_fa^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}
		right_fa := new(IR_Field_Access)
		right_fa^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}

		less_check := new(IR_BinOp)
		less_check^ = IR_BinOp {
			op    = less_op,
			left  = IR_Expr(left_fa),
			right = IR_Expr(right_fa),
			type  = bool_type,
			span  = e.span,
		}
		true_lit := make_ir_lit_bool(true, bool_type, e.span)
		if_less := new(IR_If)
		if_less^ = IR_If {
			condition   = IR_Expr(less_check),
			then_branch = true_lit,
			else_branch = chain,
			type        = bool_type,
			span        = e.span,
		}

		greater_fa_l := new(IR_Field_Access)
		greater_fa_l^ = IR_Field_Access {
			record      = lower_texpr(e.left, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}
		greater_fa_r := new(IR_Field_Access)
		greater_fa_r^ = IR_Field_Access {
			record      = lower_texpr(e.right, env),
			field       = field_name,
			field_index = i,
			type        = elem_type,
			span        = e.span,
		}
		greater_check := new(IR_BinOp)
		greater_check^ = IR_BinOp {
			op    = greater_op,
			left  = IR_Expr(greater_fa_l),
			right = IR_Expr(greater_fa_r),
			type  = bool_type,
			span  = e.span,
		}
		false_lit := make_ir_lit_bool(false, bool_type, e.span)
		if_greater := new(IR_If)
		if_greater^ = IR_If {
			condition   = IR_Expr(greater_check),
			then_branch = false_lit,
			else_branch = IR_Expr(if_less),
			type        = bool_type,
			span        = e.span,
		}
		chain = IR_Expr(if_greater)
	}
	return chain
}

// lower_tag_union_ord generates < / > / <= / >= for tag unions.
// First compare tag indices (lower index = less), then payloads lexicographically.
lower_tag_union_ord :: proc(e: ^semantics.TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}
	left_type_id := texpr_type_id(e.left)

	less_op, greater_op: IR_BinOp_Kind
	base_val: bool
	if e.op == .Lt {
		less_op = .Lt; greater_op = .Gt; base_val = false
	} else if e.op == .Gt {
		less_op = .Gt; greater_op = .Lt; base_val = false
	} else if e.op == .Lt_Eq {
		less_op = .Lt; greater_op = .Gt; base_val = true
	} else if e.op == .Gt_Eq {
		less_op = .Gt; greater_op = .Lt; base_val = true
	} else {
		return make_ir_lit_bool(false, bool_type, e.span)
	}

	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(env.store, left_type_id, &entries)

	// Tag index comparison: tag(left) vs tag(right)
	// Mask with 0xFF: IR_I32_Load reads 4 bytes but tag is 1 byte.
	left_tag_load := new(IR_I32_Load)
	left_tag_load^ = IR_I32_Load {
		base   = left_ir,
		offset = 4, // CAMP_TAG_TAG_OFFSET
		span   = e.span,
	}
	left_tag_masked := new(IR_BinOp)
	left_tag_masked^ = IR_BinOp {
		op    = .And,
		left  = IR_Expr(left_tag_load),
		right = make_ir_lit_int(0xFF, bool_type, e.span),
		type  = bool_type,
		span  = e.span,
	}
	right_tag_load := new(IR_I32_Load)
	right_tag_load^ = IR_I32_Load {
		base   = right_ir,
		offset = 4,
		span   = e.span,
	}
	right_tag_masked := new(IR_BinOp)
	right_tag_masked^ = IR_BinOp {
		op    = .And,
		left  = IR_Expr(right_tag_load),
		right = make_ir_lit_int(0xFF, bool_type, e.span),
		type  = bool_type,
		span  = e.span,
	}

	// If tags differ, compare tag indices directly.
	tag_less := new(IR_BinOp)
	tag_less^ = IR_BinOp {
		op    = less_op,
		left  = IR_Expr(left_tag_masked),
		right = IR_Expr(right_tag_masked),
		type  = bool_type,
		span  = e.span,
	}
	tag_greater := new(IR_BinOp)
	tag_greater^ = IR_BinOp {
		op    = greater_op,
		left  = IR_Expr(left_tag_masked),
		right = IR_Expr(right_tag_masked),
		type  = bool_type,
		span  = e.span,
	}

	// If tags equal, compare payloads per variant using IR_Match.
	arms := make([dynamic]IR_Match_Arm, 0, len(entries))
	for i in 0 ..< len(entries) {
		entry := entries[i]

		// Build payload comparison chain (lexicographic, inside-out).
		payload_chain := make_ir_lit_bool(base_val, bool_type, e.span)
		for j := len(entry.payload) - 1; j >= 0; j -= 1 {
			f_type := semantics.lower_type(env.store, entry.payload[j])
			l_fa := new(IR_Field_Access)
			l_fa^ = IR_Field_Access {
				record      = left_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}
			r_fa := new(IR_Field_Access)
			r_fa^ = IR_Field_Access {
				record      = right_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}

			l_check := new(IR_BinOp)
			l_check^ = IR_BinOp {
				op    = less_op,
				left  = IR_Expr(l_fa),
				right = IR_Expr(r_fa),
				type  = bool_type,
				span  = e.span,
			}
			true_lit := make_ir_lit_bool(true, bool_type, e.span)
			if_l := new(IR_If)
			if_l^ = IR_If {
				condition   = IR_Expr(l_check),
				then_branch = true_lit,
				else_branch = payload_chain,
				type        = bool_type,
				span        = e.span,
			}

			g_fa_l := new(IR_Field_Access)
			g_fa_l^ = IR_Field_Access {
				record      = left_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}
			g_fa_r := new(IR_Field_Access)
			g_fa_r^ = IR_Field_Access {
				record      = right_ir,
				field_index = j,
				type        = f_type,
				span        = e.span,
			}
			g_check := new(IR_BinOp)
			g_check^ = IR_BinOp {
				op    = greater_op,
				left  = IR_Expr(g_fa_l),
				right = IR_Expr(g_fa_r),
				type  = bool_type,
				span  = e.span,
			}
			false_lit := make_ir_lit_bool(false, bool_type, e.span)
			if_g := new(IR_If)
			if_g^ = IR_If {
				condition   = IR_Expr(g_check),
				then_branch = false_lit,
				else_branch = IR_Expr(if_l),
				type        = bool_type,
				span        = e.span,
			}
			payload_chain = IR_Expr(if_g)
		}

		pat := new(IR_Pat_Tag)
		pat^ = IR_Pat_Tag {
			name      = entry.name,
			tag_index = i,
		}
		append(&arms, IR_Match_Arm{pattern = IR_Pattern(pat), body = payload_chain})
	}

	match_ir := new(IR_Match)
	match_ir^ = IR_Match {
		scrutinee = left_ir,
		arms      = arms,
		type      = bool_type,
		span      = e.span,
	}

	// if tag(left) <_op tag(right): true
	// else if tag(left) >_op tag(right): false
	// else: match on left for payload comparison
	false_lit := make_ir_lit_bool(false, bool_type, e.span)
	if_greater := new(IR_If)
	if_greater^ = IR_If {
		condition   = IR_Expr(tag_greater),
		then_branch = false_lit,
		else_branch = IR_Expr(match_ir),
		type        = bool_type,
		span        = e.span,
	}
	true_lit := make_ir_lit_bool(true, bool_type, e.span)
	result_if := new(IR_If)
	result_if^ = IR_If {
		condition   = IR_Expr(tag_less),
		then_branch = true_lit,
		else_branch = IR_Expr(if_greater),
		type        = bool_type,
		span        = e.span,
	}
	return IR_Expr(result_if)
}

lower_tprefixop :: proc(e: ^semantics.TExpr_PrefixOp, env: ^Lower_Env) -> IR_Expr {
	operand_ir := lower_texpr(e.operand, env)

	#partial switch e.op {
	case .Kw_Not:
		false_lit := make_ir_lit_bool(false, e.type_, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp {
			op    = .Eq,
			left  = operand_ir,
			right = false_lit,
			type  = e.type_,
			span  = e.span,
		}
		return IR_Expr(binop)
	case .Minus:
		zero_lit := make_ir_lit_int(0, e.type_, e.span)
		binop := new(IR_BinOp)
		binop^ = IR_BinOp {
			op    = .Sub,
			left  = zero_lit,
			right = operand_ir,
			type  = e.type_,
			span  = e.span,
		}
		return IR_Expr(binop)
	case .Int_Literal,
	     .Float_Literal,
	     .String_Literal,
	     .Interpolated_String_Literal,
	     .Identifier,
	     .Upper_Id,
	     .Kw_If,
	     .Kw_Else,
	     .Kw_Match,
	     .Kw_Is,
	     .Kw_Derives,
	     .Kw_Handle,
	     .Kw_In,
	     .Kw_With,
	     .Kw_Import,
	     .Kw_As,
	     .Kw_For,
	     .Kw_And,
	     .Kw_Or,
	     .Kw_Expect,
	     .Kw_Test,
	     .Kw_Pub,
	     .Kw_Self,
	     .Kw_Par,
	     .Kw_Where,
	     .Pipe,
	     .Arrow,
	     .Fat_Arrow,
	     .Eq,
	     .Colon_Eq,
	     .Colon,
	     .Comma,
	     .Dot,
	     .Dot_Dot,
	     .Dollar,
	     .Hash,
	     .At,
	     .Lt,
	     .Gt,
	     .Lt_Eq,
	     .Gt_Eq,
	     .Eq_Eq,
	     .Bang_Eq,
	     .Plus,
	     .Star,
	     .Slash,
	     .Percent,
	     .Amp,
	     .Caret,
	     .Tilde,
	     .Backslash,
	     .LParen,
	     .RParen,
	     .LBrack,
	     .RBrack,
	     .LBrace,
	     .RBrace,
	     .Newline,
	     .Eof:
		return operand_ir
	}
	return operand_ir
}

// Flatten an open tag row into its full sequence of (name, payload) entries.
// Row unification stashes newly-introduced tags in the polymorphic tail
// (tag_rest), so the immediate tag_entries of a row var may not list every
// tag the scrutinee can actually take. Walk the rest until we hit an
// unlinked / non-row var.
flatten_tag_entries :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
	out: ^[dynamic]semantics.Type_Tag_Entry,
) {
	resolved := semantics.resolve_var(store, type_var)
	v := store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf do return
	#partial switch vi in inf {
	case semantics.Inferred_Newtype:
		flatten_tag_entries(store, vi.inner_id, out)
	case semantics.Inferred_Tag_Union_Row:
		for entry in vi.tag_entries {
			already := false
			for existing in out {
				if existing.name == entry.name {
					already = true
					break
				}
			}
			if !already do append(out, entry)
		}
		flatten_tag_entries(store, vi.tag_rest, out)
	}
}

resolve_tag_index :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
	tag_name: base.Intern_ID,
) -> int {
	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(store, type_var, &entries)
	for entry, i in entries {
		if entry.name == tag_name do return i
	}
	return 0
}

flatten_record_fields :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
	out: ^[dynamic]semantics.Type_Field_Entry,
) {
	resolved := semantics.resolve_var(store, type_var)
	v := store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf do return
	#partial switch vi in inf {
	case semantics.Inferred_Newtype:
		flatten_record_fields(store, vi.inner_id, out)
	case semantics.Inferred_Record_Row:
		for entry in vi.record_fields {
			already := false
			for existing in out {
				if existing.name == entry.name {
					already = true
					break
				}
			}
			if !already do append(out, entry)
		}
		flatten_record_fields(store, vi.record_rest, out)
	}
}

canonical_field_order :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
	allocator := context.allocator,
) -> []semantics.Type_Field_Entry {
	entries := make([dynamic]semantics.Type_Field_Entry, 0, 4, allocator)
	flatten_record_fields(store, type_var, &entries)
	// Canonical order = alphabetical by intern string so construct and access agree.
	for i in 1 ..< len(entries) {
		for j := i; j > 0; j -= 1 {
			a := base.intern_get(store.interner, entries[j].name)
			b := base.intern_get(store.interner, entries[j - 1].name)
			if a < b {
				entries[j], entries[j - 1] = entries[j - 1], entries[j]
			} else {
				break
			}
		}
	}
	return entries[:]
}

resolve_field_index :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
	field_name: base.Intern_ID,
) -> int {
	entries := canonical_field_order(store, type_var)
	defer delete(entries)
	for entry, i in entries {
		if entry.name == field_name do return i
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
	result^ = IR_Construct_Tag {
		tag_name   = e.name.name,
		tag_index  = tag_index,
		payload    = payload,
		reuse_addr = NO_REUSE_ADDR,
		type       = e.type_,
		span       = e.span,
	}
	return IR_Expr(result)
}

lower_trecord :: proc(e: ^semantics.TExpr_Record, env: ^Lower_Env) -> IR_Expr {
	// Lower all field values in literal order first, then reorder to canonical
	// (alphabetical by name) so construct/access agree on field_index offsets.
	lowered := make([dynamic]IR_Record_Field, 0, len(e.fields))
	defer delete(lowered)
	for f in e.fields {
		append(&lowered, IR_Record_Field{name = f.name, value = lower_texpr(f.value, env)})
	}
	canonical := canonical_field_order(env.store, e.type_.type_id)
	defer delete(canonical)
	fields := make([dynamic]IR_Record_Field, 0, len(lowered))
	for c in canonical {
		for lf in lowered {
			if lf.name == c.name {
				append(&fields, lf)
				break
			}
		}
	}
	if len(fields) != len(lowered) {
		// Type info incomplete (open row with no full info) — fall back to literal order.
		clear(&fields)
		for lf in lowered do append(&fields, lf)
	}
	rest := lower_texpr(e.rest, env)
	result := new(IR_Construct_Record)
	result^ = IR_Construct_Record {
		fields     = fields,
		rest       = rest,
		reuse_addr = NO_REUSE_ADDR,
		type       = e.type_,
		span       = e.span,
	}
	return IR_Expr(result)
}

lower_tfield_access :: proc(e: ^semantics.TExpr_Field_Access, env: ^Lower_Env) -> IR_Expr {
	record_ir := lower_texpr(e.record, env)
	record_type_id := texpr_type_id(e.record)
	idx := resolve_field_index(env.store, record_type_id, e.field)
	// Re-resolve type: later unifications (e.g. nested-access constraints)
	// may refine the field's wasm type after this TExpr was constructed.
	resolved_type := semantics.lower_type(env.store, e.type_.type_id)
	result := new(IR_Field_Access)
	result^ = IR_Field_Access {
		record      = record_ir,
		field       = e.field,
		field_index = idx,
		type        = resolved_type,
		span        = e.span,
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
	result^ = IR_Construct_Record {
		fields     = fields,
		rest       = rest_ir,
		reuse_addr = NO_REUSE_ADDR,
		type       = e.type_,
		span       = e.span,
	}
	return IR_Expr(result)
}

lower_tinterpolated_string :: proc(
	e: ^semantics.TExpr_Interpolated_String,
	env: ^Lower_Env,
) -> IR_Expr {
	if len(e.parts) == 0 {
		lit := new(IR_Literal_String)
		lit^ = IR_Literal_String {
			value = "",
			type  = e.type_,
			span  = e.span,
		}
		return IR_Expr(lit)
	}

	str_name_id := base.intern(env.interner, "Str")
	concat_name := base.intern(env.interner, "concat")

	lower_part :: proc(
		part: semantics.TExpr_String_Part,
		env: ^Lower_Env,
		str_type: base.IR_Type,
		span: base.Source_Span,
	) -> IR_Expr {
		#partial switch p in part {
		case ^semantics.TExpr_String_Literal:
			sid := fresh_ir_name(env)
			content := lower_string_content(p.value)
			lit := new(IR_Literal_String)
			lit^ = IR_Literal_String {
				id    = sid,
				value = content,
				type  = p.type_,
				span  = p.span,
			}
			append(&env.module.string_table, String_Table_Entry{id = sid, value = content})
			return IR_Expr(lit)
		case ^semantics.TExpr_String_Expr:
			inner := lower_texpr(p.expr, env)
			if p.needs_to_str {
				args := make([dynamic]IR_Expr, 0, 1)
				append(&args, inner)
				call := new(IR_Call)
				call^ = IR_Call {
					callee           = p.display_impl,
					args             = args,
					type             = str_type,
					span             = span,
					ord_compare_func = base.Canonical_Name{},
				}
				return IR_Expr(call)
			}
			return inner
		}
		return make_ir_lit_int(
			0,
			base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(-1)},
			base.Source_Span_ZERO,
		)
	}

	result := lower_part(e.parts[0], env, e.type_, e.span)
	for i := 1; i < len(e.parts); i += 1 {
		right := lower_part(e.parts[i], env, e.type_, e.span)
		args := make([dynamic]IR_Expr, 0, 2)
		append(&args, result)
		append(&args, right)
		call := new(IR_Call)
		call^ = IR_Call {
			callee = base.Canonical_Name{module = str_name_id, name = concat_name},
			args = args,
			type = e.type_,
			span = e.span,
			ord_compare_func = base.Canonical_Name{},
		}
		result = IR_Expr(call)
	}
	return result
}

lower_thandle :: proc(e: ^semantics.TExpr_Handle, env: ^Lower_Env) -> IR_Expr {
	body_ir := lower_texpr(e.body, env)
	arms := make([dynamic]IR_Handler_Arm, len(e.arms))
	for i in 0 ..< len(e.arms) {
		arms[i] = IR_Handler_Arm {
			op     = e.arms[i].op,
			params = e.arms[i].params,
			body   = lower_texpr(e.arms[i].body, env),
		}
	}
	result := new(IR_Handle)
	result^ = IR_Handle {
		effects = e.effects,
		body    = body_ir,
		arms    = arms,
		type    = e.type_,
		span    = e.span,
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
		nil_tag^ = IR_Construct_Tag {
			tag_name   = nil_name,
			tag_index  = nil_index,
			payload    = make([dynamic]IR_Expr, 0),
			reuse_addr = NO_REUSE_ADDR,
			type       = e.type_,
			span       = e.span,
		}
		result = IR_Expr(nil_tag)
	}

	for i := len(e.elements) - 1; i >= 0; i -= 1 {
		elem := lower_texpr(e.elements[i], env)
		cons_payload := make([dynamic]IR_Expr, 0, 2)
		append(&cons_payload, elem)
		append(&cons_payload, result)
		cons_tag := new(IR_Construct_Tag)
		cons_tag^ = IR_Construct_Tag {
			tag_name   = cons_name,
			tag_index  = cons_index,
			payload    = cons_payload,
			reuse_addr = NO_REUSE_ADDR,
			type       = e.type_,
			span       = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}
// is_list_tag_union returns true if the given type is a tag union with
// exactly Nil and Cons variants — the internal representation of List.
is_list_tag_union :: proc(
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
	type_id: base.Type_Var_ID,
) -> bool {
	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(store, type_id, &entries)
	if len(entries) != 2 {
		return false
	}
	nil_name := base.intern(interner, "Nil")
	cons_name := base.intern(interner, "Cons")
	has_nil := entries[0].name == nil_name || entries[1].name == nil_name
	has_cons := entries[0].name == cons_name || entries[1].name == cons_name
	return has_nil && has_cons
}

// lower_container_eq_from_type generates a recursive list-equality function
// and returns an IR_Call to it.  The generated function uses IR_Match on the
// Cons/Nil structure, IR_BinOp(Eq) for element comparison (correct for all
// inline types), and a recursive self-call for tails (correct for any length).
lower_container_eq_from_type :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	container_name: string,
	type_id: base.Type_Var_ID,
	param_index: int,
) -> IR_Expr {
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}

	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)

	nil_name := base.intern(env.interner, "Nil")
	cons_name := base.intern(env.interner, "Cons")
	nil_index := resolve_tag_index(env.store, type_id, nil_name)
	cons_index := resolve_tag_index(env.store, type_id, cons_name)

	entries: [dynamic]semantics.Type_Tag_Entry
	entries = make([dynamic]semantics.Type_Tag_Entry, 0, 4)
	defer delete(entries)
	flatten_tag_entries(env.store, type_id, &entries)

	// Find Cons entry to determine element type and field count
	cons_payload_types: []base.Type_Var_ID
	for entry in entries {
		if entry.name == cons_name {
			cons_payload_types = entry.payload
			break
		}
	}

	// --- Build inline list comparison: ---
	// match left {
	//   Nil  => match right { Nil => true, Cons(_, _) => false }
	//   Cons(head_l, tail_l) => match right {
	//     Nil => false
	//     Cons(head_r, tail_r) => (head_l == head_r) && (tail_l == tail_r)
	//   }
	// }
	// The tail comparison is recursive (calls lower_container_eq_from_type
	// again), but each recursive call peels off one Cons layer, so it
	// terminates when we hit Nil.  In practice this only works for lists
	// whose length is known at compile time (literal lists).  For
	// dynamically-sized lists, the expansion would be infinite.
	//
	// To handle dynamic-length lists properly, we'd need to generate a
	// named function with a self-recursive call.  For now, we cap the
	// expansion depth and fall back to pointer comparison beyond that.

	max_depth :: 8 // max compile-time unrolling depth

	inner :: proc(
		left: IR_Expr,
		right: IR_Expr,
		env: ^Lower_Env,
		type_id: base.Type_Var_ID,
		cons_payload_types: []base.Type_Var_ID,
		nil_index: int,
		cons_index: int,
		depth: int,
	) -> IR_Expr {
		bool_type_inner := base.IR_Type {
			wasm_type = .I32,
			type_id   = 0,
		}

		// Exceeded depth — fall back to pointer comparison
		if depth >= max_depth {
			ptr_eq := new(IR_BinOp)
			ptr_eq^ = IR_BinOp {
				op    = .Eq,
				left  = left,
				right = right,
				type  = bool_type_inner,
				span  = base.Source_Span_ZERO,
			}
			return IR_Expr(ptr_eq)
		}

		// Helper to load just the tag byte (IR_I32_Load reads 4 bytes, but
		// the tag is only 1 byte — we AND with 0xFF to mask off extra bytes).
		load_tag_byte :: proc(ptr: IR_Expr) -> IR_Expr {
			i32t := base.IR_Type {
				wasm_type = .I32,
				type_id   = 0,
			}
			load := new(IR_I32_Load)
			load^ = IR_I32_Load {
				base   = ptr,
				offset = 4,
				span   = base.Source_Span_ZERO,
			}
			mask := new(IR_BinOp)
			mask^ = IR_BinOp {
				op    = .And,
				left  = IR_Expr(load),
				right = make_ir_lit_int(0xFF, i32t, base.Source_Span_ZERO),
				type  = i32t,
				span  = base.Source_Span_ZERO,
			}
			return IR_Expr(mask)
		}

		// --- Nil arm of left ---
		// match right { Nil => true, Cons(_, _) => false }
		is_right_nil := new(IR_BinOp)
		is_right_nil^ = IR_BinOp {
			op    = .Eq,
			left  = load_tag_byte(right),
			right = make_ir_lit_int(i64(nil_index), bool_type_inner, base.Source_Span_ZERO),
			type  = bool_type_inner,
			span  = base.Source_Span_ZERO,
		}
		// Nil arm body: if right is Nil → true, else → false
		nil_arm_body := is_right_nil // 1 if right is Nil, 0 if Cons

		// --- Cons arm of left ---
		// Cons(head_l, tail_l)
		// Note: IR_Field_Access always loads i32 in codegen, so we use i32 type
		// for field access to avoid type mismatches. This is correct for i32-sized
		// types (Bool, I32, pointers). For I64/F64 fields, only the lower 32 bits
		// are compared — a known limitation shared with structural tag union Eq.
		i32_field_type := base.IR_Type {
			wasm_type = .I32,
			type_id   = 0,
		}

		head_l := new(IR_Field_Access)
		head_l^ = IR_Field_Access {
			record      = left,
			field_index = 0,
			type        = i32_field_type,
			span        = base.Source_Span_ZERO,
		}
		tail_l := new(IR_Field_Access)
		tail_l^ = IR_Field_Access {
			record      = left,
			field_index = 1,
			type        = i32_field_type,
			span        = base.Source_Span_ZERO,
		}

		// match right { Nil => false, Cons(head_r, tail_r) => ... }
		is_right_cons := new(IR_BinOp)
		is_right_cons^ = IR_BinOp {
			op    = .Eq,
			left  = load_tag_byte(right),
			right = make_ir_lit_int(i64(cons_index), bool_type_inner, base.Source_Span_ZERO),
			type  = bool_type_inner,
			span  = base.Source_Span_ZERO,
		}

		head_r := new(IR_Field_Access)
		head_r^ = IR_Field_Access {
			record      = right,
			field_index = 0,
			type        = i32_field_type,
			span        = base.Source_Span_ZERO,
		}
		tail_r := new(IR_Field_Access)
		tail_r^ = IR_Field_Access {
			record      = right,
			field_index = 1,
			type        = i32_field_type,
			span        = base.Source_Span_ZERO,
		}

		// head comparison
		head_eq := new(IR_BinOp)
		head_eq^ = IR_BinOp {
			op    = .Eq,
			left  = IR_Expr(head_l),
			right = IR_Expr(head_r),
			type  = bool_type_inner,
			span  = base.Source_Span_ZERO,
		}

		// tail comparison (recursive)
		tail_eq := inner(
			IR_Expr(tail_l),
			IR_Expr(tail_r),
			env,
			type_id,
			cons_payload_types,
			nil_index,
			cons_index,
			depth + 1,
		)

		// Cons arm body: if right is Cons → head_eq && tail_eq, else → false
		both := new(IR_BinOp)
		both^ = IR_BinOp {
			op    = .And,
			left  = IR_Expr(head_eq),
			right = tail_eq,
			type  = bool_type_inner,
			span  = base.Source_Span_ZERO,
		}
		cons_if := new(IR_If)
		cons_if^ = IR_If {
			condition   = IR_Expr(is_right_cons),
			then_branch = IR_Expr(both),
			else_branch = make_ir_lit_bool(false, bool_type_inner, base.Source_Span_ZERO),
			type        = bool_type_inner,
			span        = base.Source_Span_ZERO,
		}

		// Outer: if left is Nil → nil_arm_body, else → cons_if
		is_left_nil := new(IR_BinOp)
		is_left_nil^ = IR_BinOp {
			op    = .Eq,
			left  = load_tag_byte(left),
			right = make_ir_lit_int(i64(nil_index), bool_type_inner, base.Source_Span_ZERO),
			type  = bool_type_inner,
			span  = base.Source_Span_ZERO,
		}
		outer := new(IR_If)
		outer^ = IR_If {
			condition   = IR_Expr(is_left_nil),
			then_branch = IR_Expr(nil_arm_body),
			else_branch = IR_Expr(cons_if),
			type        = bool_type_inner,
			span        = base.Source_Span_ZERO,
		}
		return IR_Expr(outer)
	}

	result := inner(left_ir, right_ir, env, type_id, cons_payload_types, nil_index, cons_index, 0)
	if e.op == .Bang_Eq {
		return wrap_not(result, e)
	}
	return result
}

// lower_container_eq generates an IR_Call to a container's eq intrinsic
// (e.g., List.eq) with the element type's Eq trait method resolved as a callback.
// param_index selects which type parameter to use for the element (0 for List/Set,
// 0 for Map keys, 1 for Map values — Map is handled separately for now).
lower_container_eq :: proc(
	e: ^semantics.TExpr_BinOp,
	env: ^Lower_Env,
	container_name: string,
	nt: semantics.Inferred_Newtype,
	param_index: int,
) -> IR_Expr {
	bool_type := base.IR_Type {
		wasm_type = .I32,
		type_id   = 0,
	}

	// Resolve element type from container's type parameters
	if param_index >= len(nt.param_ids) {
		return make_ir_lit_bool(false, bool_type, e.span)
	}
	elem_type_id := nt.param_ids[param_index]

	// Resolve element's Eq.eq trait method
	eq_method, _ := resolve_trait_method(env.store, env.interner, elem_type_id, "Eq", "eq")

	// Generate IR_Call to e.g. List.eq(left, right)
	mod_name := base.intern(env.interner, container_name)
	eq_name := base.intern(env.interner, "eq")
	left_ir := lower_texpr(e.left, env)
	right_ir := lower_texpr(e.right, env)
	args := make([dynamic]IR_Expr, 0, 2)
	append(&args, left_ir)
	append(&args, right_ir)
	call := new(IR_Call)
	call^ = IR_Call {
		callee = base.Canonical_Name{module = mod_name, name = eq_name},
		args = args,
		type = e.type_,
		span = e.span,
		ord_compare_func = eq_method,
	}
	result := IR_Expr(call)
	if e.op == .Bang_Eq {
		return wrap_not(result, e)
	}
	return result
}

// --- Generic trait dispatch resolution ---
//
// These helpers resolve trait method implementations at IR lowering time,
// when full type info from the typechecker is still available.
// They are generic over trait name and method name, so they can serve
// Ord (Map/Set keys), Hash (future HashMap), Eq, or any other trait
// whose method needs to be passed as a runtime callback.

// resolve_type_name returns the Intern_ID for the "spine" name of a type
// (e.g. "I64", "Str", "MyNewtype"). Returns (name, true) on success.
resolve_type_name :: proc(
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
	type_id: base.Type_Var_ID,
) -> (
	base.Intern_ID,
	bool,
) {
	resolved := semantics.resolve_var(store, type_id)
	inf, is_inf := store.vars[int(resolved)].link.(semantics.Inferred_Type)
	if !is_inf {
		return base.Intern_ID(0), false
	}

	#partial switch f in inf {
	case semantics.Inferred_Primitive:
		return f.primitive_name, true
	case semantics.Inferred_Newtype:
		return f.primitive_name, true
	case semantics.Inferred_Constructor:
		return f.primitive_name, true
	case:
		return base.Intern_ID(0), false
	}
}

// resolve_trait_method looks up a trait implementation for a given type and
// returns the Canonical_Name of the resolved method. Returns (name, true) on success.
resolve_trait_method :: proc(
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
	type_id: base.Type_Var_ID,
	trait_name: string,
	method_name: string,
) -> (
	base.Canonical_Name,
	bool,
) {
	type_name, ok := resolve_type_name(store, interner, type_id)
	if !ok {
		return base.Canonical_Name{}, false
	}

	trait_id := base.intern(interner, trait_name)
	impl, found := semantics.find_trait_impl(store, trait_id, type_name)
	if !found {
		return base.Canonical_Name{}, false
	}

	method_id := base.intern(interner, method_name)
	func_name, has_method := impl.methods[method_id]
	if !has_method {
		return base.Canonical_Name{}, false
	}

	return func_name, true
}

// extract_container_element_type walks the type of a typed expression
// looking for a parameterized container (Map, Set, List) and returns
// the type var for the element at param_index (0 = first type param).
// For List, this is the element type. For Map, 0=key, 1=value.
// For Set, 0=element.
extract_container_element_type :: proc(
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
	arg: semantics.TExpr,
	container_name: string,
	param_index: int,
) -> (
	base.Type_Var_ID,
	bool,
) {
	arg_type_id := texpr_type_id(arg)
	resolved := semantics.resolve_var(store, arg_type_id)
	inf, is_inf := store.vars[int(resolved)].link.(semantics.Inferred_Type)
	if !is_inf {
		return base.Type_Var_ID(0), false
	}

	nt, nt_ok := inf.(semantics.Inferred_Newtype)
	if !nt_ok {
		return base.Type_Var_ID(0), false
	}

	nt_name := base.intern_get(interner, nt.primitive_name)
	if nt_name != container_name {
		return base.Type_Var_ID(0), false
	}

	if param_index >= len(nt.param_ids) {
		return base.Type_Var_ID(0), false
	}

	return nt.param_ids[param_index], true
}

// extract_tuple_element_type resolves a type var to an Inferred_Tuple
// and returns the type var for the element at the given index.
extract_tuple_element_type :: proc(
	store: ^semantics.Type_Store,
	type_id: base.Type_Var_ID,
	element_index: int,
) -> (
	base.Type_Var_ID,
	bool,
) {
	resolved := semantics.resolve_var(store, type_id)
	inf, is_inf := store.vars[int(resolved)].link.(semantics.Inferred_Type)
	if !is_inf {
		return base.Type_Var_ID(0), false
	}

	tup, tup_ok := inf.(semantics.Inferred_Tuple)
	if !tup_ok {
		return base.Type_Var_ID(0), false
	}

	if element_index >= len(tup.element_types) {
		return base.Type_Var_ID(0), false
	}

	return tup.element_types[element_index], true
}

// intrinsic_needs_trait returns true if a Map/Set intrinsic call requires
// a trait dispatch (currently Ord for ordered tree operations).
intrinsic_needs_trait :: proc(callee: base.Canonical_Name, interner: ^base.Intern_Table) -> bool {
	module_str := base.intern_get(interner, callee.module)
	if module_str != "Map" && module_str != "Set" {
		return false
	}

	name_str := base.intern_get(interner, callee.name)

	// Functions that don't need Ord (pure structural / traversal)
	switch name_str {
	case "new", "size", "is_empty", "min", "max", "fold", "to_iter", "keys", "values", "to_list":
		return false
	}

	return true
}

// resolve_ord_compare resolves the Ord.compare method for the key type
// of a Map/Set intrinsic call. Returns a zero-value Canonical_Name if
// resolution fails (no Ord impl, or call doesn't need one).
resolve_ord_compare :: proc(
	callee: base.Canonical_Name,
	args: [dynamic]semantics.TExpr,
	env: ^Lower_Env,
) -> base.Canonical_Name {
	if !intrinsic_needs_trait(callee, env.interner) {
		return base.Canonical_Name{}
	}

	module_str := base.intern_get(env.interner, callee.module)
	name_str := base.intern_get(env.interner, callee.name)

	key_type_id: base.Type_Var_ID

	if name_str == "from_list" {
		// from_list(list) — List element type carries the key.
		// Set.from_list: List(k) → k is the key directly.
		// Map.from_list: List((k, v)) → k is the first tuple element.
		if len(args) == 0 {
			return base.Canonical_Name{}
		}
		elem_type, ok := extract_container_element_type(
			env.store,
			env.interner,
			args[0],
			"List",
			0,
		)
		if !ok {
			return base.Canonical_Name{}
		}
		if module_str == "Set" {
			key_type_id = elem_type
		} else {
			key, ok := extract_tuple_element_type(env.store, elem_type, 0)
			if !ok {
				return base.Canonical_Name{}
			}
			key_type_id = key
		}
	} else {
		// For all other Map/Set functions, find the container argument
		// and extract the key type from its first type parameter.
		container_name_primary: string
		container_name_secondary: string
		if module_str == "Map" {
			container_name_primary = "Map"
			container_name_secondary = "Set"
		} else {
			container_name_primary = "Set"
			container_name_secondary = "Map"
		}
		for i in 0 ..< len(args) {
			elem, ok := extract_container_element_type(
				env.store,
				env.interner,
				args[i],
				container_name_primary,
				0,
			)
			if ok {
				key_type_id = elem
				break
			}
			elem, ok = extract_container_element_type(
				env.store,
				env.interner,
				args[i],
				container_name_secondary,
				0,
			)
			if ok {
				key_type_id = elem
				break
			}
		}
	}

	if key_type_id == base.Type_Var_ID(0) {
		return base.Canonical_Name{}
	}

	func_name, ok := resolve_trait_method(env.store, env.interner, key_type_id, "Ord", "compare")
	if !ok {
		return base.Canonical_Name{}
	}

	return func_name
}


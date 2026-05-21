package camp

annotate_file :: proc(cfile: CFile, store: ^Type_Store) -> TFile {
	result: TFile
	result.path = cfile.path
	result.span = cfile.span
	result.decls = make([dynamic]TDecl, 0, len(cfile.decls))
	result.imports = cfile.imports

	env: Annotate_Env
	env.store = store
	env.interner = store.interner

	for decl in cfile.decls {
		annotated := annotate_decl(decl, &env)
		append(&result.decls, annotated)
	}

	return result
}

Annotate_Env :: struct {
	store:     ^Type_Store,
	interner:  ^Intern_Table,
}

annotate_decl :: proc(decl: CDecl, env: ^Annotate_Env) -> TDecl {
	switch d in decl {
	case ^CDecl_Const:
		return annotate_decl_const(d, env)
	case ^CDecl_Effect:
		return annotate_decl_effect(d, env)
	case ^CDecl_Trait:
		return annotate_decl_trait(d, env)
	case ^CDecl_Alias:
		return annotate_decl_alias(d, env)
	case ^CDecl_Newtype:
		return annotate_decl_newtype(d, env)
	case ^CDecl_Import:
		result := new(TDecl_Import)
		result.deferred = d.deferred
		result.span = d.span
		return TDecl(result)
	case ^CDecl_Test:
		return annotate_decl_test(d, env)
	case ^CDecl_Expect:
		return annotate_decl_expect(d, env)
	}
	unreachable()
}

annotate_decl_const :: proc(d: ^CDecl_Const, env: ^Annotate_Env) -> TDecl {
	body_t := annotate_expr(d.body, env)
	type_ir := lower_type(env.store, env.store.bindings[d.name.name])
	eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, d.span))

	result := new(TDecl_Const)
	result.name = d.name
	result.is_pub = d.is_pub
	result.is_effectful = d.is_effectful
	result.type_ann = d.type_ann
	result.body = body_t
	result.type_ = type_ir
	result.eff_ = eff_ir
	result.derive_targets = d.derive_targets
	result.span = d.span

	return TDecl(result)
}

annotate_decl_effect :: proc(d: ^CDecl_Effect, env: ^Annotate_Env) -> TDecl {
	result := new(TDecl_Effect)
	result.name = d.name
	result.is_pub = d.is_pub
	result.operations = make([dynamic]TEffect_Op, len(d.operations))

	for i in 0..<len(d.operations) {
		op := d.operations[i]
		top := TEffect_Op{
			name = op.name,
			is_effectful = op.is_effectful,
			params = make([dynamic]TFunc_Param, len(op.params)),
			span = op.span,
		}
		for j in 0..<len(op.params) {
			p := op.params[j]
			type_ir := lower_type(env.store, env.store.bindings[p.name])
			eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, p.span))
			top.params[j] = TFunc_Param{
				name = p.name,
				type_ = type_ir,
				eff_ = eff_ir,
				span = p.span,
			}
		}
		if op.return_type != nil {
			top.return_type = lower_type(env.store, fresh_value_var(env.store, op.span))
		}
		if op.return_effects != nil {
			top.return_effects = lower_effect_type(env.store, fresh_effect_row(env.store, op.span))
		}
		result.operations[i] = top
	}

	return TDecl(result)
}

annotate_decl_trait :: proc(d: ^CDecl_Trait, env: ^Annotate_Env) -> TDecl {
	result := new(TDecl_Trait)
	result.name = d.name
	result.is_pub = d.is_pub
	result.parent = d.parent
	result.span = d.span
	result.methods = make([dynamic]TTrait_Method, len(d.methods))

	for i in 0..<len(d.methods) {
		m := d.methods[i]
		tm := TTrait_Method{
			name = m.name,
			params = make([dynamic]TFunc_Param, len(m.params)),
			span = m.span,
		}
		for j in 0..<len(m.params) {
			p := m.params[j]
			type_ir := lower_type(env.store, fresh_value_var(env.store, p.span))
			eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, p.span))
			tm.params[j] = TFunc_Param{
				name = p.name,
				type_ = type_ir,
				eff_ = eff_ir,
				span = p.span,
			}
		}
		if m.return_type != nil {
			tm.return_type = lower_type(env.store, fresh_value_var(env.store, m.span))
		}
		tm.effects = lower_effect_type(env.store, fresh_effect_row(env.store, m.span))
		result.methods[i] = tm
	}

	return TDecl(result)
}

annotate_decl_alias :: proc(d: ^CDecl_Alias, env: ^Annotate_Env) -> TDecl {
	result := new(TDecl_Alias)
	result.name = d.name
	result.is_pub = d.is_pub
	result.target = d.target
	result.span = d.span
	return TDecl(result)
}

annotate_decl_newtype :: proc(d: ^CDecl_Newtype, env: ^Annotate_Env) -> TDecl {
	type_ir := lower_type(env.store, env.store.bindings[d.name.name])

	result := new(TDecl_Newtype)
	result.name = d.name
	result.is_pub = d.is_pub
	result.type_params = d.type_params
	result.trait_conforms = d.trait_conforms
	result.inner_type = d.inner_type
	result.type_ = type_ir
	result.derive_targets = d.derive_targets
	result.span = d.span

	return TDecl(result)
}

annotate_decl_test :: proc(d: ^CDecl_Test, env: ^Annotate_Env) -> TDecl {
	result := new(TDecl_Test)
	result.name = d.name
	result.body = annotate_expr(d.body, env)
	result.span = d.span
	return TDecl(result)
}

annotate_decl_expect :: proc(d: ^CDecl_Expect, env: ^Annotate_Env) -> TDecl {
	result := new(TDecl_Expect)
	result.condition = annotate_expr(d.condition, env)
	result.span = d.span
	return TDecl(result)
}

annotate_expr :: proc(expr: CExpr, env: ^Annotate_Env) -> TExpr {
	switch e in expr {
	case ^CExpr_Int:
		type_ir := lower_type(env.store, env.store.bindings[intern(env.interner, "I64")])
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		return TExpr(new(TExpr_Int))

	case ^CExpr_Float:
		type_ir := lower_type(env.store, env.store.bindings[intern(env.interner, "F64")])
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		return TExpr(new(TExpr_Float))

	case ^CExpr_String:
		type_ir := lower_type(env.store, env.store.bindings[intern(env.interner, "Str")])
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		return TExpr(new(TExpr_String))

	case ^CExpr_Bool:
		type_ir := lower_type(env.store, env.store.bindings[intern(env.interner, "Bool")])
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		return TExpr(new(TExpr_Bool))

	case ^CExpr_Tag:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		payload_t := make([dynamic]TExpr, len(e.payload))
		for i in 0..<len(e.payload) {
			payload_t[i] = annotate_expr(e.payload[i], env)
		}
		result := new(TExpr_Tag)
		result.name = e.name
		result.payload = payload_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Record:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		fields_t := make([dynamic]TRecord_Field, len(e.fields))
		for i in 0..<len(e.fields) {
			fields_t[i] = TRecord_Field{
				name = e.fields[i].name,
				value = annotate_expr(e.fields[i].value, env),
				span = e.fields[i].span,
			}
		}
		result := new(TExpr_Record)
		result.fields = fields_t
		result.rest = annotate_expr(e.rest, env)
		result.is_open = e.is_open
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_List:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		elements_t := make([dynamic]TExpr, len(e.elements))
		for i in 0..<len(e.elements) {
			elements_t[i] = annotate_expr(e.elements[i], env)
		}
		result := new(TExpr_List)
		result.elements = elements_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Name:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Name)
		result.name = e.name
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Call:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		args_t := make([dynamic]TExpr, len(e.args))
		for i in 0..<len(e.args) {
			args_t[i] = annotate_expr(e.args[i], env)
		}
		result := new(TExpr_Call)
		result.callee = annotate_expr(e.callee, env)
		result.args = args_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Method_Call:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		args_t := make([dynamic]TExpr, len(e.args))
		for i in 0..<len(e.args) {
			args_t[i] = annotate_expr(e.args[i], env)
		}
		result := new(TExpr_Method_Call)
		result.receiver = annotate_expr(e.receiver, env)
		result.method = e.method
		result.args = args_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Lambda:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		params_t := make([dynamic]TFunc_Param, len(e.params))
		for i in 0..<len(e.params) {
			p := e.params[i]
			type_ir := lower_type(env.store, fresh_value_var(env.store, p.span))
			eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, p.span))
			params_t[i] = TFunc_Param{
				name = p.name,
				type_ = type_ir,
				eff_ = eff_ir,
				span = p.span,
			}
		}
		return_type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		effects_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Lambda)
		result.type_params = e.type_params
		result.params = params_t
		result.return_type = return_type_ir
		result.effects = effects_ir
		result.body = annotate_expr(e.body, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Block:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		statements_t := make([dynamic]TExpr, len(e.statements))
		for i in 0..<len(e.statements) {
			statements_t[i] = annotate_expr(e.statements[i], env)
		}
		result := new(TExpr_Block)
		result.statements = statements_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_If:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_If)
		result.condition = annotate_expr(e.condition, env)
		result.then_branch = annotate_expr(e.then_branch, env)
		result.else_branch = annotate_expr(e.else_branch, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Match:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		arms_t := make([dynamic]TMatch_Arm, len(e.arms))
		for i in 0..<len(e.arms) {
			arms_t[i] = TMatch_Arm{
				pattern = annotate_pattern(e.arms[i].pattern),
				body = annotate_expr(e.arms[i].body, env),
				span = e.arms[i].span,
			}
		}
		result := new(TExpr_Match)
		result.scrutinee = annotate_expr(e.scrutinee, env)
		result.arms = arms_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_BinOp:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_BinOp)
		result.op = e.op
		result.left = annotate_expr(e.left, env)
		result.right = annotate_expr(e.right, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_PrefixOp:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_PrefixOp)
		result.op = e.op
		result.operand = annotate_expr(e.operand, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Field_Access:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Field_Access)
		result.record = annotate_expr(e.record, env)
		result.field = e.field
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Record_Update:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		updates_t := make([dynamic]TRecord_Field, len(e.updates))
		for i in 0..<len(e.updates) {
			updates_t[i] = TRecord_Field{
				name = e.updates[i].name,
				value = annotate_expr(e.updates[i].value, env),
				span = e.updates[i].span,
			}
		}
		result := new(TExpr_Record_Update)
		result.rest = annotate_expr(e.rest, env)
		result.updates = updates_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Assign:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Assign)
		result.target = annotate_expr(e.target, env)
		result.value = annotate_expr(e.value, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Return:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Return)
		result.value = annotate_expr(e.value, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Crash:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		result := new(TExpr_Crash)
		result.message = annotate_expr(e.message, env)
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Interpolate:
		type_ir := lower_type(env.store, env.store.bindings[intern(env.interner, "Str")])
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		parts_t := make([dynamic]TExpr, len(e.parts))
		for i in 0..<len(e.parts) {
			parts_t[i] = annotate_expr(e.parts[i], env)
		}
		result := new(TExpr_Interpolate)
		result.parts = parts_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)

	case ^CExpr_Handle:
		type_ir := lower_type(env.store, fresh_value_var(env.store, e.span))
		eff_ir := lower_effect_type(env.store, fresh_effect_row(env.store, e.span))
		arms_t := make([dynamic]THandler_Arm, len(e.arms))
		for i in 0..<len(e.arms) {
			arms_t[i] = THandler_Arm{
				op = e.arms[i].op,
				resume_id = e.arms[i].resume_id,
				body = annotate_expr(e.arms[i].body, env),
				span = e.arms[i].span,
			}
		}
		result := new(TExpr_Handle)
		result.effect = e.effect
		result.is_shallow = e.is_shallow
		result.is_non_resuming = e.is_non_resuming
		result.body = annotate_expr(e.body, env)
		result.arms = arms_t
		result.type_ = type_ir
		result.eff_ = eff_ir
		result.span = e.span
		return TExpr(result)
	}

	unreachable()
}

annotate_pattern :: proc(pattern: CPattern) -> TPattern {
	switch p in pattern {
	case ^CPattern_Tag:
		payload_t := make([dynamic]TPattern, len(p.payload))
		for i in 0..<len(p.payload) {
			payload_t[i] = annotate_pattern(p.payload[i])
		}
		result := new(TPattern_Tag)
		result.name = p.name
		result.payload = payload_t
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Record:
		fields_t := make([dynamic]TPattern_Field, len(p.fields))
		for i in 0..<len(p.fields) {
			fields_t[i] = TPattern_Field{
				name = p.fields[i].name,
				binding = p.fields[i].binding,
				span = p.fields[i].span,
			}
		}
		result := new(TPattern_Record)
		result.fields = fields_t
		result.is_open = p.is_open
		result.span = p.span
		return TPattern(result)

	case ^CPattern_List:
		elements_t := make([dynamic]TPattern, len(p.elements))
		for i in 0..<len(p.elements) {
			elements_t[i] = annotate_pattern(p.elements[i])
		}
		result := new(TPattern_List)
		result.elements = elements_t
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Int:
		result := new(TPattern_Int)
		result.value = p.value
		result.span = p.span
		return TPattern(result)

	case ^CPattern_String:
		result := new(TPattern_String)
		result.value = p.value
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Bool:
		result := new(TPattern_Bool)
		result.value = p.value
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Identifier:
		result := new(TPattern_Identifier)
		result.name = p.name
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Wildcard:
		result := new(TPattern_Wildcard)
		result.span = p.span
		return TPattern(result)

	case ^CPattern_Destructure:
		result := new(TPattern_Destructure)
		result.type_name = p.type_name
		result.inner = annotate_pattern(p.inner)
		result.span = p.span
		return TPattern(result)
	}

	unreachable()
}

lower_effect_type :: proc(store: ^Type_Store, eff_var: Type_Var_ID) -> IR_Type {
	resolved := resolve_var(store, eff_var)
	v := get_var(store, resolved)
	if inf, is_inf := v.link.(Inferred_Type); is_inf && inf.tag == .Effect_Row {
		return IR_Type{wasm_type = .Void, type_id = resolved}
	}
	return IR_Type{wasm_type = .Void, type_id = eff_var}
}
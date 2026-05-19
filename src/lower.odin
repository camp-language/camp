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
		case ^CDecl_Const:
			ir_decl := lower_decl_const(d^, &env)
			append(&mod.decls, ir_decl)
		case ^CDecl_Effect:
			ir_decl := lower_decl_effect(d^, &env)
			append(&mod.decls, ir_decl)
			eff_def := lower_effect_def(d^, &env)
			append(&mod.effect_defs, eff_def)
		case:
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
		}
	}

	return IR_Type{wasm_type = wasm_type, type_id = resolved}
}

fresh_ir_name :: proc(env: ^Lower_Env) -> Intern_ID {
	name := fmt.tprintf("_ir_{}", env.fresh_counter)
	env.fresh_counter += 1
	return intern(env.interner, name)
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

	fn_decl := new(IR_Decl_Fn)
	fn_decl^ = IR_Decl_Fn{
		name = name,
		is_effectful = is_effectful,
		params = params,
		return_type = ir_ret_type,
		effect_row = IR_Type{.Void, fresh_effect_row(env.store, span)},
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
	return IR_Effect_Def{name = d.name, operations = ops}
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
		callee_expr := lower_expr(c, env)
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

lower_method_call :: proc(e: ^CExpr_Method_Call, env: ^Lower_Env) -> IR_Expr {
	receiver := lower_expr(e.receiver, env)

	ir_args := make([dynamic]IR_Expr, 0, len(e.args))
	for arg in e.args {
		append(&ir_args, lower_expr(arg, env))
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
		body = body,
		span = e.span,
	}
	append(&env.pending_decls, IR_Decl(fn_decl))

	closure := new(IR_Closure)
	closure^ = IR_Closure{
		fn_name = fn_name,
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

	stmts := make([dynamic]IR_Expr, 0, len(e.statements))
	for stmt in e.statements {
		append(&stmts, lower_expr(stmt, env))
	}

	type_var := fresh_value_var(env.store, e.span)
	block := new(IR_Block)
	block^ = IR_Block{statements = stmts, type = lower_type(env.store, type_var), span = e.span}
	return IR_Expr(block)
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
	payload := make([dynamic]IR_Expr, 0, len(e.payload))
	for p in e.payload {
		append(&payload, lower_expr(p, env))
	}

	type_var := fresh_value_var(env.store, e.span)
	tag := new(IR_Construct_Tag)
	tag^ = IR_Construct_Tag{
		tag_name = e.name.name,
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
			resume_id = arm.resume_id,
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
			payload = cons_payload,
			type = ir_type,
			span = e.span,
		}
		result = IR_Expr(cons_tag)
	}
	return result
}

package camp

import "core:fmt"
import "core:slice"

DOT_RECEIVER_NAME :: "__dot_receiver__"
DOT_RECEIVER_INTERN_ID : Intern_ID = 0
dot_lambda_counter : int = 0

Canonicalize_Scope :: struct {
	local_names: map[Intern_ID]Canonical_Name,
}

canonicalize :: proc(surface: File, ctx: ^Compilation_Context) -> CFile {
	DOT_RECEIVER_INTERN_ID = intern(&ctx.interner, DOT_RECEIVER_NAME)

	scope: Canonicalize_Scope
	scope.local_names = make(map[Intern_ID]Canonical_Name, 64)
	defer delete(scope.local_names)

	cfile: CFile
	cfile.path = surface.path
	cfile.decls = make([dynamic]CDecl, 0, len(surface.decls))
	cfile.imports = make([dynamic]Deferred_Import, 0, 8)
	cfile.spans = make(Span_Table, 64)
	ctx.spans = cfile.spans

	for decl in surface.decls {
		cdecl := canonicalize_decl(decl, &scope, &cfile.imports, ctx)
		append(&cfile.decls, cdecl)
	}

	return cfile
}

canonicalize_decl :: proc(decl: Decl, scope: ^Canonicalize_Scope, imports: ^[dynamic]Deferred_Import, ctx: ^Compilation_Context) -> CDecl {
	#partial switch d in decl {
	case ^Decl_Const:
		name := canonicalize_local_name(d.name, scope)
		cbody := canonicalize_expr(d.body, scope, ctx)
		ctype_ann: ^CType = nil
		if d.type_ann != nil {
			ctype_ann = canonicalize_type(d.type_ann^, scope, ctx)
		}
		cdecl := new(CDecl_Const)
		cdecl^ = CDecl_Const{
			name = name,
			is_pub = d.is_pub,
			is_effectful = d.is_effectful,
			type_ann = ctype_ann,
			body = cbody,
			derive_targets = make([dynamic]Intern_ID, 0, 4),
		}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Effect:
		name := canonicalize_local_name(d.name, scope)
		ops := make([dynamic]CEffect_Op, 0, len(d.operations))
		for op in d.operations {
			append(&ops, canonicalize_effect_op(op, scope, ctx))
		}
		cdecl := new(CDecl_Effect)
		cdecl^ = CDecl_Effect{
			name = name,
			is_pub = d.is_pub,
			operations = ops,
		}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Trait:
		name := canonicalize_local_name(d.name, scope)
		methods := make([dynamic]CTrait_Method, 0, len(d.methods))
		for m in d.methods {
			append(&methods, canonicalize_trait_method(m, scope, ctx))
		}
		cdecl := new(CDecl_Trait)
		cdecl^ = CDecl_Trait{
			name = name,
			is_pub = d.is_pub,
			parent = d.parent,
			methods = methods,
		}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Alias:
		name := canonicalize_local_name(d.name, scope)
		ctarget := canonicalize_type(d.target^, scope, ctx)
		cdecl := new(CDecl_Alias)
		cdecl^ = CDecl_Alias{
			name = name,
			is_pub = d.is_pub,
			target = ctarget,
		}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Import:
		di := Deferred_Import{
			module = intern(&ctx.interner, d.module),
			exposing = make([dynamic]Intern_ID, len(d.exposing)),
			alias = d.alias,
			is_unsafe = d.is_unsafe,
			span = d.span,
		}
		for i, name in d.exposing {
			di.exposing[i] = Intern_ID(name)
		}
		append(imports, di)
		cdecl := new(CDecl_Import)
		cdecl^ = CDecl_Import{deferred = di}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Test:
		cbody := canonicalize_expr(d.body, scope, ctx)
		cdecl := new(CDecl_Test)
		cdecl^ = CDecl_Test{name = d.name, body = cbody}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl

	case ^Decl_Expect:
		ccond := canonicalize_expr(d.condition, scope, ctx)
		cdecl := new(CDecl_Expect)
		cdecl^ = CDecl_Expect{condition = ccond}
		span_set(ctx.spans, cdecl, d.span)
		return cdecl
	}
	cdecl := new(CDecl_Const)
	cdecl^ = CDecl_Const{}
	return cdecl
}

canonicalize_local_name :: proc(id: Intern_ID, scope: ^Canonicalize_Scope) -> Canonical_Name {
	name := Canonical_Name{module = NO_NAME, name = id, is_local = true}
	scope.local_names[id] = name
	return name
}

canonicalize_effect_op :: proc(op: Effect_Op, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> CEffect_Op {
	params := make([dynamic]CFunc_Param, 0, len(op.params))
	for p in op.params {
		append(&params, canonicalize_func_param(p, scope, ctx))
	}
	creturn_type: ^CType = nil
	if op.return_type != nil {
		creturn_type = canonicalize_type(op.return_type^, scope, ctx)
	}
	ceffects: ^CType = nil
	if op.return_effects != nil {
		ceffects = canonicalize_type(op.return_effects^, scope, ctx)
	}
	return CEffect_Op{
		name = op.name,
		is_effectful = op.is_effectful,
		params = params,
		return_type = creturn_type,
		return_effects = ceffects,
		span = op.span,
	}
}

canonicalize_trait_method :: proc(m: Trait_Method, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> CTrait_Method {
	params := make([dynamic]CFunc_Param, 0, len(m.params))
	for p in m.params {
		append(&params, canonicalize_func_param(p, scope, ctx))
	}
	creturn_type: ^CType = nil
	if m.return_type != nil {
		creturn_type = canonicalize_type(m.return_type^, scope, ctx)
	}
	return CTrait_Method{
		name = m.name,
		params = params,
		return_type = creturn_type,
		span = m.span,
	}
}

canonicalize_func_param :: proc(p: Func_Param, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> CFunc_Param {
	ct: ^CType = nil
	if p.type_ann != nil {
		ct = canonicalize_type(p.type_ann^, scope, ctx)
	}
	return CFunc_Param{name = p.name, type_ann = ct, span = p.span}
}

replace_dot_receiver :: proc(expr: Expr, replacement: Intern_ID) -> Expr {
	#partial switch e in expr {
	case ^Expr_Identifier:
		if e.name == DOT_RECEIVER_INTERN_ID {
			c := new(Expr_Identifier)
			c^ = Expr_Identifier{name = replacement, span = e.span}
			return c
		}
		return expr
	case ^Expr_Method_Call:
		creceiver := replace_dot_receiver(e.receiver, replacement)
		args := make([dynamic]Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(Expr_Method_Call)
		c^ = Expr_Method_Call{receiver = creceiver, method = e.method, args = args, span = e.span}
		return c
	case ^Expr_Field_Access:
		crecord := replace_dot_receiver(e.record, replacement)
		c := new(Expr_Field_Access)
		c^ = Expr_Field_Access{record = crecord, field = e.field, span = e.span}
		return c
	case ^Expr_Call:
		ccallee := replace_dot_receiver(e.callee, replacement)
		args := make([dynamic]Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(Expr_Call)
		c^ = Expr_Call{callee = ccallee, args = args, span = e.span}
		return c
	case:
		return expr
	}
}

canonicalize_expr :: proc(expr: Expr, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> CExpr {
	switch e in expr {
	case ^Expr_Int:
		c := new(CExpr_Int)
		c^ = CExpr_Int{value = e.value}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Float:
		c := new(CExpr_Float)
		c^ = CExpr_Float{value = e.value}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_String:
		c := new(CExpr_String)
		c^ = CExpr_String{value = e.value}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Bool:
		c := new(CExpr_Bool)
		c^ = CExpr_Bool{value = e.value}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Tag:
		name := Canonical_Name{module = NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		payload := make([dynamic]CExpr, 0, len(e.payload))
		for p in e.payload {
			append(&payload, canonicalize_expr(p, scope, ctx))
		}
		c := new(CExpr_Tag)
		c^ = CExpr_Tag{name = name, payload = payload}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Record:
		fields := make([dynamic]CRecord_Field, 0, len(e.fields))
		for f in e.fields {
			append(&fields, CRecord_Field{
				name = f.name,
				value = canonicalize_expr(f.value, scope, ctx),
				span = f.span,
			})
		}
		sort_record_fields_by_name(&fields)
		crest: CExpr
		if e.rest != nil {
			crest = canonicalize_expr(e.rest, scope, ctx)
		}
		c := new(CExpr_Record)
		c^ = CExpr_Record{fields = fields, rest = crest, is_open = e.is_open}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_List:
		elements := make([dynamic]CExpr, 0, len(e.elements))
		for el in e.elements {
			append(&elements, canonicalize_expr(el, scope, ctx))
		}
		c := new(CExpr_List)
		c^ = CExpr_List{elements = elements}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Identifier:
		name := Canonical_Name{module = NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		c := new(CExpr_Name)
		c^ = CExpr_Name{name = name}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Dollar_Identifier:
		name := Canonical_Name{module = NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		c := new(CExpr_Name)
		c^ = CExpr_Name{name = name}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Call:
		ccallee := canonicalize_expr(e.callee, scope, ctx)
		args := make([dynamic]CExpr, 0, len(e.args))
		for a in e.args {
			append(&args, canonicalize_expr(a, scope, ctx))
		}
		c := new(CExpr_Call)
		c^ = CExpr_Call{callee = ccallee, args = args}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Method_Call:
		creceiver := canonicalize_expr(e.receiver, scope, ctx)
		name := Canonical_Name{module = NO_NAME, name = e.method, is_local = true}
		if existing, ok := scope.local_names[e.method]; ok {
			name = existing
		}
		args := make([dynamic]CExpr, 0, len(e.args))
		for a in e.args {
			append(&args, canonicalize_expr(a, scope, ctx))
		}
		c := new(CExpr_Method_Call)
		c^ = CExpr_Method_Call{receiver = creceiver, method = name, args = args}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Lambda:
		type_params := make([dynamic]Intern_ID, 0, len(e.type_params))
		for tp in e.type_params {
			append(&type_params, tp)
		}
		params := make([dynamic]CFunc_Param, 0, len(e.params))
		for p in e.params {
			append(&params, canonicalize_func_param(p, scope, ctx))
		}
		creturn_type: ^CType = nil
		if e.return_type != nil {
			creturn_type = canonicalize_type(e.return_type^, scope, ctx)
		}
		ceffects: ^CType = nil
		if e.effects != nil {
			ceffects = canonicalize_type(e.effects^, scope, ctx)
		}
		cbody := canonicalize_expr(e.body, scope, ctx)
		c := new(CExpr_Lambda)
		c^ = CExpr_Lambda{
			type_params = type_params,
			params = params,
			return_type = creturn_type,
			effects = ceffects,
			body = cbody,
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Block:
		stmts := make([dynamic]CExpr, 0, len(e.statements))
		for s in e.statements {
			append(&stmts, canonicalize_expr(s, scope, ctx))
		}
		c := new(CExpr_Block)
		c^ = CExpr_Block{statements = stmts}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_If:
		c := new(CExpr_If)
		c^ = CExpr_If{
			condition = canonicalize_expr(e.condition, scope, ctx),
			then_branch = canonicalize_expr(e.then_branch, scope, ctx),
			else_branch = canonicalize_expr(e.else_branch, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Match:
		arms := make([dynamic]CMatch_Arm, 0, len(e.arms))
		for a in e.arms {
			append(&arms, CMatch_Arm{
				pattern = canonicalize_pattern(a.pattern, scope, ctx),
				body = canonicalize_expr(a.body, scope, ctx),
				span = a.span,
			})
		}
		c := new(CExpr_Match)
		c^ = CExpr_Match{
			scrutinee = canonicalize_expr(e.scrutinee, scope, ctx),
			arms = arms,
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_BinOp:
		c := new(CExpr_BinOp)
		c^ = CExpr_BinOp{
			op = e.op,
			left = canonicalize_expr(e.left, scope, ctx),
			right = canonicalize_expr(e.right, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_PrefixOp:
		c := new(CExpr_PrefixOp)
		c^ = CExpr_PrefixOp{
			op = e.op,
			operand = canonicalize_expr(e.operand, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Field_Access:
		c := new(CExpr_Field_Access)
		c^ = CExpr_Field_Access{
			record = canonicalize_expr(e.record, scope, ctx),
			field = e.field,
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Record_Update:
		updates := make([dynamic]CRecord_Field, 0, len(e.updates))
		for u in e.updates {
			append(&updates, CRecord_Field{
				name = u.name,
				value = canonicalize_expr(u.value, scope, ctx),
				span = u.span,
			})
		}
		sort_record_fields_by_name(&updates)
		c := new(CExpr_Record_Update)
		c^ = CExpr_Record_Update{
			rest = canonicalize_expr(e.rest, scope, ctx),
			updates = updates,
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Assign:
		c := new(CExpr_Assign)
		c^ = CExpr_Assign{
			target = canonicalize_expr(e.target, scope, ctx),
			value = canonicalize_expr(e.value, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Return:
		c := new(CExpr_Return)
		c^ = CExpr_Return{
			value = canonicalize_expr(e.value, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Crash:
		c := new(CExpr_Crash)
		c^ = CExpr_Crash{
			message = canonicalize_expr(e.message, scope, ctx),
		}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Interpolate:
		parts := make([dynamic]CExpr, 0, len(e.parts))
		for p in e.parts {
			append(&parts, canonicalize_expr(p, scope, ctx))
		}
		c := new(CExpr_Interpolate)
		c^ = CExpr_Interpolate{parts = parts}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Handle:
		effect_name := Canonical_Name{module = NO_NAME, name = e.effect, is_local = true}
		if existing, ok := scope.local_names[e.effect]; ok {
			effect_name = existing
		}
		cbody := canonicalize_expr(e.body, scope, ctx)
		arms := make([dynamic]CHandler_Arm, 0, len(e.arms))
		for a in e.arms {
			append(&arms, CHandler_Arm{
				op = a.op,
				resume_id = a.resume_id,
				body = canonicalize_expr(a.body, scope, ctx),
				span = a.span,
			})
		}
		c := new(CExpr_Handle)
		c^ = CExpr_Handle{effect = effect_name, is_shallow = e.is_shallow, body = cbody, arms = arms}
		span_set(ctx.spans, c, e.span)
		return c

	case ^Expr_Dot_Lambda:
		dot_lambda_counter += 1
		param_name := fmt.tprintf("_dot_{}", dot_lambda_counter)
		param_id := intern(&ctx.interner, param_name)

		resolved_body := replace_dot_receiver(e.body, param_id)
		cbody := canonicalize_expr(resolved_body, scope, ctx)

		params := make([dynamic]CFunc_Param, 1)
		params[0] = CFunc_Param{name = param_id, span = e.span}

		cl := new(CExpr_Lambda)
		cl^ = CExpr_Lambda{
			type_params = make([dynamic]Intern_ID, 0),
			params = params,
			return_type = nil,
			effects = nil,
			body = cbody,
		}
		span_set(ctx.spans, cl, e.span)
		return cl
	}
	c := new(CExpr_Int)
	c^ = CExpr_Int{}
	return c
}

canonicalize_pattern :: proc(pat: Pattern, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> CPattern {
	switch p in pat {
	case ^Pattern_Tag:
		name := Canonical_Name{module = NO_NAME, name = p.name, is_local = true}
		payload := make([dynamic]CPattern, 0, len(p.payload))
		for pp in p.payload {
			append(&payload, canonicalize_pattern(pp, scope, ctx))
		}
		c := new(CPattern_Tag)
		c^ = CPattern_Tag{name = name, payload = payload}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Record:
		fields := make([dynamic]CPattern_Field, 0, len(p.fields))
		for f in p.fields {
			append(&fields, CPattern_Field{name = f.name, binding = f.binding})
		}
		sort_pattern_fields_by_name(&fields)
		c := new(CPattern_Record)
		c^ = CPattern_Record{fields = fields, is_open = p.is_open}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_List:
		elements := make([dynamic]CPattern, 0, len(p.elements))
		for el in p.elements {
			append(&elements, canonicalize_pattern(el, scope, ctx))
		}
		c := new(CPattern_List)
		c^ = CPattern_List{elements = elements}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Int:
		c := new(CPattern_Int)
		c^ = CPattern_Int{value = p.value}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_String:
		c := new(CPattern_String)
		c^ = CPattern_String{value = p.value}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Bool:
		c := new(CPattern_Bool)
		c^ = CPattern_Bool{value = p.value}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Identifier:
		c := new(CPattern_Identifier)
		c^ = CPattern_Identifier{name = p.name}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Wildcard:
		c := new(CPattern_Wildcard)
		c^ = CPattern_Wildcard{}
		span_set(ctx.spans, c, p.span)
		return c

	case ^Pattern_Destructure:
		name := Canonical_Name{module = NO_NAME, name = p.type_name, is_local = true}
		c := new(CPattern_Destructure)
		c^ = CPattern_Destructure{
			type_name = name,
			inner = canonicalize_pattern(p.inner, scope, ctx),
		}
		span_set(ctx.spans, c, p.span)
		return c
	}
	c := new(CPattern_Wildcard)
	c^ = CPattern_Wildcard{}
	return c
}

canonicalize_type :: proc(t: Type, scope: ^Canonicalize_Scope, ctx: ^Compilation_Context) -> ^CType {
	result: CType
	switch ty in t {
	case ^Type_Primitive:
		c := new(CType_Primitive)
		c^ = CType_Primitive{name = ty.name}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Applied:
		args := make([dynamic]CType, 0, len(ty.args))
		for a in ty.args {
			append(&args, canonicalize_type(a, scope, ctx)^)
		}
		c := new(CType_Applied)
		c^ = CType_Applied{name = ty.name, args = args}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Function:
		params := make([dynamic]CType, 0, len(ty.params))
		for p in ty.params {
			append(&params, canonicalize_type(p, scope, ctx)^)
		}
		ceffects: ^CType = nil
		if ty.effects != nil {
			ceffects = canonicalize_type(ty.effects^, scope, ctx)
		}
		creturn := canonicalize_type(ty.return_, scope, ctx)
		c := new(CType_Function)
		c^ = CType_Function{params = params, effects = ceffects, return_ = creturn^}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Record:
		fields := make([dynamic]CType_Field, 0, len(ty.fields))
		for f in ty.fields {
			cf := canonicalize_type(f.type, scope, ctx)
			append(&fields, CType_Field{name = f.name, type = cf^})
		}
		sort_type_fields_by_name(&fields)
		c := new(CType_Record)
		c^ = CType_Record{fields = fields, rest = ty.rest, is_open = ty.is_open}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Tag_Union:
		tags := make([dynamic]CType_Tag, 0, len(ty.tags))
		for tg in ty.tags {
			payload := make([dynamic]CType, 0, len(tg.payload))
			for p in tg.payload {
				cp := canonicalize_type(p, scope, ctx)
				append(&payload, cp^)
			}
			append(&tags, CType_Tag{name = tg.name, payload = payload})
		}
		c := new(CType_Tag_Union)
		c^ = CType_Tag_Union{tags = tags, rest = ty.rest, is_open = ty.is_open}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Effect_Row:
		effects := make([dynamic]Intern_ID, 0, len(ty.effects))
		for e in ty.effects {
			append(&effects, e)
		}
		c := new(CType_Effect_Row)
		c^ = CType_Effect_Row{effects = effects, rest = ty.rest, is_open = ty.is_open}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Variable:
		c := new(CType_Variable)
		c^ = CType_Variable{name = ty.name}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)

	case ^Type_Wildcard:
		c := new(CType_Wildcard)
		c^ = CType_Wildcard{}
		span_set(ctx.spans, c, ty.span)
		result = CType(c)
	}
	ptr := new(CType)
	ptr^ = result
	return ptr
}

sort_record_fields_by_name :: proc(fields: ^[dynamic]CRecord_Field) {
	for i := 0; i < len(fields) - 1; i += 1 {
		for j := i + 1; j < len(fields); j += 1 {
			if int(fields[j].name) < int(fields[i].name) {
				fields[i], fields[j] = fields[j], fields[i]
			}
		}
	}
}

sort_pattern_fields_by_name :: proc(fields: ^[dynamic]CPattern_Field) {
	for i := 0; i < len(fields) - 1; i += 1 {
		for j := i + 1; j < len(fields); j += 1 {
			if int(fields[j].name) < int(fields[i].name) {
				fields[i], fields[j] = fields[j], fields[i]
			}
		}
	}
}

sort_type_fields_by_name :: proc(fields: ^[dynamic]CType_Field) {
	for i := 0; i < len(fields) - 1; i += 1 {
		for j := i + 1; j < len(fields); j += 1 {
			if int(fields[j].name) < int(fields[i].name) {
				fields[i], fields[j] = fields[j], fields[i]
			}
		}
	}
}

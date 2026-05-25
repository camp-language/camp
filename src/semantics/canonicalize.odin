package semantics

import "core:fmt"
import "core:slice"

import "camp:base"
import "camp:frontend"
import "camp:diagnostics"

DOT_RECEIVER_NAME :: "__dot_receiver__"
DOT_RECEIVER_INTERN_ID : base.Intern_ID = 0
dot_lambda_counter : int = 0

Canonicalize_Scope :: struct {
	local_names:    map[base.Intern_ID]base.Canonical_Name,
	local_kinds:    map[base.Intern_ID]Decl_Kind,
}

Decl_Kind :: enum {
	Const,
	Effect,
	Trait,
	Alias,
	Newtype,
	Import,
	Test,
	Expect,
}

canonicalize :: proc(surface: frontend.File, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CFile {
	DOT_RECEIVER_INTERN_ID = base.intern(interner, DOT_RECEIVER_NAME)

	scope: Canonicalize_Scope
	scope.local_names = make(map[base.Intern_ID]base.Canonical_Name, 64)
	scope.local_kinds = make(map[base.Intern_ID]Decl_Kind, 64)
	defer delete(scope.local_names)
	defer delete(scope.local_kinds)

	cfile: CFile
	cfile.path = surface.path
	cfile.decls = make([dynamic]CDecl, 0, len(surface.decls))
	cfile.imports = make([dynamic]base.Deferred_Import, 0, 8)

	for decl in surface.decls {
		cdecl := canonicalize_decl(decl, &scope, &cfile.imports, interner, collector)
		append(&cfile.decls, cdecl)

		#partial switch d in cdecl {
		case ^CDecl_Newtype:
			if len(d.derive_targets) > 0 {
				stubs := generate_derive_stubs(d, &scope, interner, collector)
				for stub in stubs {
					append(&cfile.decls, stub)
				}
			}
		case ^CDecl_Const, ^CDecl_Effect, ^CDecl_Trait, ^CDecl_Alias, ^CDecl_Import, ^CDecl_Test, ^CDecl_Expect:
		}
	}

	return cfile
}

canonicalize_decl :: proc(decl: frontend.Decl, scope: ^Canonicalize_Scope, imports: ^[dynamic]base.Deferred_Import, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CDecl {
	#partial switch d in decl {
	case ^frontend.Decl_Const:
		name := canonicalize_local_name(d.name, .Const, scope, interner, collector)
		cbody := canonicalize_expr(d.body, scope, interner, collector)
		ctype_ann: ^CType = nil
		if d.type_ann != nil {
			ctype_ann = canonicalize_type(d.type_ann^, scope, interner, collector)
		}
		where_clauses := make([dynamic]frontend.Where_Clause, 0, len(d.where_clauses))
		for wc in d.where_clauses {
			append(&where_clauses, wc)
		}
		// Merge where clause constraints into the lambda's type params
		// so the existing typecheck constraint machinery handles them.
		if len(where_clauses) > 0 {
			if lambda, ok := cbody.(^CExpr_Lambda); ok {
				for wc in where_clauses {
					found_param := false
					for &tp in lambda.type_params {
						if tp.name == wc.type_param {
							found := false
							for c in tp.constraints {
								if c == wc.trait_name {
									found = true
									break
								}
							}
							if !found {
								append(&tp.constraints, wc.trait_name)
							}
							found_param = true
							break
						}
					}
					// If the where clause references a type variable not in annotations,
					// add it as a new type param
					if !found_param {
						constraints := make([dynamic]base.Intern_ID, 0, 1)
						append(&constraints, wc.trait_name)
						append(&lambda.type_params, frontend.Type_Param{name = wc.type_param, constraints = constraints})
					}
				}
			}
		}
		cdecl := new(CDecl_Const)
		cdecl^ = CDecl_Const{
			name = name,
			is_pub = d.is_pub,
			is_effectful = d.is_effectful,
			type_ann = ctype_ann,
			body = cbody,
			derive_targets = make([dynamic]base.Intern_ID, 0, 4),
			where_clauses = where_clauses,
			span = d.span,
		}
		return cdecl

	case ^frontend.Decl_Effect:
		name := canonicalize_local_name(d.name, .Effect, scope, interner, collector)
		ops := make([dynamic]CEffect_Op, 0, len(d.operations))
		for op in d.operations {
			append(&ops, canonicalize_effect_op(op, scope, interner, collector))
		}
		type_params := make([dynamic]frontend.Type_Param, 0, len(d.type_params))
		for tp in d.type_params {
			constraints := make([dynamic]base.Intern_ID, 0, len(tp.constraints))
			for c in tp.constraints {
				append(&constraints, c)
			}
			append(&type_params, frontend.Type_Param{name = tp.name, constraints = constraints, is_effect = tp.is_effect})
		}
		cdecl := new(CDecl_Effect)
		cdecl^ = CDecl_Effect{
			name = name,
			is_pub = d.is_pub,
			operations = ops,
			type_params = type_params,
			span = d.span,
		}
		return cdecl

	case ^frontend.Decl_Trait:
		name := canonicalize_local_name(d.name, .Trait, scope, interner, collector)
		methods := make([dynamic]CTrait_Method, 0, len(d.methods))
		for m in d.methods {
			append(&methods, canonicalize_trait_method(m, scope, interner, collector))
		}
		cdecl := new(CDecl_Trait)
		cdecl^ = CDecl_Trait{
			name = name,
			is_pub = d.is_pub,
			parent = d.parent,
			methods = methods,
			span = d.span,
		}
		return cdecl

	case ^frontend.Decl_Alias:
		name := canonicalize_local_name(d.name, .Alias, scope, interner, collector)
		ctarget := canonicalize_type(d.target^, scope, interner, collector)
		cdecl := new(CDecl_Alias)
		cdecl^ = CDecl_Alias{
			name = name,
			is_pub = d.is_pub,
			target = ctarget,
			span = d.span,
		}
		return cdecl

	case ^frontend.Decl_Newtype:
		name := canonicalize_local_name(d.name, .Newtype, scope, interner, collector)
		type_params := make([dynamic]base.Intern_ID, 0, len(d.type_params))
		for tp in d.type_params {
			append(&type_params, tp)
		}
		cinner_type := canonicalize_type(d.inner_type^, scope, interner, collector)
		derive_targets := make([dynamic]base.Intern_ID, 0, len(d.derive_targets))
		for dt in d.derive_targets {
			append(&derive_targets, dt)
		}
		cdecl := new(CDecl_Newtype)
		cdecl^ = CDecl_Newtype{
			name = name,
			is_pub = d.is_pub,
			pub_variants = d.pub_variants,
			type_params = type_params,
			inner_type = cinner_type,
			derive_targets = derive_targets,
			span = d.span,
		}
		return cdecl

	case ^frontend.Decl_Import:
		di := base.Deferred_Import{
			module = base.intern(interner, d.module),
			names = make([dynamic]base.Intern_ID, 0, len(d.names)),
			alias = d.alias,
			span = d.span,
		}
		for item in d.names {
			switch it in item {
			case base.Intern_ID:
				append(&di.names, it)
			case ^frontend.Import_Variant_Group:
				for variant in it.variants {
					append(&di.names, variant)
				}
			}
		}
		append(imports, di)
		cdecl := new(CDecl_Import)
		cdecl^ = CDecl_Import{deferred = di, span = d.span}
		return cdecl

	case ^frontend.Decl_Test:
		cbody := canonicalize_expr(d.body, scope, interner, collector)
		cdecl := new(CDecl_Test)
		cdecl^ = CDecl_Test{name = d.name, body = cbody, span = d.span}
		return cdecl

	case ^frontend.Decl_Expect:
		ccond := canonicalize_expr(d.condition, scope, interner, collector)
		cdecl := new(CDecl_Expect)
		cdecl^ = CDecl_Expect{condition = ccond, span = d.span}
		return cdecl
	}
	cdecl := new(CDecl_Const)
	cdecl^ = CDecl_Const{span = base.Source_Span_ZERO}
	return cdecl
}

canonicalize_local_name :: proc(id: base.Intern_ID, kind: Decl_Kind, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> base.Canonical_Name {
	if existing_kind, ok := scope.local_kinds[id]; ok {
		if existing_kind != kind {
			name_str := base.intern_get(interner, id)
			diagnostics.collector_add_diag(collector, diagnostics.diag_duplicate_module_name(name_str, base.Source_Span_ZERO))
		}
	}
	name := base.Canonical_Name{module = base.NO_NAME, name = id, is_local = true}
	scope.local_names[id] = name
	scope.local_kinds[id] = kind
	return name
}

canonicalize_effect_op :: proc(op: frontend.Effect_Op, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CEffect_Op {
	params := make([dynamic]CFunc_Param, 0, len(op.params))
	for p in op.params {
		append(&params, canonicalize_func_param(p, scope, interner, collector))
	}
	creturn_type: ^CType = nil
	if op.return_type != nil {
		creturn_type = canonicalize_type(op.return_type^, scope, interner, collector)
	}
	ceffects: ^CType = nil
	if op.return_effects != nil {
		ceffects = canonicalize_type(op.return_effects^, scope, interner, collector)
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

canonicalize_trait_method :: proc(m: frontend.Trait_Method, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CTrait_Method {
	params := make([dynamic]CFunc_Param, 0, len(m.params))
	for p in m.params {
		append(&params, canonicalize_func_param(p, scope, interner, collector))
	}
	creturn_type: ^CType = nil
	if m.return_type != nil {
		creturn_type = canonicalize_type(m.return_type^, scope, interner, collector)
	}
	return CTrait_Method{
		name = m.name,
		params = params,
		return_type = creturn_type,
		span = m.span,
	}
}

canonicalize_func_param :: proc(p: frontend.Func_Param, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CFunc_Param {
	ct: ^CType = nil
	if p.type_ann != nil {
		ct = canonicalize_type(p.type_ann^, scope, interner, collector)
	}
	return CFunc_Param{name = p.name, type_ann = ct, span = p.span}
}

replace_dot_receiver :: proc(expr: frontend.Expr, replacement: base.Intern_ID) -> frontend.Expr {
	#partial switch e in expr {
	case ^frontend.Expr_Identifier:
		if e.name == DOT_RECEIVER_INTERN_ID {
			c := new(frontend.Expr_Identifier)
			c^ = frontend.Expr_Identifier{name = replacement, span = e.span}
			return c
		}
		return expr
	case ^frontend.Expr_Method_Call:
		creceiver := replace_dot_receiver(e.receiver, replacement)
		args := make([dynamic]frontend.Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(frontend.Expr_Method_Call)
		c^ = frontend.Expr_Method_Call{receiver = creceiver, method = e.method, args = args, dispatch = e.dispatch, span = e.span}
		return c
	case ^frontend.Expr_Field_Access:
		crecord := replace_dot_receiver(e.record, replacement)
		c := new(frontend.Expr_Field_Access)
		c^ = frontend.Expr_Field_Access{record = crecord, field = e.field, span = e.span}
		return c
	case ^frontend.Expr_Call:
		ccallee := replace_dot_receiver(e.callee, replacement)
		args := make([dynamic]frontend.Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(frontend.Expr_Call)
		c^ = frontend.Expr_Call{callee = ccallee, args = args, span = e.span}
		return c
	case ^frontend.Expr_Int, ^frontend.Expr_Float, ^frontend.Expr_String, ^frontend.Expr_Char, ^frontend.Expr_Bool, ^frontend.Expr_Tag, ^frontend.Expr_Nominal_Construct, ^frontend.Expr_Record, ^frontend.Expr_List, ^frontend.Expr_Dollar_Identifier, ^frontend.Expr_Lambda, ^frontend.Expr_Block, ^frontend.Expr_If, ^frontend.Expr_Match, ^frontend.Expr_BinOp, ^frontend.Expr_PrefixOp, ^frontend.Expr_Record_Update, ^frontend.Expr_Assign, ^frontend.Expr_Return, ^frontend.Expr_Crash, ^frontend.Expr_Todo, ^frontend.Expr_Interpolated_String, ^frontend.Expr_Handle, ^frontend.Expr_Par, ^frontend.Expr_Dot_Lambda, ^frontend.Expr_For:
		return expr
	}
	return expr
}

canonicalize_expr :: proc(expr: frontend.Expr, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CExpr {
	switch e in expr {
	case ^frontend.Expr_Int:
		c := new(CExpr_Int)
		c^ = CExpr_Int{value = e.value, span = e.span}
		return c

	case ^frontend.Expr_Float:
		c := new(CExpr_Float)
		c^ = CExpr_Float{value = e.value, span = e.span}
		return c

	case ^frontend.Expr_String:
		c := new(CExpr_String)
		c^ = CExpr_String{value = e.value, span = e.span}
		return c

	case ^frontend.Expr_Bool:
		c := new(CExpr_Bool)
		c^ = CExpr_Bool{value = e.value, span = e.span}
		return c

	case ^frontend.Expr_Char:
		c := new(CExpr_Int)
		c^ = CExpr_Int{value = i64(e.value), span = e.span}
		return c

	case ^frontend.Expr_Tag:
		name := base.Canonical_Name{module = base.NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		payload := make([dynamic]CExpr, 0, len(e.payload))
		for p in e.payload {
			append(&payload, canonicalize_expr(p, scope, interner, collector))
		}
		c := new(CExpr_Tag)
		c^ = CExpr_Tag{name = name, payload = payload, span = e.span}
		return c

	case ^frontend.Expr_Nominal_Construct:
		type_name := base.Canonical_Name{module = base.NO_NAME, name = e.type_name, is_local = true}
		if existing, ok := scope.local_names[e.type_name]; ok {
			type_name = existing
		}
		payload := make([dynamic]CExpr, 0, len(e.payload))
		for p in e.payload {
			append(&payload, canonicalize_expr(p, scope, interner, collector))
		}
		c := new(CExpr_Nominal_Construct)
		c^ = CExpr_Nominal_Construct{type_name = type_name, variant = e.variant, payload = payload, span = e.span}
		return c

	case ^frontend.Expr_Record:
		fields := make([dynamic]CRecord_Field, 0, len(e.fields))
		for f in e.fields {
			append(&fields, CRecord_Field{
				name = f.name,
				value = canonicalize_expr(f.value, scope, interner, collector),
				span = f.span,
			})
		}
		sort_record_fields_by_name(&fields)
		crest: CExpr
		if e.rest != nil {
			crest = canonicalize_expr(e.rest, scope, interner, collector)
		}
		c := new(CExpr_Record)
		c^ = CExpr_Record{fields = fields, rest = crest, is_open = e.is_open, span = e.span}
		return c

	case ^frontend.Expr_List:
		elements := make([dynamic]CExpr, 0, len(e.elements))
		for el in e.elements {
			append(&elements, canonicalize_expr(el, scope, interner, collector))
		}
		c := new(CExpr_List)
		c^ = CExpr_List{elements = elements, span = e.span}
		return c

	case ^frontend.Expr_Identifier:
		name := base.Canonical_Name{module = base.NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		c := new(CExpr_Name)
		c^ = CExpr_Name{name = name, span = e.span}
		return c

	case ^frontend.Expr_Dollar_Identifier:
		name := base.Canonical_Name{module = base.NO_NAME, name = e.name, is_local = true}
		if existing, ok := scope.local_names[e.name]; ok {
			name = existing
		}
		c := new(CExpr_Name)
		c^ = CExpr_Name{name = name, span = e.span}
		return c

	case ^frontend.Expr_Call:
		ccallee := canonicalize_expr(e.callee, scope, interner, collector)
		args := make([dynamic]CExpr, 0, len(e.args))
		for a in e.args {
			append(&args, canonicalize_expr(a, scope, interner, collector))
		}

		c := new(CExpr_Call)
		c^ = CExpr_Call{callee = ccallee, args = args, span = e.span}
		return c

	case ^frontend.Expr_Method_Call:
		creceiver := canonicalize_expr(e.receiver, scope, interner, collector)
		name := base.Canonical_Name{module = base.NO_NAME, name = e.method, is_local = true}
		if existing, ok := scope.local_names[e.method]; ok {
			name = existing
		}
		args := make([dynamic]CExpr, 0, len(e.args))
		for a in e.args {
			append(&args, canonicalize_expr(a, scope, interner, collector))
		}

		// Method sugar desugaring: par_map!, par_filter!, etc. → Parallel! perform
		method_str := base.intern_get(interner, e.method)
		parallel_sugar := desugar_parallel_method(method_str, creceiver, args, e.span, scope, interner, collector)
		if parallel_sugar != nil {
			return parallel_sugar
		}

		c := new(CExpr_Method_Call)
		c^ = CExpr_Method_Call{receiver = creceiver, method = name, args = args, is_effectful = e.is_effectful, span = e.span}
		return c

	case ^frontend.Expr_Lambda:
		existing_type_params := make([dynamic]frontend.Type_Param, 0, len(e.type_params))
		for tp in e.type_params {
			constraints := make([dynamic]base.Intern_ID, 0, len(tp.constraints))
			for c in tp.constraints {
				append(&constraints, c)
			}
			append(&existing_type_params, frontend.Type_Param{name = tp.name, constraints = constraints, is_effect = tp.is_effect})
		}
		where_clauses := make([dynamic]frontend.Where_Clause, 0, len(e.where_clauses))
		for wc in e.where_clauses {
			append(&where_clauses, wc)
		}
		params := make([dynamic]CFunc_Param, 0, len(e.params))
		for p in e.params {
			append(&params, canonicalize_func_param(p, scope, interner, collector))
		}
		creturn_type: ^CType = nil
		if e.return_type != nil {
			creturn_type = canonicalize_type(e.return_type^, scope, interner, collector)
		}
		ceffects: ^CType = nil
		if e.effects != nil {
			ceffects = canonicalize_type(e.effects^, scope, interner, collector)
		}
		// Infer type params from lowercase type variables in annotations
		type_params := infer_type_params(params[:], creturn_type, ceffects, existing_type_params, where_clauses)
		cbody := canonicalize_expr(e.body, scope, interner, collector)
		c := new(CExpr_Lambda)
		c^ = CExpr_Lambda{
			type_params = type_params,
			params = params,
			return_type = creturn_type,
			effects = ceffects,
			where_clauses = where_clauses,
			body = cbody,
			span = e.span,
		}
		return c

	case ^frontend.Expr_Block:
		stmts := make([dynamic]CExpr, 0, len(e.statements))
		for s in e.statements {
			append(&stmts, canonicalize_expr(s, scope, interner, collector))
		}
		c := new(CExpr_Block)
		c^ = CExpr_Block{statements = stmts, span = e.span}
		return c

	case ^frontend.Expr_If:
		c := new(CExpr_If)
		c^ = CExpr_If{
			condition = canonicalize_expr(e.condition, scope, interner, collector),
			then_branch = canonicalize_expr(e.then_branch, scope, interner, collector),
			else_branch = canonicalize_expr(e.else_branch, scope, interner, collector),
			span = e.span,
		}
		return c

	case ^frontend.Expr_Match:
		arms := make([dynamic]CMatch_Arm, 0, len(e.arms))
		for a in e.arms {
			cguard: CExpr = nil
			if a.guard != nil {
				cguard = canonicalize_expr(a.guard, scope, interner, collector)
			}
			append(&arms, CMatch_Arm{
				pattern = canonicalize_pattern(a.pattern, scope, interner, collector),
				guard = cguard,
				body = canonicalize_expr(a.body, scope, interner, collector),
				span = a.span,
			})
		}
		c := new(CExpr_Match)
		c^ = CExpr_Match{
			scrutinee = canonicalize_expr(e.scrutinee, scope, interner, collector),
			arms = arms,
			span = e.span,
		}
		return c

	case ^frontend.Expr_BinOp:
		c := new(CExpr_BinOp)
		c^ = CExpr_BinOp{
			op = e.op,
			left = canonicalize_expr(e.left, scope, interner, collector),
			right = canonicalize_expr(e.right, scope, interner, collector),
			span = e.span,
		}
		return c

	case ^frontend.Expr_PrefixOp:
		c := new(CExpr_PrefixOp)
		c^ = CExpr_PrefixOp{
			op = e.op,
			operand = canonicalize_expr(e.operand, scope, interner, collector),
			span = e.span,
		}
		return c

	case ^frontend.Expr_Field_Access:
		c := new(CExpr_Field_Access)
		c^ = CExpr_Field_Access{
			record = canonicalize_expr(e.record, scope, interner, collector),
			field = e.field,
			span = e.span,
		}
		return c

	case ^frontend.Expr_Record_Update:
		updates := make([dynamic]CRecord_Field, 0, len(e.updates))
		for u in e.updates {
			append(&updates, CRecord_Field{
				name = u.name,
				value = canonicalize_expr(u.value, scope, interner, collector),
				span = u.span,
			})
		}
		sort_record_fields_by_name(&updates)
		c := new(CExpr_Record_Update)
		c^ = CExpr_Record_Update{
			rest = canonicalize_expr(e.rest, scope, interner, collector),
			updates = updates,
			span = e.span,
		}
		return c

	case ^frontend.Expr_Assign:
		ctype_ann: ^CType = nil
		if e.type_ann != nil {
			ctype_ann = canonicalize_type(e.type_ann^, scope, interner, collector)
		}
		c := new(CExpr_Assign)
		c^ = CExpr_Assign{
			target = canonicalize_expr(e.target, scope, interner, collector),
			value = canonicalize_expr(e.value, scope, interner, collector),
			type_ann = ctype_ann,
			span = e.span,
		}
		return c

	case ^frontend.Expr_Return:
		c := new(CExpr_Return)
		c^ = CExpr_Return{
			value = canonicalize_expr(e.value, scope, interner, collector),
			span = e.span,
		}
		return c

	case ^frontend.Expr_Crash:
		c := new(CExpr_Crash)
		c^ = CExpr_Crash{
			message = canonicalize_expr(e.message, scope, interner, collector),
			span = e.span,
		}
		return c

	case ^frontend.Expr_Todo:
		cmessage: CExpr = nil
		if e.message != nil {
			cmessage = canonicalize_expr(e.message, scope, interner, collector)
		}
		c := new(CExpr_Crash)
		c^ = CExpr_Crash{
			message = cmessage,
			span = e.span,
		}
		return c

	case ^frontend.Expr_Interpolated_String:
		cparts := make([dynamic]CExpr_String_Part, 0, len(e.parts))
		for part in e.parts {
			switch p in part {
			case ^frontend.String_Segment:
				clit := new(CExpr_String_Literal)
				clit^ = CExpr_String_Literal{value = p.text, span = p.span}
				append(&cparts, CExpr_String_Part(clit))
			case frontend.Expr:
				cexpr := canonicalize_expr(p, scope, interner, collector)
				append(&cparts, CExpr_String_Part(cexpr))
			}
		}
		c := new(CExpr_Interpolated_String)
		c^ = CExpr_Interpolated_String{parts = cparts, span = e.span}
		return c

	case ^frontend.Expr_Handle:
		effect_id := len(e.effects) > 0 ? e.effects[0] : 0
		effect_name := base.Canonical_Name{module = base.NO_NAME, name = effect_id, is_local = true}
		if existing, ok := scope.local_names[effect_id]; ok {
			effect_name = existing
		}
		cbody := canonicalize_expr(e.body, scope, interner, collector)
		arms := make([dynamic]CHandler_Arm, 0, len(e.arms))
		for a in e.arms {
			append(&arms, CHandler_Arm{
				op = a.op,
				params = a.params,
				body = canonicalize_expr(a.body, scope, interner, collector),
				span = a.span,
			})
		}
		c := new(CExpr_Handle)
		c.effects = make([dynamic]base.Canonical_Name, 0, 1)
		append(&c.effects, effect_name)
		c.body = cbody
		c.arms = arms
		c.span = e.span
		return c

	case ^frontend.Expr_Par:
		if e.for_var != base.Intern_ID(0) {
			// par for x in xs { body } → Parallel!.for_each!(xs, |x| body)
			citer := canonicalize_expr(e.for_iter, scope, interner, collector)
			cbody := canonicalize_expr(e.for_body, scope, interner, collector)

			// Create lambda: |x| body
			params := make([dynamic]CFunc_Param, 1)
			params[0] = CFunc_Param{name = e.for_var, span = e.span}
			lambda := new(CExpr_Lambda)
			lambda^ = CExpr_Lambda{
				type_params = make([dynamic]frontend.Type_Param, 0),
				params = params,
				return_type = nil,
				effects = nil,
				where_clauses = make([dynamic]frontend.Where_Clause, 0),
				body = cbody,
				span = e.span,
			}

			// Create perform: Parallel!.for_each!(iter, lambda)
			parallel_name := base.Canonical_Name{module = base.NO_NAME, name = base.intern(interner, "Parallel"), is_local = true}
			for_each_op := base.intern(interner, "for_each!")
			args := make([dynamic]CExpr, 0, 2)
			append(&args, citer)
			append(&args, lambda)

			perform := new(CExpr_Perform)
			perform^ = CExpr_Perform{effect = parallel_name, op = for_each_op, args = args, span = e.span}
			return perform
		} else {
			// par { name: expr, ... } — keep as CExpr_Par with names
			// The typechecker will infer a heterogeneous record type
			cexprs := make([dynamic]CExpr, 0, len(e.expressions))
			for expr in e.expressions {
				append(&cexprs, canonicalize_expr(expr, scope, interner, collector))
			}

			cnames := make([dynamic]base.Intern_ID, len(e.names))
			for idx in 0..<len(e.names) {
				cnames[idx] = e.names[idx]
			}

			par := new(CExpr_Par)
			par^ = CExpr_Par{
				names = cnames,
				expressions = cexprs,
				span = e.span,
			}
			return par
		}

	case ^frontend.Expr_For:
		citer := canonicalize_expr(e.iterable, scope, interner, collector)
		cbody := canonicalize_expr(e.body, scope, interner, collector)
		c := new(CExpr_For)
		c^ = CExpr_For{var = e.var, iterable = citer, body = cbody, span = e.span}
		return c

	case ^frontend.Expr_Dot_Lambda:
		dot_lambda_counter += 1
		param_name := fmt.tprintf("_dot_{}", dot_lambda_counter)
		param_id := base.intern(interner, param_name)

		resolved_body := replace_dot_receiver(e.body, param_id)
		cbody := canonicalize_expr(resolved_body, scope, interner, collector)

		params := make([dynamic]CFunc_Param, 1)
		params[0] = CFunc_Param{name = param_id, span = e.span}

		cl := new(CExpr_Lambda)
		cl^ = CExpr_Lambda{
			type_params = make([dynamic]frontend.Type_Param, 0),
			params = params,
			return_type = nil,
			effects = nil,
			where_clauses = make([dynamic]frontend.Where_Clause, 0),
			body = cbody,
			span = e.span,
		}
		return cl
	}
	c := new(CExpr_Int)
	c^ = CExpr_Int{span = base.Source_Span_ZERO}
	return c
}

canonicalize_pattern :: proc(pat: frontend.Pattern, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CPattern {
	switch p in pat {
	case ^frontend.Pattern_Tag:
		name := base.Canonical_Name{module = base.NO_NAME, name = p.name, is_local = true}
		payload := make([dynamic]CPattern, 0, len(p.payload))
		for pp in p.payload {
			append(&payload, canonicalize_pattern(pp, scope, interner, collector))
		}
		c := new(CPattern_Tag)
		c^ = CPattern_Tag{name = name, payload = payload, span = p.span}
		return c

	case ^frontend.Pattern_Record:
		fields := make([dynamic]CPattern_Field, 0, len(p.fields))
		for f in p.fields {
			append(&fields, CPattern_Field{name = f.name, binding = f.binding, span = f.span})
		}
		sort_pattern_fields_by_name(&fields)
		c := new(CPattern_Record)
		c^ = CPattern_Record{fields = fields, is_open = p.is_open, span = p.span}
		return c

	case ^frontend.Pattern_List:
		elements := make([dynamic]CPattern, 0, len(p.elements))
		for el in p.elements {
			append(&elements, canonicalize_pattern(el, scope, interner, collector))
		}
		c := new(CPattern_List)
		c^ = CPattern_List{elements = elements, span = p.span}
		return c

	case ^frontend.Pattern_Int:
		c := new(CPattern_Int)
		c^ = CPattern_Int{value = p.value, span = p.span}
		return c

	case ^frontend.Pattern_Char:
		c := new(CPattern_Int)
		c^ = CPattern_Int{value = i64(p.value), span = p.span}
		return c

	case ^frontend.Pattern_String:
		c := new(CPattern_String)
		c^ = CPattern_String{value = p.value, span = p.span}
		return c

	case ^frontend.Pattern_Bool:
		c := new(CPattern_Bool)
		c^ = CPattern_Bool{value = p.value, span = p.span}
		return c

	case ^frontend.Pattern_Identifier:
		c := new(CPattern_Identifier)
		c^ = CPattern_Identifier{name = p.name, span = p.span}
		return c

	case ^frontend.Pattern_Wildcard:
		c := new(CPattern_Wildcard)
		c^ = CPattern_Wildcard{span = p.span}
		return c

	case ^frontend.Pattern_Destructure:
		name := base.Canonical_Name{module = base.NO_NAME, name = p.type_name, is_local = true}
		c := new(CPattern_Destructure)
		c^ = CPattern_Destructure{
			type_name = name,
			inner = canonicalize_pattern(p.inner, scope, interner, collector),
			span = p.span,
		}
		return c

	case ^frontend.Pattern_Or:
		alternatives := make([dynamic]CPattern, 0, len(p.alternatives))
		for alt in p.alternatives {
			append(&alternatives, canonicalize_pattern(alt, scope, interner, collector))
		}
		c := new(CPattern_Or)
		c^ = CPattern_Or{alternatives = alternatives, span = p.span}
		return c
	}
	c := new(CPattern_Wildcard)
	c^ = CPattern_Wildcard{span = base.Source_Span_ZERO}
	return c
}

canonicalize_type :: proc(t: frontend.Type, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> ^CType {
	result: CType
	switch ty in t {
	case ^frontend.Type_Primitive:
		c := new(CType_Primitive)
		c^ = CType_Primitive{name = ty.name, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Applied:
		args := make([dynamic]CType, 0, len(ty.args))
		for a in ty.args {
			append(&args, canonicalize_type(a, scope, interner, collector)^)
		}
		c := new(CType_Applied)
		c^ = CType_Applied{name = ty.name, args = args, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Function:
		params := make([dynamic]CType, 0, len(ty.params))
		for p in ty.params {
			append(&params, canonicalize_type(p, scope, interner, collector)^)
		}
		ceffects: ^CType = nil
		if ty.effects != nil {
			ceffects = canonicalize_type(ty.effects^, scope, interner, collector)
		}
		creturn := canonicalize_type(ty.return_, scope, interner, collector)
		c := new(CType_Function)
		c^ = CType_Function{params = params, effects = ceffects, return_ = creturn^, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Record:
		fields := make([dynamic]CType_Field, 0, len(ty.fields))
		for f in ty.fields {
			cf := canonicalize_type(f.type, scope, interner, collector)
			append(&fields, CType_Field{name = f.name, type = cf^, span = f.span})
		}
		sort_type_fields_by_name(&fields)
		c := new(CType_Record)
		c^ = CType_Record{fields = fields, rest = ty.rest, is_open = ty.is_open, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Tag_Union:
		tags := make([dynamic]CType_Tag, 0, len(ty.tags))
		for tg in ty.tags {
			payload := make([dynamic]CType, 0, len(tg.payload))
			for p in tg.payload {
				cp := canonicalize_type(p, scope, interner, collector)
				append(&payload, cp^)
			}
			append(&tags, CType_Tag{name = tg.name, payload = payload, span = tg.span})
		}
		c := new(CType_Tag_Union)
		c^ = CType_Tag_Union{tags = tags, rest = ty.rest, is_open = ty.is_open, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Effect_Row:
		effects := make([dynamic]CType_Effect_Entry, 0, len(ty.effects))
		for e in ty.effects {
			type_args := make([dynamic]CType, 0, len(e.type_args))
			for a in e.type_args {
				ca := canonicalize_type(a, scope, interner, collector)
				append(&type_args, ca^)
			}
			append(&effects, CType_Effect_Entry{
				name = e.name,
				type_args = type_args,
				span = e.span,
			})
		}
		c := new(CType_Effect_Row)
		c^ = CType_Effect_Row{effects = effects, rest = ty.rest, is_open = ty.is_open, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Variable:
		c := new(CType_Variable)
		c^ = CType_Variable{name = ty.name, span = ty.span}
		result = CType(c)

	case ^frontend.Type_Wildcard:
		c := new(CType_Wildcard)
		c^ = CType_Wildcard{span = ty.span}
		result = CType(c)

	case ^frontend.Type_Self:
		c := new(CType_Self)
		c^ = CType_Self{span = ty.span}
		result = CType(c)
	}
	ptr := new(CType)
	ptr^ = result
	return ptr
}

sort_record_fields_by_name :: proc(fields: ^[dynamic]CRecord_Field) {
	slice.sort_by(fields[:], proc(a, b: CRecord_Field) -> bool { return int(a.name) < int(b.name) })
}

sort_pattern_fields_by_name :: proc(fields: ^[dynamic]CPattern_Field) {
	slice.sort_by(fields[:], proc(a, b: CPattern_Field) -> bool { return int(a.name) < int(b.name) })
}

sort_type_fields_by_name :: proc(fields: ^[dynamic]CType_Field) {
	slice.sort_by(fields[:], proc(a, b: CType_Field) -> bool { return int(a.name) < int(b.name) })
}

generate_derive_stubs :: proc(d: ^CDecl_Newtype, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> [dynamic]CDecl {
	result := make([dynamic]CDecl, 0, 8)
	type_name_str := base.intern_get(interner, d.name.name)
	generated: map[string]bool
	generated = make(map[string]bool, 8)
	defer delete(generated)

	for dt in d.derive_targets {
		derive_name_str := base.intern_get(interner, dt)
		switch derive_name_str {
		case "Eq":
			stub_name := fmt.tprintf("{}_eq", type_name_str)
			if !generated[stub_name] {
				generated[stub_name] = true
				append(&result, make_derive_method_decl(d, "eq", 2, false, scope, interner, collector))
			}
		case "Clone":
			stub_name := fmt.tprintf("{}_clone", type_name_str)
			if !generated[stub_name] {
				generated[stub_name] = true
				append(&result, make_derive_method_decl(d, "clone", 1, true, scope, interner, collector))
			}
		case "Hash":
			stub_name := fmt.tprintf("{}_hash", type_name_str)
			if !generated[stub_name] {
				generated[stub_name] = true
				append(&result, make_derive_method_decl(d, "hash", 1, false, scope, interner, collector))
			}
		case "Ord":
			compare_name := fmt.tprintf("{}_compare", type_name_str)
			if !generated[compare_name] {
				generated[compare_name] = true
				append(&result, make_derive_method_decl(d, "compare", 2, false, scope, interner, collector))
			}
			eq_name := fmt.tprintf("{}_eq", type_name_str)
			if !generated[eq_name] {
				generated[eq_name] = true
				append(&result, make_derive_method_decl(d, "eq", 2, false, scope, interner, collector))
			}
		case: // unknown derive target — skip
		}
	}

	return result
}

make_derive_method_decl :: proc(
	d: ^CDecl_Newtype,
	method_name: string,
	param_count: int,
	wrap_in_newtype: bool,
	scope: ^Canonicalize_Scope,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
) -> CDecl {
	type_name_str := base.intern_get(interner, d.name.name)
	fn_name_str := fmt.tprintf("{}_{}", type_name_str, method_name)
	fn_name_id := base.intern(interner, fn_name_str)

	fn_canonical_name := base.Canonical_Name{module = d.name.module, name = fn_name_id, is_local = true}
	scope.local_names[fn_name_id] = fn_canonical_name
	scope.local_kinds[fn_name_id] = .Const

	param_name_strs := [2]string{"x", "y"}
	params := make([dynamic]CFunc_Param, 0, param_count)
	param_ids := make([dynamic]base.Intern_ID, 0, param_count)
	for i in 0..<param_count {
		p_id := base.intern(interner, param_name_strs[i])
		append(&param_ids, p_id)
		append(&params, CFunc_Param{name = p_id, span = d.span})
	}

	inner_id := base.intern(interner, "inner")
	method_id := base.intern(interner, method_name)

	x_name := base.Canonical_Name{module = base.NO_NAME, name = param_ids[0], is_local = true}
	x_expr := new(CExpr_Name)
	x_expr^ = CExpr_Name{name = x_name, span = d.span}

	inner_canonical := base.Canonical_Name{module = base.NO_NAME, name = inner_id, is_local = true}
	x_inner := new(CExpr_Method_Call)
	x_inner^ = CExpr_Method_Call{
		receiver = x_expr,
		method = inner_canonical,
		args = make([dynamic]CExpr, 0),
		span = d.span,
	}

	method_canonical := base.Canonical_Name{module = base.NO_NAME, name = method_id, is_local = true}
	method_args := make([dynamic]CExpr, 0, param_count - 1)
	for i in 1..<param_count {
		y_name := base.Canonical_Name{module = base.NO_NAME, name = param_ids[i], is_local = true}
		y_expr := new(CExpr_Name)
		y_expr^ = CExpr_Name{name = y_name, span = d.span}
		y_inner := new(CExpr_Method_Call)
		y_inner^ = CExpr_Method_Call{
			receiver = y_expr,
			method = inner_canonical,
			args = make([dynamic]CExpr, 0),
			span = d.span,
		}
		append(&method_args, y_inner)
	}

	method_call := new(CExpr_Method_Call)
	method_call^ = CExpr_Method_Call{
		receiver = x_inner,
		method = method_canonical,
		args = method_args,
		span = d.span,
	}

	body_expr: CExpr
	if wrap_in_newtype {
		tag_payload := make([dynamic]CExpr, 1)
		tag_payload[0] = method_call
		tag := new(CExpr_Tag)
		tag^ = CExpr_Tag{name = d.name, payload = tag_payload, span = d.span}
		body_expr = tag
	} else {
		body_expr = method_call
	}

	lambda := new(CExpr_Lambda)
	lambda^ = CExpr_Lambda{
		type_params = make([dynamic]frontend.Type_Param, 0),
		params = params,
		return_type = nil,
		effects = nil,
		where_clauses = make([dynamic]frontend.Where_Clause, 0),
		body = body_expr,
		span = d.span,
	}

	cdecl := new(CDecl_Const)
	cdecl^ = CDecl_Const{
		name = fn_canonical_name,
		is_pub = d.is_pub,
		is_effectful = false,
		body = lambda,
		derive_targets = make([dynamic]base.Intern_ID, 0, 4),
		span = d.span,
	}

	return cdecl
}

// Method sugar desugaring: receiver.par_map!(args) → Parallel!.map!(receiver, args)

desugar_parallel_method :: proc(method_str: string, receiver: CExpr, args: [dynamic]CExpr, span: base.Source_Span, scope: ^Canonicalize_Scope, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) -> CExpr {
	op_name: string
	is_sugar := false

	if method_str == "par_map!" {
		op_name = "map!"; is_sugar = true
	} else if method_str == "par_filter!" {
		op_name = "filter!"; is_sugar = true
	} else if method_str == "par_reduce!" {
		op_name = "reduce!"; is_sugar = true
	} else if method_str == "par_for_each!" {
		op_name = "for_each!"; is_sugar = true
	} else if method_str == "par_all!" {
		op_name = "all!"; is_sugar = true
	} else if method_str == "par_any!" {
		op_name = "any!"; is_sugar = true
	}

	if !is_sugar {
		return nil
	}

	parallel_name := base.Canonical_Name{module = base.NO_NAME, name = base.intern(interner, "Parallel"), is_local = true}
	op_id := base.intern(interner, op_name)

	// Build args: [receiver, ...original_args]
	perform_args := make([dynamic]CExpr, 0, len(args) + 1)
	append(&perform_args, receiver)
	for a in args {
		append(&perform_args, a)
	}

	perform := new(CExpr_Perform)
	perform^ = CExpr_Perform{effect = parallel_name, op = op_id, args = perform_args, span = span}
	return perform
}

// Collect lowercase type variable names from a CType tree.
// Used to infer generic type parameters from type annotations.
collect_type_variable_names :: proc(t: CType, seen: ^map[base.Intern_ID]bool, names: ^[dynamic]base.Intern_ID) {
	switch ty in t {
	case ^CType_Variable:
		if _, exists := seen[ty.name]; !exists {
			seen[ty.name] = true
			append(names, ty.name)
		}
	case ^CType_Primitive:
	case ^CType_Wildcard:
	case ^CType_Self:
	case ^CType_Function:
		for p in ty.params {
			collect_type_variable_names(p, seen, names)
		}
		collect_type_variable_names(ty.return_, seen, names)
		if ty.effects != nil {
			collect_type_variable_names(ty.effects^, seen, names)
		}
	case ^CType_Record:
		for f in ty.fields {
			collect_type_variable_names(f.type, seen, names)
		}
	case ^CType_Tag_Union:
		for tag in ty.tags {
			for p in tag.payload {
				collect_type_variable_names(p, seen, names)
			}
		}
	case ^CType_Applied:
		for a in ty.args {
			collect_type_variable_names(a, seen, names)
		}
	case ^CType_Effect_Row:
		for e in ty.effects {
			for a in e.type_args {
				collect_type_variable_names(a, seen, names)
			}
		}
	}
}

// Infer type_params from type annotations and merge where clause constraints.
// Lowercase type variables in annotations become implicit type parameters.
infer_type_params :: proc(
	params: []CFunc_Param,
	return_type: ^CType,
	effects: ^CType,
	existing_type_params: [dynamic]frontend.Type_Param,
	where_clauses: [dynamic]frontend.Where_Clause,
) -> [dynamic]frontend.Type_Param {
	seen := make(map[base.Intern_ID]bool)
	inferred_names := make([dynamic]base.Intern_ID, 0, 4)
	defer delete(seen)
	defer delete(inferred_names)

	// Mark names already in existing type_params as seen
	for tp in existing_type_params {
		seen[tp.name] = true
	}

	// Scan param type annotations
	for p in params {
		if p.type_ann != nil {
			collect_type_variable_names(p.type_ann^, &seen, &inferred_names)
		}
	}

	// Scan return type
	if return_type != nil {
		collect_type_variable_names(return_type^, &seen, &inferred_names)
	}

	// Scan effect type
	if effects != nil {
		collect_type_variable_names(effects^, &seen, &inferred_names)
	}

	// Also mark where clause type params as seen (they may not appear in annotations
	// but should still be type params)
	for wc in where_clauses {
		if _, exists := seen[wc.type_param]; !exists {
			seen[wc.type_param] = true
			append(&inferred_names, wc.type_param)
		}
	}

	// Build result: existing type params + inferred ones
	result := make([dynamic]frontend.Type_Param, 0, len(existing_type_params) + len(inferred_names))
	for tp in existing_type_params {
		append(&result, tp)
	}
	for name in inferred_names {
		append(&result, frontend.Type_Param{name = name})
	}

	// Merge where clause constraints into type params
	for wc in where_clauses {
		for &tp in result {
			if tp.name == wc.type_param {
				found := false
				for c in tp.constraints {
					if c == wc.trait_name {
						found = true
						break
					}
				}
				if !found {
					append(&tp.constraints, wc.trait_name)
				}
				break
			}
		}
	}

	return result
}

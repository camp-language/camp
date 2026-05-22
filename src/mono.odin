package camp

import "core:fmt"

Mono_Env :: struct {
	store:             ^Type_Store,
	interner:          ^Intern_Table,
	specializations:   map[string]Canonical_Name,
	decl_map:          map[Canonical_Name]^TDecl_Const,
	worklist:         [dynamic]Mono_Item,
	output_decls:      [dynamic]TDecl,
}

Mono_Item :: struct {
	original:  Canonical_Name,
	type_args: map[Intern_ID]Type_Var_ID,
	span:      Source_Span,
}

mono :: proc(tfile: TFile, store: ^Type_Store, interner: ^Intern_Table) -> TFile {
	env: Mono_Env
	env.store = store
	env.interner = interner
	env.specializations = make(map[string]Canonical_Name, 32)
	env.decl_map = make(map[Canonical_Name]^TDecl_Const, 32)
	env.worklist = make([dynamic]Mono_Item, 0, 16)
	env.output_decls = make([dynamic]TDecl, 0, len(tfile.decls))

	for decl in tfile.decls {
		if d, ok := decl.(^TDecl_Const); ok {
			env.decl_map[d.name] = d
		}
		walk_decl_for_call_sites(decl, &env)
	}

	for len(env.worklist) > 0 {
		item := pop(&env.worklist)
		key := specialization_key(item, store, env.interner)
		if _, exists := env.specializations[key]; exists {
			continue
		}

		specialized_name := mangle(item.original, item.type_args, env.interner, store)
		env.specializations[key] = specialized_name

		specialized_decl := specialize_decl(item, &env)
		if specialized_decl != nil {
			append(&env.output_decls, TDecl(specialized_decl))
		}
	}

	for decl in tfile.decls {
		rewritten := rewrite_calls_in_decl(decl, env.specializations, &env)
		append(&env.output_decls, rewritten)
	}

	result: TFile
	result.path = tfile.path
	result.span = tfile.span
	result.decls = env.output_decls
	result.imports = tfile.imports

	delete(env.specializations)
	delete(env.decl_map)
	delete(env.worklist)
	return result
}

specialization_key :: proc(item: Mono_Item, store: ^Type_Store, interner: ^Intern_Table) -> string {
	name_str := intern_get(interner, item.original.name)
	module_str := intern_get(interner, item.original.module)
	base := fmt.tprintf("{}.{}", module_str, name_str)

	if len(item.type_args) == 0 {
		return base
	}

	type_parts: [dynamic]string
	for _, type_var in item.type_args {
		resolved := resolve_var(store, type_var)
		v := get_var(store, resolved)
		type_str := format_type_var_for_key(store, v, interner)
		append(&type_parts, type_str)
	}

	key := base
	for tp in type_parts {
		key = fmt.tprintf("{}${}", key, tp)
	}

	delete(type_parts)
	return key
}

format_type_var_for_key :: proc(store: ^Type_Store, v: ^Type_Var, interner: ^Intern_Table) -> string {
	link := v.link
	for {
		linked, is_id := link.(Type_Var_ID)
		if !is_id do break
		resolved := resolve_var(store, linked)
		v2 := get_var(store, resolved)
		link = v2.link
	}

	inf, is_inf := link.(Inferred_Type)
	if !is_inf do return "var"

	switch inf.tag {
	case .Primitive:
		return intern_get(interner, inf.primitive_name)
	case .Newtype:
		return intern_get(interner, inf.primitive_name)
	case .Constructor:
		return intern_get(interner, inf.primitive_name)
	case .Handle:
		return "Handle"
	case .Record_Row:
		return "Record"
	case .Tag_Union_Row:
		return "Tag"
	case .Effect_Row:
		return "Eff"
	case .Function:
		return "Fn"
	}
	return "var"
}

mangle :: proc(name: Canonical_Name, type_args: map[Intern_ID]Type_Var_ID, interner: ^Intern_Table, store: ^Type_Store) -> Canonical_Name {
	name_str := intern_get(interner, name.name)
	base := name_str

	if len(type_args) > 0 {
		parts: [dynamic]string
		for _, type_var in type_args {
			resolved := resolve_var(store, type_var)
			v := get_var(store, resolved)
			type_str := format_type_var_for_key(store, v, interner)
			append(&parts, type_str)
		}
		for tp in parts {
			base = fmt.tprintf("{}${}", base, tp)
		}
		delete(parts)
	}

	mangled_name := intern(interner, base)
	return Canonical_Name{
		module = name.module,
		name = mangled_name,
		is_local = name.is_local,
	}
}

specialize_decl :: proc(item: Mono_Item, env: ^Mono_Env) -> ^TDecl_Const {
	original, exists := env.decl_map[item.original]
	if !exists {
		return nil
	}

	specialized_name := mangle(item.original, item.type_args, env.interner, env.store)

	decl := new(TDecl_Const)
	decl.name = specialized_name
	decl.is_pub = original.is_pub
	decl.is_effectful = original.is_effectful
	decl.type_ann = original.type_ann
	decl.derive_targets = original.derive_targets
	decl.span = item.span

	decl.body = substitute_types_in_expr(original.body, item.type_args, env)

	decl.type_ = substitute_ir_type(original.type_, item.type_args, env)
	decl.eff_ = substitute_ir_type(original.eff_, item.type_args, env)

	return decl
}

substitute_types_in_expr :: proc(expr: TExpr, type_args: map[Intern_ID]Type_Var_ID, env: ^Mono_Env) -> TExpr {
	switch e in expr {
	case ^TExpr_Int:
		return expr

	case ^TExpr_Float:
		return expr

	case ^TExpr_String:
		return expr

	case ^TExpr_Bool:
		return expr

	case ^TExpr_Tag:
		payload_t := make([dynamic]TExpr, len(e.payload))
		for i in 0..<len(e.payload) {
			payload_t[i] = substitute_types_in_expr(e.payload[i], type_args, env)
		}
		result := new(TExpr_Tag)
		result.name = e.name
		result.payload = payload_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Record:
		fields_t := make([dynamic]TRecord_Field, len(e.fields))
		for i in 0..<len(e.fields) {
			fields_t[i] = TRecord_Field{
				name = e.fields[i].name,
				value = substitute_types_in_expr(e.fields[i].value, type_args, env),
				span = e.fields[i].span,
			}
		}
		result := new(TExpr_Record)
		result.fields = fields_t
		result.rest = substitute_types_in_expr(e.rest, type_args, env)
		result.is_open = e.is_open
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_List:
		elements_t := make([dynamic]TExpr, len(e.elements))
		for i in 0..<len(e.elements) {
			elements_t[i] = substitute_types_in_expr(e.elements[i], type_args, env)
		}
		result := new(TExpr_List)
		result.elements = elements_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Name:
		result := new(TExpr_Name)
		result.name = e.name
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Call:
		args_t := make([dynamic]TExpr, len(e.args))
		for i in 0..<len(e.args) {
			args_t[i] = substitute_types_in_expr(e.args[i], type_args, env)
		}
		result := new(TExpr_Call)
		result.callee = substitute_types_in_expr(e.callee, type_args, env)
		result.args = args_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Method_Call:
		sub_receiver := substitute_types_in_expr(e.receiver, type_args, env)
		sub_args := make([dynamic]TExpr, len(e.args))
		for i in 0..<len(e.args) {
			sub_args[i] = substitute_types_in_expr(e.args[i], type_args, env)
		}

		sub_type := substitute_ir_type(e.type_, type_args, env)
		sub_eff := substitute_ir_type(e.eff_, type_args, env)

		receiver_type_name := resolve_mono_type(sub_receiver, type_args, env)
		if receiver_type_name != NO_NAME {
			impl_name, found := find_method_impl(receiver_type_name, e.method.name, env.store)
			if found {
				callee := new(TExpr_Name)
				callee^ = TExpr_Name{
					name = impl_name,
					type_ = sub_type,
					eff_ = sub_eff,
					span = e.span,
				}

				all_args := make([dynamic]TExpr, len(sub_args) + 1)
				append(&all_args, sub_receiver)
				for a in sub_args {
					append(&all_args, a)
				}

				result := new(TExpr_Call)
				result^ = TExpr_Call{
					callee = TExpr(callee),
					args = all_args,
					type_ = sub_type,
					eff_ = sub_eff,
					span = e.span,
				}
				return TExpr(result)
			}
		}

		result := new(TExpr_Method_Call)
		result^ = TExpr_Method_Call{
			receiver = sub_receiver,
			method = e.method,
			args = sub_args,
			type_ = sub_type,
			eff_ = sub_eff,
			resolved_ = e.resolved_,
			span = e.span,
		}
		return TExpr(result)

	case ^TExpr_Lambda:
		substituted_params := make([dynamic]TFunc_Param, len(e.params))
		for i in 0..<len(e.params) {
			substituted_params[i] = TFunc_Param{
				name = e.params[i].name,
				type_ = substitute_ir_type(e.params[i].type_, type_args, env),
				eff_ = substitute_ir_type(e.params[i].eff_, type_args, env),
				span = e.params[i].span,
			}
		}
		result := new(TExpr_Lambda)
		result.type_params = e.type_params
		result.params = substituted_params
		result.return_type = substitute_ir_type(e.return_type, type_args, env)
		result.effects = substitute_ir_type(e.effects, type_args, env)
		result.body = substitute_types_in_expr(e.body, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Block:
		statements_t := make([dynamic]TExpr, len(e.statements))
		for i in 0..<len(e.statements) {
			statements_t[i] = substitute_types_in_expr(e.statements[i], type_args, env)
		}
		result := new(TExpr_Block)
		result.statements = statements_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_If:
		result := new(TExpr_If)
		result.condition = substitute_types_in_expr(e.condition, type_args, env)
		result.then_branch = substitute_types_in_expr(e.then_branch, type_args, env)
		result.else_branch = substitute_types_in_expr(e.else_branch, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Match:
		arms_t := make([dynamic]TMatch_Arm, len(e.arms))
		for i in 0..<len(e.arms) {
			arms_t[i] = TMatch_Arm{
				pattern = e.arms[i].pattern,
				body = substitute_types_in_expr(e.arms[i].body, type_args, env),
				span = e.arms[i].span,
			}
		}
		result := new(TExpr_Match)
		result.scrutinee = substitute_types_in_expr(e.scrutinee, type_args, env)
		result.arms = arms_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_BinOp:
		result := new(TExpr_BinOp)
		result.op = e.op
		result.left = substitute_types_in_expr(e.left, type_args, env)
		result.right = substitute_types_in_expr(e.right, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_PrefixOp:
		result := new(TExpr_PrefixOp)
		result.op = e.op
		result.operand = substitute_types_in_expr(e.operand, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Field_Access:
		result := new(TExpr_Field_Access)
		result.record = substitute_types_in_expr(e.record, type_args, env)
		result.field = e.field
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Record_Update:
		updates_t := make([dynamic]TRecord_Field, len(e.updates))
		for i in 0..<len(e.updates) {
			updates_t[i] = TRecord_Field{
				name = e.updates[i].name,
				value = substitute_types_in_expr(e.updates[i].value, type_args, env),
				span = e.updates[i].span,
			}
		}
		result := new(TExpr_Record_Update)
		result.rest = substitute_types_in_expr(e.rest, type_args, env)
		result.updates = updates_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Assign:
		result := new(TExpr_Assign)
		result.target = substitute_types_in_expr(e.target, type_args, env)
		result.value = substitute_types_in_expr(e.value, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Return:
		result := new(TExpr_Return)
		result.value = substitute_types_in_expr(e.value, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Crash:
		result := new(TExpr_Crash)
		result.message = substitute_types_in_expr(e.message, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Interpolate:
		parts_t := make([dynamic]TExpr, len(e.parts))
		for i in 0..<len(e.parts) {
			parts_t[i] = substitute_types_in_expr(e.parts[i], type_args, env)
		}
		result := new(TExpr_Interpolate)
		result.parts = parts_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)

	case ^TExpr_Handle:
		arms_t := make([dynamic]THandler_Arm, len(e.arms))
		for i in 0..<len(e.arms) {
			arms_t[i] = THandler_Arm{
				op = e.arms[i].op,
				resume_id = e.arms[i].resume_id,
				op_params = e.arms[i].op_params,
				body = substitute_types_in_expr(e.arms[i].body, type_args, env),
				span = e.arms[i].span,
			}
		}
		result := new(TExpr_Handle)
		result.effect = e.effect
		result.is_shallow = e.is_shallow
		result.body = substitute_types_in_expr(e.body, type_args, env)
		result.arms = arms_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return TExpr(result)
	}
	return expr
}

substitute_ir_type :: proc(ir_type: IR_Type, type_args: map[Intern_ID]Type_Var_ID, env: ^Mono_Env) -> IR_Type {
	if len(type_args) == 0 {
		return ir_type
	}

	resolved := resolve_var(env.store, ir_type.type_id)
	v := get_var(env.store, resolved)

	if _, is_inf := v.link.(Inferred_Type); is_inf {
		return ir_type
	}

	for tp_name, concrete_var_id in type_args {
		tp_binding, has_binding := env.store.bindings[tp_name]
		if !has_binding {
			continue
		}
		tp_resolved := resolve_var(env.store, tp_binding)
		if tp_resolved == resolved {
			concrete_resolved := resolve_var(env.store, concrete_var_id)
			cv := get_var(env.store, concrete_resolved)
			wasm_type := ir_type.wasm_type
			if cinf, cis_inf := cv.link.(Inferred_Type); cis_inf && cinf.tag == .Newtype {
				wasm_type = lower_type(env.store, cinf.inner_id).wasm_type
			}
			return IR_Type{wasm_type = wasm_type, type_id = concrete_resolved}
		}
	}

	return ir_type
}

get_expr_ir_type :: proc(expr: TExpr) -> IR_Type {
	switch e in expr {
	case ^TExpr_Int:
		return e.type_
	case ^TExpr_Float:
		return e.type_
	case ^TExpr_String:
		return e.type_
	case ^TExpr_Bool:
		return e.type_
	case ^TExpr_Tag:
		return e.type_
	case ^TExpr_Record:
		return e.type_
	case ^TExpr_List:
		return e.type_
	case ^TExpr_Name:
		return e.type_
	case ^TExpr_Call:
		return e.type_
	case ^TExpr_Method_Call:
		return e.type_
	case ^TExpr_Lambda:
		return e.type_
	case ^TExpr_Block:
		return e.type_
	case ^TExpr_If:
		return e.type_
	case ^TExpr_Match:
		return e.type_
	case ^TExpr_BinOp:
		return e.type_
	case ^TExpr_PrefixOp:
		return e.type_
	case ^TExpr_Field_Access:
		return e.type_
	case ^TExpr_Record_Update:
		return e.type_
	case ^TExpr_Assign:
		return e.type_
	case ^TExpr_Return:
		return e.type_
	case ^TExpr_Crash:
		return e.type_
	case ^TExpr_Interpolate:
		return e.type_
	case ^TExpr_Handle:
		return e.type_
	}
	return IR_Type{}
}

resolve_mono_type :: proc(expr: TExpr, type_args: map[Intern_ID]Type_Var_ID, env: ^Mono_Env) -> Intern_ID {
	ir_type := get_expr_ir_type(expr)

	subbed := substitute_ir_type(ir_type, type_args, env)
	resolved := resolve_var(env.store, subbed.type_id)
	v := get_var(env.store, resolved)

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return NO_NAME
	}

	#partial switch inf.tag {
	case .Primitive, .Newtype, .Constructor:
		return inf.primitive_name
	}

	return NO_NAME
}

find_method_impl :: proc(type_name: Intern_ID, method_name: Intern_ID, store: ^Type_Store) -> (Canonical_Name, bool) {
	impl, found := find_trait_impl_by_method(store, type_name, method_name)
	if !found {
		return Canonical_Name{}, false
	}
	impl_name, has := impl.methods[method_name]
	if !has {
		return Canonical_Name{}, false
	}
	return impl_name, true
}

walk_decl_for_call_sites :: proc(decl: TDecl, env: ^Mono_Env) {
	switch d in decl {
	case ^TDecl_Const:
		walk_expr_for_call_sites(d.body, env)
	case ^TDecl_Effect:
		for op in d.operations {
			for p in op.params {
			}
		}
	case ^TDecl_Trait:
	case ^TDecl_Alias:
	case ^TDecl_Newtype:
	case ^TDecl_Import:
	case ^TDecl_Test:
		walk_expr_for_call_sites(d.body, env)
	case ^TDecl_Expect:
		walk_expr_for_call_sites(d.condition, env)
	}
}

walk_expr_for_call_sites :: proc(expr: TExpr, env: ^Mono_Env) {
	switch e in expr {
	case ^TExpr_Call:
		#partial switch callee in e.callee {
		case ^TExpr_Name:
			if d, ok := env.decl_map[callee.name]; ok {
				#partial switch body in d.body {
				case ^TExpr_Lambda:
					if len(body.type_params) > 0 {
						callee_type_id, has_type := env.store.bindings[callee.name.name]
						if has_type {
							resolved_id := resolve_var(env.store, callee_type_id)
							callee_v := get_var(env.store, resolved_id)
							if inf, is_inf := callee_v.link.(Inferred_Type); is_inf && inf.tag == .Function {
								type_args := make(map[Intern_ID]Type_Var_ID, len(body.type_params))
								param_idx := 0
								for tp in body.type_params {
									if param_idx < len(inf.param_ids) {
										concrete := resolve_var(env.store, inf.param_ids[param_idx])
										type_args[tp.name] = concrete
										param_idx += 1
									}
								}
								if len(type_args) > 0 {
									append(&env.worklist, Mono_Item{
										original = callee.name,
										type_args = type_args,
										span = e.span,
									})
								} else {
									delete(type_args)
								}
							}
						}
					}
				case:
				}
			}
		case:
		}
		walk_expr_for_call_sites(e.callee, env)
		for arg in e.args {
			walk_expr_for_call_sites(arg, env)
		}
	case ^TExpr_Method_Call:
		walk_expr_for_call_sites(e.receiver, env)
		for arg in e.args {
			walk_expr_for_call_sites(arg, env)
		}
	case ^TExpr_Lambda:
		walk_expr_for_call_sites(e.body, env)
	case ^TExpr_Block:
		for stmt in e.statements {
			walk_expr_for_call_sites(stmt, env)
		}
	case ^TExpr_If:
		walk_expr_for_call_sites(e.condition, env)
		walk_expr_for_call_sites(e.then_branch, env)
		walk_expr_for_call_sites(e.else_branch, env)
	case ^TExpr_Match:
		walk_expr_for_call_sites(e.scrutinee, env)
		for arm in e.arms {
			walk_expr_for_call_sites(arm.body, env)
		}
	case ^TExpr_BinOp:
		walk_expr_for_call_sites(e.left, env)
		walk_expr_for_call_sites(e.right, env)
	case ^TExpr_PrefixOp:
		walk_expr_for_call_sites(e.operand, env)
	case ^TExpr_Field_Access:
		walk_expr_for_call_sites(e.record, env)
	case ^TExpr_Record_Update:
		walk_expr_for_call_sites(e.rest, env)
	case ^TExpr_Assign:
		walk_expr_for_call_sites(e.target, env)
		walk_expr_for_call_sites(e.value, env)
	case ^TExpr_Return:
		walk_expr_for_call_sites(e.value, env)
	case ^TExpr_Crash:
		walk_expr_for_call_sites(e.message, env)
	case ^TExpr_Interpolate:
		for part in e.parts {
			walk_expr_for_call_sites(part, env)
		}
	case ^TExpr_Handle:
		walk_expr_for_call_sites(e.body, env)
	case ^TExpr_Int, ^TExpr_Float, ^TExpr_String, ^TExpr_Bool,
		^TExpr_Tag, ^TExpr_Record, ^TExpr_List, ^TExpr_Name:
	}
}

rewrite_calls_in_decl :: proc(decl: TDecl, specializations: map[string]Canonical_Name, env: ^Mono_Env) -> TDecl {
	switch d in decl {
	case ^TDecl_Const:
		new_body := rewrite_calls_in_expr(d.body, specializations, env)
		d.body = new_body
	case ^TDecl_Test:
		new_body := rewrite_calls_in_expr(d.body, specializations, env)
		d.body = new_body
	case ^TDecl_Expect:
		new_cond := rewrite_calls_in_expr(d.condition, specializations, env)
		d.condition = new_cond
	case ^TDecl_Effect, ^TDecl_Trait, ^TDecl_Alias, ^TDecl_Newtype, ^TDecl_Import:
	}
	return decl
}

rewrite_calls_in_expr :: proc(expr: TExpr, specializations: map[string]Canonical_Name, env: ^Mono_Env) -> TExpr {
	switch e in expr {
	case ^TExpr_Call:
		for i in 0..<len(e.args) {
			e.args[i] = rewrite_calls_in_expr(e.args[i], specializations, env)
		}
		e.callee = rewrite_calls_in_expr(e.callee, specializations, env)
	case ^TExpr_Method_Call:
		for i in 0..<len(e.args) {
			e.args[i] = rewrite_calls_in_expr(e.args[i], specializations, env)
		}
		e.receiver = rewrite_calls_in_expr(e.receiver, specializations, env)

		no_type_args := map[Intern_ID]Type_Var_ID{}
		receiver_type_name := resolve_mono_type(e.receiver, no_type_args, env)
		if receiver_type_name != NO_NAME {
			impl_name, found := find_method_impl(receiver_type_name, e.method.name, env.store)
			if found {
				callee := new(TExpr_Name)
				callee^ = TExpr_Name{
					name = impl_name,
					type_ = e.type_,
					eff_ = e.eff_,
					span = e.span,
				}

				all_args := make([dynamic]TExpr, len(e.args) + 1)
				append(&all_args, e.receiver)
				for a in e.args {
					append(&all_args, a)
				}

				result := new(TExpr_Call)
				result^ = TExpr_Call{
					callee = TExpr(callee),
					args = all_args,
					type_ = e.type_,
					eff_ = e.eff_,
					span = e.span,
				}
				return TExpr(result)
			}
		}
	case ^TExpr_Lambda:
		e.body = rewrite_calls_in_expr(e.body, specializations, env)
	case ^TExpr_Block:
		for i in 0..<len(e.statements) {
			e.statements[i] = rewrite_calls_in_expr(e.statements[i], specializations, env)
		}
	case ^TExpr_If:
		e.condition = rewrite_calls_in_expr(e.condition, specializations, env)
		e.then_branch = rewrite_calls_in_expr(e.then_branch, specializations, env)
		e.else_branch = rewrite_calls_in_expr(e.else_branch, specializations, env)
	case ^TExpr_Match:
		e.scrutinee = rewrite_calls_in_expr(e.scrutinee, specializations, env)
		for i in 0..<len(e.arms) {
			e.arms[i].body = rewrite_calls_in_expr(e.arms[i].body, specializations, env)
		}
	case ^TExpr_BinOp:
		e.left = rewrite_calls_in_expr(e.left, specializations, env)
		e.right = rewrite_calls_in_expr(e.right, specializations, env)
	case ^TExpr_PrefixOp:
		e.operand = rewrite_calls_in_expr(e.operand, specializations, env)
	case ^TExpr_Field_Access:
		e.record = rewrite_calls_in_expr(e.record, specializations, env)
	case ^TExpr_Record_Update:
		e.rest = rewrite_calls_in_expr(e.rest, specializations, env)
	case ^TExpr_Assign:
		e.target = rewrite_calls_in_expr(e.target, specializations, env)
		e.value = rewrite_calls_in_expr(e.value, specializations, env)
	case ^TExpr_Return:
		e.value = rewrite_calls_in_expr(e.value, specializations, env)
	case ^TExpr_Crash:
		e.message = rewrite_calls_in_expr(e.message, specializations, env)
	case ^TExpr_Interpolate:
		for i in 0..<len(e.parts) {
			e.parts[i] = rewrite_calls_in_expr(e.parts[i], specializations, env)
		}
	case ^TExpr_Handle:
		e.body = rewrite_calls_in_expr(e.body, specializations, env)
	case ^TExpr_Int, ^TExpr_Float, ^TExpr_String, ^TExpr_Bool,
		^TExpr_Tag, ^TExpr_Record, ^TExpr_List, ^TExpr_Name:
	}
	return expr
}
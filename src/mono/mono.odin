package mono

import "camp:base"
import "camp:semantics"
import "core:fmt"
import "core:strings"

Mono_Env :: struct {
	store:           ^semantics.Type_Store,
	interner:        ^base.Intern_Table,
	specializations: map[string]base.Canonical_Name,
	decl_map:        map[base.Canonical_Name]^semantics.TDecl_Const,
	newtype_map:     map[base.Canonical_Name]^semantics.TDecl_Newtype,
	worklist:        [dynamic]Mono_Item,
	output_decls:    [dynamic]semantics.TDecl,
}

Mono_Item :: struct {
	original:  base.Canonical_Name,
	type_args: map[base.Intern_ID]base.Type_Var_ID,
	span:      base.Source_Span,
}

mono :: proc(
	tfile: semantics.TFile,
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
) -> semantics.TFile {
	env: Mono_Env
	env.store = store
	env.interner = interner
	env.specializations = make(map[string]base.Canonical_Name, 32)
	env.decl_map = make(map[base.Canonical_Name]^semantics.TDecl_Const, 32)
	env.newtype_map = make(map[base.Canonical_Name]^semantics.TDecl_Newtype, 16)
	env.worklist = make([dynamic]Mono_Item, 0, 16)
	env.output_decls = make([dynamic]semantics.TDecl, 0, len(tfile.decls))

	for decl in tfile.decls {
		if d, ok := decl.(^semantics.TDecl_Const); ok {
			env.decl_map[d.name] = d
		} else if d, ok := decl.(^semantics.TDecl_Newtype); ok {
			env.newtype_map[d.name] = d
		}
		walk_decl_for_call_sites(decl, &env)
	}

	for len(env.worklist) > 0 {
		item := pop(&env.worklist)
		key := specialization_key(item, store, env.interner)
		if _, exists := env.specializations[key]; exists {
			delete(item.type_args)
			delete(key)
			continue
		}

		specialized_name := mangle(item.original, item.type_args, env.interner, store)
		env.specializations[key] = specialized_name

		specialized_decl := specialize_decl(item, &env)
		if specialized_decl != nil {
			append(&env.output_decls, semantics.TDecl(specialized_decl))
			walk_expr_for_call_sites(specialized_decl.body, &env)
		} else {
			specialized_newtype := specialize_newtype(item, &env)
			if specialized_newtype != nil {
				append(&env.output_decls, semantics.TDecl(specialized_newtype))
			}
		}
		delete(item.type_args)
	}

	for decl in tfile.decls {
		// Skip generic const decls — they've been specialized
		if d, ok := decl.(^semantics.TDecl_Const); ok {
			if lambda, ok := d.body.(^semantics.TExpr_Lambda); ok && len(lambda.type_params) > 0 {
				continue
			}
		}
		rewritten := rewrite_calls_in_decl(decl, env.specializations, &env)
		append(&env.output_decls, rewritten)
	}

	result: semantics.TFile
	result.path = tfile.path
	result.span = tfile.span
	result.decls = env.output_decls
	result.imports = tfile.imports

	delete(env.specializations)
	delete(env.decl_map)
	delete(env.newtype_map)
	delete(env.worklist)
	return result
}

specialization_key :: proc(
	item: Mono_Item,
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
) -> string {
	b: strings.Builder
	strings.builder_init_len_cap(&b, 0, 64)
	defer strings.builder_destroy(&b)

	name_str := base.intern_get(interner, item.original.name)
	if item.original.module != base.NO_NAME {
		module_str := base.intern_get(interner, item.original.module)
		strings.write_string(&b, module_str)
		strings.write_string(&b, ".")
		strings.write_string(&b, name_str)
	} else {
		strings.write_string(&b, name_str)
	}

	if len(item.type_args) > 0 {
		type_parts: [dynamic]string
		for _, type_var in item.type_args {
			resolved := semantics.resolve_var(store, type_var)
			v := &store.vars[int(resolved)]
			type_str := format_type_var_for_key(store, v, interner)
			append(&type_parts, type_str)
		}
		for tp in type_parts {
			strings.write_string(&b, "$")
			strings.write_string(&b, tp)
		}
		delete(type_parts)
	}

	return strings.clone(strings.to_string(b))
}

format_type_var_for_key :: proc(
	store: ^semantics.Type_Store,
	v: ^semantics.Type_Var,
	interner: ^base.Intern_Table,
) -> string {
	link := v.link
	for {
		linked, is_id := link.(base.Type_Var_ID)
		if !is_id do break
		resolved := semantics.resolve_var(store, linked)
		v2 := &store.vars[int(resolved)]
		link = v2.link
	}

	inf, is_inf := link.(semantics.Inferred_Type)
	if !is_inf do return "var"

	switch v in inf {
	case semantics.Inferred_Primitive:
		return base.intern_get(interner, v.primitive_name)
	case semantics.Inferred_Newtype:
		return base.intern_get(interner, v.primitive_name)
	case semantics.Inferred_Constructor:
		return base.intern_get(interner, v.primitive_name)
	case semantics.Inferred_Handle:
		return "Handle"
	case semantics.Inferred_Record_Row:
		return "Record"
	case semantics.Inferred_Tag_Union_Row:
		return "Tag"
	case semantics.Inferred_Effect_Row:
		return "Eff"
	case semantics.Inferred_Tuple:
		return "Tuple"
	case semantics.Inferred_Function:
		return "Fn"
	}
	return "var"
}

// Extract concrete type args for a generic function call by walking the original
// generic type tree and the instantiated call-site type tree in parallel.
//
// The positional mapping (type_params[i] → param_ids[i]) only works when type
// params correspond 1:1 with value params (e.g. id = |x: a| -> a { x }).
// For non-trivial cases like map = |f: a -> b, xs: List(a)| -> List(b),
// param_ids[0] is the type of f (a function), not the type param a.
//
// After instantiate(), the type tree structure is preserved — only leaf type
// vars are replaced with fresh copies. So we walk both trees in parallel:
// when the original tree has a leaf matching a type param's Type_Var_ID,
// the corresponding leaf in the instantiated tree gives the concrete type.
extract_type_args :: proc(
	callee: ^semantics.TExpr_Name,
	generic_lambda: ^semantics.TExpr_Lambda,
	env: ^Mono_Env,
) -> map[base.Intern_ID]base.Type_Var_ID {
	type_args := make(map[base.Intern_ID]base.Type_Var_ID, len(generic_lambda.type_params))
	if len(generic_lambda.type_params) == 0 {
		return type_args
	}

	// Collect type param var IDs from store.bindings
	tp_var_ids := make(map[base.Type_Var_ID]base.Intern_ID, len(generic_lambda.type_params))
	for tp in generic_lambda.type_params {
		if binding, ok := env.store.bindings[tp.name]; ok {
			tp_var_ids[binding] = tp.name
		}
	}

	if len(tp_var_ids) == 0 {
		return type_args
	}

	// Get the original generic function type
	orig_type_id, has_orig := env.store.bindings[callee.name.name]
	if !has_orig {
		return type_args
	}

	// Get the instantiated call-site type
	inst_type_id := callee.type_.type_id
	if inst_type_id == base.Type_Var_ID(-1) {
		return type_args
	}

	// Walk both type trees in parallel, collecting type param → concrete mappings
	find_type_params_in_trees(env.store, orig_type_id, inst_type_id, tp_var_ids, &type_args)

	delete(tp_var_ids)
	return type_args
}

find_type_params_in_trees :: proc(
	store: ^semantics.Type_Store,
	orig_id: base.Type_Var_ID,
	inst_id: base.Type_Var_ID,
	tp_var_ids: map[base.Type_Var_ID]base.Intern_ID,
	type_args: ^map[base.Intern_ID]base.Type_Var_ID,
) {
	orig_resolved := semantics.resolve_var(store, orig_id)
	inst_resolved := semantics.resolve_var(store, inst_id)

	// If the original resolves to a type param, the instantiated side gives the concrete type
	if tp_name, is_tp := tp_var_ids[orig_resolved]; is_tp {
		concrete := inst_resolved
		// Follow links to get the truly resolved concrete type
		v := &store.vars[int(concrete)]
		if linked_id, is_link := v.link.(base.Type_Var_ID); is_link {
			concrete = semantics.resolve_var(store, linked_id)
		}
		type_args[tp_name] = concrete
		return
	}

	orig_v := &store.vars[int(orig_resolved)]
	inst_v := &store.vars[int(inst_resolved)]

	orig_inf, orig_is_inf := orig_v.link.(semantics.Inferred_Type)
	inst_inf, inst_is_inf := inst_v.link.(semantics.Inferred_Type)
	if !orig_is_inf || !inst_is_inf {
		return
	}

	// Walk both inferred types in parallel
	switch orig_link in orig_inf {
	case semantics.Inferred_Function:
		inst_link, ok := inst_inf.(semantics.Inferred_Function)
		if !ok do return
		for i in 0 ..< min(len(orig_link.param_ids), len(inst_link.param_ids)) {
			find_type_params_in_trees(
				store,
				orig_link.param_ids[i],
				inst_link.param_ids[i],
				tp_var_ids,
				type_args,
			)
		}
		find_type_params_in_trees(
			store,
			orig_link.return_id,
			inst_link.return_id,
			tp_var_ids,
			type_args,
		)
		find_type_params_in_trees(
			store,
			orig_link.effect_id,
			inst_link.effect_id,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Newtype:
		inst_link, ok := inst_inf.(semantics.Inferred_Newtype)
		if !ok do return
		for i in 0 ..< min(len(orig_link.param_ids), len(inst_link.param_ids)) {
			find_type_params_in_trees(
				store,
				orig_link.param_ids[i],
				inst_link.param_ids[i],
				tp_var_ids,
				type_args,
			)
		}
		find_type_params_in_trees(
			store,
			orig_link.inner_id,
			inst_link.inner_id,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Tag_Union_Row:
		inst_link, ok := inst_inf.(semantics.Inferred_Tag_Union_Row)
		if !ok do return
		for i in 0 ..< min(len(orig_link.tag_entries), len(inst_link.tag_entries)) {
			for j in 0 ..< min(
				len(orig_link.tag_entries[i].payload),
				len(inst_link.tag_entries[i].payload),
			) {
				find_type_params_in_trees(
					store,
					orig_link.tag_entries[i].payload[j],
					inst_link.tag_entries[i].payload[j],
					tp_var_ids,
					type_args,
				)
			}
		}
		find_type_params_in_trees(
			store,
			orig_link.tag_rest,
			inst_link.tag_rest,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Record_Row:
		inst_link, ok := inst_inf.(semantics.Inferred_Record_Row)
		if !ok do return
		for i in 0 ..< min(len(orig_link.record_fields), len(inst_link.record_fields)) {
			find_type_params_in_trees(
				store,
				orig_link.record_fields[i].var,
				inst_link.record_fields[i].var,
				tp_var_ids,
				type_args,
			)
		}
		find_type_params_in_trees(
			store,
			orig_link.record_rest,
			inst_link.record_rest,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Effect_Row:
		inst_link, ok := inst_inf.(semantics.Inferred_Effect_Row)
		if !ok do return
		for i in 0 ..< min(len(orig_link.effects), len(inst_link.effects)) {
			for j in 0 ..< min(
				len(orig_link.effects[i].type_args),
				len(inst_link.effects[i].type_args),
			) {
				find_type_params_in_trees(
					store,
					orig_link.effects[i].type_args[j],
					inst_link.effects[i].type_args[j],
					tp_var_ids,
					type_args,
				)
			}
		}
		find_type_params_in_trees(
			store,
			orig_link.rest_id,
			inst_link.rest_id,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Handle:
		inst_link, ok := inst_inf.(semantics.Inferred_Handle)
		if !ok do return
		find_type_params_in_trees(
			store,
			orig_link.inner_id,
			inst_link.inner_id,
			tp_var_ids,
			type_args,
		)
		find_type_params_in_trees(
			store,
			orig_link.effect_id,
			inst_link.effect_id,
			tp_var_ids,
			type_args,
		)

	case semantics.Inferred_Tuple:
		inst_link, ok := inst_inf.(semantics.Inferred_Tuple)
		if !ok do return
		for i in 0 ..< min(len(orig_link.element_types), len(inst_link.element_types)) {
			find_type_params_in_trees(
				store,
				orig_link.element_types[i],
				inst_link.element_types[i],
				tp_var_ids,
				type_args,
			)
		}

	case semantics.Inferred_Primitive, semantics.Inferred_Constructor:
	// Leaf types — no type params inside
	}
}

mangle :: proc(
	name: base.Canonical_Name,
	type_args: map[base.Intern_ID]base.Type_Var_ID,
	interner: ^base.Intern_Table,
	store: ^semantics.Type_Store,
) -> base.Canonical_Name {
	name_str := base.intern_get(interner, name.name)
	base_str: string = name_str

	if len(type_args) > 0 {
		b: strings.Builder
		strings.builder_init_len_cap(&b, 0, 64)
		strings.write_string(&b, name_str)

		parts: [dynamic]string
		for _, type_var in type_args {
			resolved := semantics.resolve_var(store, type_var)
			v := &store.vars[int(resolved)]
			type_str := format_type_var_for_key(store, v, interner)
			append(&parts, type_str)
		}
		for tp in parts {
			strings.write_string(&b, "$")
			strings.write_string(&b, tp)
		}
		delete(parts)

		base_str = strings.clone(strings.to_string(b))
		strings.builder_destroy(&b)
	}

	mangled_name := base.intern(interner, base_str)
	delete(base_str)
	return base.Canonical_Name{module = name.module, name = mangled_name, is_local = name.is_local}
}

specialize_newtype :: proc(item: Mono_Item, env: ^Mono_Env) -> ^semantics.TDecl_Newtype {
	original, exists := env.newtype_map[item.original]
	if !exists {
		return nil
	}

	specialized_name := mangle(item.original, item.type_args, env.interner, env.store)

	decl := new(semantics.TDecl_Newtype)
	decl.name = specialized_name
	decl.is_pub = original.is_pub
	decl.type_params = make([dynamic]base.Intern_ID, 0)
	decl.inner_type = original.inner_type
	decl.type_ = substitute_ir_type(original.type_, item.type_args, env)
	decl.derive_targets = make([dynamic]base.Intern_ID, len(original.derive_targets))
	copy(decl.derive_targets[:], original.derive_targets[:])
	decl.span = item.span

	return decl
}

specialize_decl :: proc(item: Mono_Item, env: ^Mono_Env) -> ^semantics.TDecl_Const {
	original, exists := env.decl_map[item.original]
	if !exists {
		return nil
	}

	specialized_name := mangle(item.original, item.type_args, env.interner, env.store)

	decl := new(semantics.TDecl_Const)
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

substitute_types_in_expr :: proc(
	expr: semantics.TExpr,
	type_args: map[base.Intern_ID]base.Type_Var_ID,
	env: ^Mono_Env,
) -> semantics.TExpr {
	switch e in expr {
	case ^semantics.TExpr_Int:
		return expr

	case ^semantics.TExpr_Float:
		return expr

	case ^semantics.TExpr_String:
		return expr

	case ^semantics.TExpr_Bool:
		return expr

	case ^semantics.TExpr_Char:
		return expr

	case ^semantics.TExpr_Todo:
		if e.message != nil {
			msg := substitute_types_in_expr(e.message, type_args, env)
			result := new(semantics.TExpr_Todo)
			result^ = e^
			result.message = msg
			return semantics.TExpr(result)
		}
		return expr

	case ^semantics.TExpr_Tag:
		payload_t := make([dynamic]semantics.TExpr, len(e.payload))
		for i in 0 ..< len(e.payload) {
			payload_t[i] = substitute_types_in_expr(e.payload[i], type_args, env)
		}
		result := new(semantics.TExpr_Tag)
		result.name = e.name
		result.payload = payload_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Record:
		fields_t := make([dynamic]semantics.TRecord_Field, len(e.fields))
		for i in 0 ..< len(e.fields) {
			fields_t[i] = semantics.TRecord_Field {
				name  = e.fields[i].name,
				value = substitute_types_in_expr(e.fields[i].value, type_args, env),
				span  = e.fields[i].span,
			}
		}
		result := new(semantics.TExpr_Record)
		result.fields = fields_t
		result.rest = substitute_types_in_expr(e.rest, type_args, env)
		result.is_open = e.is_open
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)
	case ^semantics.TExpr_Tuple:
		elements_t := make([dynamic]semantics.TExpr, len(e.elements))
		for i in 0 ..< len(e.elements) {
			elements_t[i] = substitute_types_in_expr(e.elements[i], type_args, env)
		}
		result := new(semantics.TExpr_Tuple)
		result.elements = elements_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)
	case ^semantics.TExpr_List:
		elements_t := make([dynamic]semantics.TExpr, len(e.elements))
		for i in 0 ..< len(e.elements) {
			elements_t[i] = substitute_types_in_expr(e.elements[i], type_args, env)
		}
		result := new(semantics.TExpr_List)
		result.elements = elements_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Name:
		result := new(semantics.TExpr_Name)
		result.name = e.name
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Call:
		args_t := make([dynamic]semantics.TExpr, len(e.args))
		for i in 0 ..< len(e.args) {
			args_t[i] = substitute_types_in_expr(e.args[i], type_args, env)
		}
		result := new(semantics.TExpr_Call)
		result.callee = substitute_types_in_expr(e.callee, type_args, env)
		result.args = args_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Method_Call:
		sub_receiver := substitute_types_in_expr(e.receiver, type_args, env)
		sub_args := make([dynamic]semantics.TExpr, len(e.args))
		for i in 0 ..< len(e.args) {
			sub_args[i] = substitute_types_in_expr(e.args[i], type_args, env)
		}

		sub_type := substitute_ir_type(e.type_, type_args, env)
		sub_eff := substitute_ir_type(e.eff_, type_args, env)

		receiver_type_name := resolve_mono_type(sub_receiver, type_args, env)
		if receiver_type_name != base.NO_NAME {
			impl_name, found := find_method_impl(receiver_type_name, e.method.name, env.store)
			if found {
				callee := new(semantics.TExpr_Name)
				callee^ = semantics.TExpr_Name {
					name  = impl_name,
					type_ = sub_type,
					eff_  = sub_eff,
					span  = e.span,
				}

				all_args := make([dynamic]semantics.TExpr, len(sub_args) + 1)
				append(&all_args, sub_receiver)
				for a in sub_args {
					append(&all_args, a)
				}

				result := new(semantics.TExpr_Call)
				result^ = semantics.TExpr_Call {
					callee = semantics.TExpr(callee),
					args   = all_args,
					type_  = sub_type,
					eff_   = sub_eff,
					span   = e.span,
				}
				return semantics.TExpr(result)
			}
		}

		result := new(semantics.TExpr_Method_Call)
		result^ = semantics.TExpr_Method_Call {
			receiver  = sub_receiver,
			method    = e.method,
			args      = sub_args,
			type_     = sub_type,
			eff_      = sub_eff,
			resolved_ = e.resolved_,
			span      = e.span,
		}
		return semantics.TExpr(result)

	case ^semantics.TExpr_Lambda:
		substituted_params := make([dynamic]semantics.TFunc_Param, len(e.params))
		for i in 0 ..< len(e.params) {
			substituted_params[i] = semantics.TFunc_Param {
				name  = e.params[i].name,
				type_ = substitute_ir_type(e.params[i].type_, type_args, env),
				eff_  = substitute_ir_type(e.params[i].eff_, type_args, env),
				span  = e.params[i].span,
			}
		}
		result := new(semantics.TExpr_Lambda)
		result.type_params = e.type_params
		result.params = substituted_params
		result.return_type = substitute_ir_type(e.return_type, type_args, env)
		result.effects = substitute_ir_type(e.effects, type_args, env)
		result.body = substitute_types_in_expr(e.body, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Block:
		statements_t := make([dynamic]semantics.TExpr, len(e.statements))
		for i in 0 ..< len(e.statements) {
			statements_t[i] = substitute_types_in_expr(e.statements[i], type_args, env)
		}
		result := new(semantics.TExpr_Block)
		result.statements = statements_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_If:
		result := new(semantics.TExpr_If)
		result.condition = substitute_types_in_expr(e.condition, type_args, env)
		result.then_branch = substitute_types_in_expr(e.then_branch, type_args, env)
		result.else_branch = substitute_types_in_expr(e.else_branch, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Match:
		arms_t := make([dynamic]semantics.TMatch_Arm, len(e.arms))
		for i in 0 ..< len(e.arms) {
			arms_t[i] = semantics.TMatch_Arm {
				pattern = e.arms[i].pattern,
				guard   = substitute_types_in_expr(e.arms[i].guard, type_args, env) if e.arms[i].guard != nil else nil,
				body    = substitute_types_in_expr(e.arms[i].body, type_args, env),
				span    = e.arms[i].span,
			}
		}
		result := new(semantics.TExpr_Match)
		result.scrutinee = substitute_types_in_expr(e.scrutinee, type_args, env)
		result.arms = arms_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_BinOp:
		result := new(semantics.TExpr_BinOp)
		result.op = e.op
		result.left = substitute_types_in_expr(e.left, type_args, env)
		result.right = substitute_types_in_expr(e.right, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_PrefixOp:
		result := new(semantics.TExpr_PrefixOp)
		result.op = e.op
		result.operand = substitute_types_in_expr(e.operand, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Field_Access:
		result := new(semantics.TExpr_Field_Access)
		result.record = substitute_types_in_expr(e.record, type_args, env)
		result.field = e.field
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)
	case ^semantics.TExpr_Field_Index:
		result := new(semantics.TExpr_Field_Index)
		result.record = substitute_types_in_expr(e.record, type_args, env)
		result.field_index = e.field_index
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)
	case ^semantics.TExpr_Record_Update:
		updates_t := make([dynamic]semantics.TRecord_Field, len(e.updates))
		for i in 0 ..< len(e.updates) {
			updates_t[i] = semantics.TRecord_Field {
				name  = e.updates[i].name,
				value = substitute_types_in_expr(e.updates[i].value, type_args, env),
				span  = e.updates[i].span,
			}
		}
		result := new(semantics.TExpr_Record_Update)
		result.rest = substitute_types_in_expr(e.rest, type_args, env)
		result.updates = updates_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Assign:
		result := new(semantics.TExpr_Assign)
		result.target = substitute_types_in_expr(e.target, type_args, env)
		result.value = substitute_types_in_expr(e.value, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Return:
		result := new(semantics.TExpr_Return)
		result.value = substitute_types_in_expr(e.value, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Crash:
		result := new(semantics.TExpr_Crash)
		result.message = substitute_types_in_expr(e.message, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Interpolated_String:
		tparts := make([dynamic]semantics.TExpr_String_Part, 0, len(e.parts))
		for part in e.parts {
			switch p in part {
			case ^semantics.TExpr_String_Literal:
				clit := new(semantics.TExpr_String_Literal)
				clit^ = semantics.TExpr_String_Literal {
					value = p.value,
					type_ = substitute_ir_type(p.type_, type_args, env),
					eff_  = substitute_ir_type(p.eff_, type_args, env),
					span  = p.span,
				}
				append(&tparts, semantics.TExpr_String_Part(clit))
			case ^semantics.TExpr_String_Expr:
				sexpr := new(semantics.TExpr_String_Expr)
				sexpr^ = semantics.TExpr_String_Expr {
					expr         = substitute_types_in_expr(p.expr, type_args, env),
					needs_to_str = p.needs_to_str,
					display_impl = p.display_impl,
				}
				append(&tparts, semantics.TExpr_String_Part(sexpr))
			case semantics.TPattern:
			}
		}
		result := new(semantics.TExpr_Interpolated_String)
		result.parts = tparts
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Handle:
		arms_t := make([dynamic]semantics.THandler_Arm, len(e.arms))
		for i in 0 ..< len(e.arms) {
			arms_t[i] = semantics.THandler_Arm {
				op     = e.arms[i].op,
				params = e.arms[i].params,
				body   = substitute_types_in_expr(e.arms[i].body, type_args, env),
				span   = e.arms[i].span,
			}
		}
		result := new(semantics.TExpr_Handle)
		result.effects = make([dynamic]base.Canonical_Name, 0, len(e.effects))
		for eff in e.effects {
			append(&result.effects, eff)
		}
		result.body = substitute_types_in_expr(e.body, type_args, env)
		result.arms = arms_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Perform:
		args_t := make([dynamic]semantics.TExpr, len(e.args))
		for i in 0 ..< len(e.args) {
			args_t[i] = substitute_types_in_expr(e.args[i], type_args, env)
		}
		result := new(semantics.TExpr_Perform)
		result.effect = e.effect
		result.op = e.op
		result.args = args_t
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_For:
		result := new(semantics.TExpr_For)
		result.var = e.var
		result.iterable = substitute_types_in_expr(e.iterable, type_args, env)
		result.body = substitute_types_in_expr(e.body, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		return semantics.TExpr(result)

	case ^semantics.TExpr_Par:
		result := new(semantics.TExpr_Par)
		result.for_var = e.for_var
		result.for_iter = substitute_types_in_expr(e.for_iter, type_args, env)
		result.for_body = substitute_types_in_expr(e.for_body, type_args, env)
		result.type_ = substitute_ir_type(e.type_, type_args, env)
		result.eff_ = substitute_ir_type(e.eff_, type_args, env)
		result.span = e.span
		exprs := make([dynamic]semantics.TExpr, 0, len(e.expressions))
		for expr in e.expressions {
			append(&exprs, substitute_types_in_expr(expr, type_args, env))
		}
		result.expressions = exprs
		names := make([dynamic]base.Intern_ID, len(e.names))
		for idx in 0 ..< len(e.names) {
			names[idx] = e.names[idx]
		}
		result.names = names
		return semantics.TExpr(result)

	case ^semantics.TExpr_Nominal_Construct:
		payload_t := make([dynamic]semantics.TExpr, len(e.payload))
		for i in 0 ..< len(e.payload) {
			payload_t[i] = substitute_types_in_expr(e.payload[i], type_args, env)
		}
		result := new(semantics.TExpr_Nominal_Construct)
		result^ = semantics.TExpr_Nominal_Construct {
			type_name     = e.type_name,
			variant       = e.variant,
			payload       = payload_t,
			resolved_type = e.resolved_type,
			span          = e.span,
		}
		return semantics.TExpr(result)
	}
	return expr
}

substitute_ir_type :: proc(
	ir_type: base.IR_Type,
	type_args: map[base.Intern_ID]base.Type_Var_ID,
	env: ^Mono_Env,
) -> base.IR_Type {
	if len(type_args) == 0 {
		return ir_type
	}

	resolved := semantics.resolve_var(env.store, ir_type.type_id)
	v := &env.store.vars[int(resolved)]

	if _, is_inf := v.link.(semantics.Inferred_Type); is_inf {
		return ir_type
	}

	for tp_name, concrete_var_id in type_args {
		tp_binding, has_binding := env.store.bindings[tp_name]
		if !has_binding {
			continue
		}
		tp_resolved := semantics.resolve_var(env.store, tp_binding)
		if tp_resolved == resolved {
			// camp-9xi6/zmni: use lower_type to derive the full IR_Type
			// (wasm_type + is_heap) for ANY concrete type a generic param
			// monomorphizes to — tag unions, records, newtypes, etc.
			// Previously only Inferred_Newtype was handled; tag unions and
			// other types got the stale wasm_type from the IR_Type of the
			// original generic param, causing is_heap=false for heap types
			// and wrong wasm_type for immediate tag unions.
			return semantics.lower_type(env.store, concrete_var_id)
		}
	}

	return ir_type
}

get_expr_ir_type :: proc(expr: semantics.TExpr) -> base.IR_Type {
	switch e in expr {
	case ^semantics.TExpr_Int:
		return e.type_
	case ^semantics.TExpr_Float:
		return e.type_
	case ^semantics.TExpr_String:
		return e.type_
	case ^semantics.TExpr_Bool:
		return e.type_

	case ^semantics.TExpr_Char:
		return e.type_

	case ^semantics.TExpr_Todo:
		return e.type_

	case ^semantics.TExpr_Tag:
		return e.type_
	case ^semantics.TExpr_Record:
		return e.type_
	case ^semantics.TExpr_List:
		return e.type_
	case ^semantics.TExpr_Name:
		return e.type_
	case ^semantics.TExpr_Call:
		return e.type_
	case ^semantics.TExpr_Method_Call:
		return e.type_
	case ^semantics.TExpr_Lambda:
		return e.type_
	case ^semantics.TExpr_Block:
		return e.type_
	case ^semantics.TExpr_If:
		return e.type_
	case ^semantics.TExpr_Match:
		return e.type_
	case ^semantics.TExpr_BinOp:
		return e.type_
	case ^semantics.TExpr_PrefixOp:
		return e.type_
	case ^semantics.TExpr_Field_Access:
		return e.type_
	case ^semantics.TExpr_Tuple:
		return e.type_
	case ^semantics.TExpr_Field_Index:
		return e.type_
	case ^semantics.TExpr_Record_Update:
		return e.type_
	case ^semantics.TExpr_Assign:
		return e.type_
	case ^semantics.TExpr_Return:
		return e.type_
	case ^semantics.TExpr_Crash:
		return e.type_
	case ^semantics.TExpr_Interpolated_String:
		return e.type_
	case ^semantics.TExpr_Handle:
		return e.type_
	case ^semantics.TExpr_Perform:
		return e.type_
	case ^semantics.TExpr_For:
		return e.type_
	case ^semantics.TExpr_Par:
		return e.type_
	case ^semantics.TExpr_Nominal_Construct:
		return base.IR_Type{type_id = e.resolved_type}
	}
	return base.IR_Type{}
}

resolve_mono_type :: proc(
	expr: semantics.TExpr,
	type_args: map[base.Intern_ID]base.Type_Var_ID,
	env: ^Mono_Env,
) -> base.Intern_ID {
	ir_type := get_expr_ir_type(expr)

	subbed := substitute_ir_type(ir_type, type_args, env)
	resolved := semantics.resolve_var(env.store, subbed.type_id)
	v := &env.store.vars[int(resolved)]

	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf {
		return base.NO_NAME
	}

	#partial switch vi in inf {
	case semantics.Inferred_Primitive:
		return vi.primitive_name
	case semantics.Inferred_Newtype:
		return vi.primitive_name
	case semantics.Inferred_Constructor:
		return vi.primitive_name
	}

	return base.NO_NAME
}

find_method_impl :: proc(
	type_name: base.Intern_ID,
	method_name: base.Intern_ID,
	store: ^semantics.Type_Store,
) -> (
	base.Canonical_Name,
	bool,
) {
	impl, found := semantics.find_trait_impl_by_method(store, type_name, method_name)
	if !found {
		return base.Canonical_Name{}, false
	}
	impl_name, has := impl.methods[method_name]
	if !has {
		return base.Canonical_Name{}, false
	}
	return impl_name, true
}

walk_decl_for_call_sites :: proc(decl: semantics.TDecl, env: ^Mono_Env) {
	switch d in decl {
	case ^semantics.TDecl_Const:
		walk_expr_for_call_sites(d.body, env)
	case ^semantics.TDecl_Effect:
		for op in d.operations {
			for p in op.params {
			}
		}
	case ^semantics.TDecl_Effect_Alias:
	case ^semantics.TDecl_Trait:
	case ^semantics.TDecl_Alias:
	case ^semantics.TDecl_Newtype:
		// Newtypes with type params may need specialization
		if len(d.type_params) > 0 {
			type_args := make(map[base.Intern_ID]base.Type_Var_ID, len(d.type_params))
			for tp in d.type_params {
				if binding, has := env.store.bindings[tp]; has {
					type_args[tp] = binding
				}
			}
			if len(type_args) > 0 {
				append(
					&env.worklist,
					Mono_Item{original = d.name, type_args = type_args, span = d.span},
				)
			} else {
				delete(type_args)
			}
		}
	case ^semantics.TDecl_Import:
	case ^semantics.TDecl_Test:
		walk_expr_for_call_sites(d.body, env)
	case ^semantics.TDecl_Expect:
		walk_expr_for_call_sites(d.condition, env)
	case ^semantics.TDecl_Is_Impl:
	}
}

walk_expr_for_call_sites :: proc(expr: semantics.TExpr, env: ^Mono_Env) {
	switch e in expr {
	case ^semantics.TExpr_Call:
		#partial switch callee in e.callee {
		case ^semantics.TExpr_Name:
			if d, ok := env.decl_map[callee.name]; ok {
				#partial switch body in d.body {
				case ^semantics.TExpr_Lambda:
					if len(body.type_params) > 0 {
						type_args := extract_type_args(callee, body, env)
						if len(type_args) > 0 {
							item := Mono_Item {
								original  = callee.name,
								type_args = type_args,
								span      = e.span,
							}
							// Dedup check: skip if this specialization already exists,
							// preventing infinite worklist growth for recursive generics
							key := specialization_key(item, env.store, env.interner)
							if _, exists := env.specializations[key]; !exists {
								append(&env.worklist, item)
							} else {
								delete(type_args)
							}
						} else {
							delete(type_args)
						}
					}
				case ^semantics.TExpr_Int,
				     ^semantics.TExpr_Float,
				     ^semantics.TExpr_String,
				     ^semantics.TExpr_Bool,
				     ^semantics.TExpr_Char,
				     ^semantics.TExpr_Todo,
				     ^semantics.TExpr_Tag,
				     ^semantics.TExpr_Nominal_Construct,
				     ^semantics.TExpr_Record,
				     ^semantics.TExpr_Tuple,
				     ^semantics.TExpr_Field_Index,
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
			}
		case ^semantics.TExpr_Int,
		     ^semantics.TExpr_Float,
		     ^semantics.TExpr_String,
		     ^semantics.TExpr_Bool,
		     ^semantics.TExpr_Char,
		     ^semantics.TExpr_Todo,
		     ^semantics.TExpr_Tag,
		     ^semantics.TExpr_Nominal_Construct,
		     ^semantics.TExpr_Record,
		     ^semantics.TExpr_Tuple,
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
		     ^semantics.TExpr_Field_Index,
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
		walk_expr_for_call_sites(e.callee, env)
		for arg in e.args {
			walk_expr_for_call_sites(arg, env)
		}
	case ^semantics.TExpr_Method_Call:
		walk_expr_for_call_sites(e.receiver, env)
		for arg in e.args {
			walk_expr_for_call_sites(arg, env)
		}
	case ^semantics.TExpr_Lambda:
		walk_expr_for_call_sites(e.body, env)
	case ^semantics.TExpr_Block:
		for stmt in e.statements {
			walk_expr_for_call_sites(stmt, env)
		}
	case ^semantics.TExpr_If:
		walk_expr_for_call_sites(e.condition, env)
		walk_expr_for_call_sites(e.then_branch, env)
		walk_expr_for_call_sites(e.else_branch, env)
	case ^semantics.TExpr_Match:
		walk_expr_for_call_sites(e.scrutinee, env)
		for arm in e.arms {
			walk_expr_for_call_sites(arm.body, env)
		}
	case ^semantics.TExpr_BinOp:
		walk_expr_for_call_sites(e.left, env)
		walk_expr_for_call_sites(e.right, env)
	case ^semantics.TExpr_PrefixOp:
		walk_expr_for_call_sites(e.operand, env)
	case ^semantics.TExpr_Field_Access:
		walk_expr_for_call_sites(e.record, env)
	case ^semantics.TExpr_Tuple:
		for el in e.elements {
			walk_expr_for_call_sites(el, env)
		}
	case ^semantics.TExpr_Field_Index:
		walk_expr_for_call_sites(e.record, env)
	case ^semantics.TExpr_Record_Update:
		walk_expr_for_call_sites(e.rest, env)
	case ^semantics.TExpr_Assign:
		walk_expr_for_call_sites(e.target, env)
		walk_expr_for_call_sites(e.value, env)
	case ^semantics.TExpr_Return:
		walk_expr_for_call_sites(e.value, env)
	case ^semantics.TExpr_Crash:
		walk_expr_for_call_sites(e.message, env)
	case ^semantics.TExpr_Interpolated_String:
		for part in e.parts {
			switch p in part {
			case ^semantics.TExpr_String_Literal:
			case ^semantics.TExpr_String_Expr:
				walk_expr_for_call_sites(p.expr, env)
			case semantics.TPattern:
			}
		}
	case ^semantics.TExpr_Handle:
		walk_expr_for_call_sites(e.body, env)
	case ^semantics.TExpr_Perform:
		for arg in e.args {
			walk_expr_for_call_sites(arg, env)
		}
	case ^semantics.TExpr_Int,
	     ^semantics.TExpr_Float,
	     ^semantics.TExpr_String,
	     ^semantics.TExpr_Bool,
	     ^semantics.TExpr_Char,
	     ^semantics.TExpr_Todo,
	     ^semantics.TExpr_Tag,
	     ^semantics.TExpr_Nominal_Construct,
	     ^semantics.TExpr_Record,
	     ^semantics.TExpr_List,
	     ^semantics.TExpr_Name,
	     ^semantics.TExpr_For,
	     ^semantics.TExpr_Par:
	}
}

rewrite_calls_in_decl :: proc(
	decl: semantics.TDecl,
	specializations: map[string]base.Canonical_Name,
	env: ^Mono_Env,
) -> semantics.TDecl {
	switch d in decl {
	case ^semantics.TDecl_Const:
		new_body := rewrite_calls_in_expr(d.body, specializations, env)
		d.body = new_body
	case ^semantics.TDecl_Test:
		new_body := rewrite_calls_in_expr(d.body, specializations, env)
		d.body = new_body
	case ^semantics.TDecl_Expect:
		new_cond := rewrite_calls_in_expr(d.condition, specializations, env)
		d.condition = new_cond
	case ^semantics.TDecl_Newtype:
		// Substitute type params in the IR type for generic newtypes
		if len(d.type_params) > 0 {
			type_args := make(map[base.Intern_ID]base.Type_Var_ID, len(d.type_params))
			for tp in d.type_params {
				if binding, has := env.store.bindings[tp]; has {
					type_args[tp] = binding
				}
			}
			if len(type_args) > 0 {
				d.type_ = substitute_ir_type(d.type_, type_args, env)
			}
			delete(type_args)
		}
	case ^semantics.TDecl_Is_Impl:
	case ^semantics.TDecl_Effect,
	     ^semantics.TDecl_Effect_Alias,
	     ^semantics.TDecl_Trait,
	     ^semantics.TDecl_Alias,
	     ^semantics.TDecl_Import:
	}
	return decl
}

rewrite_calls_in_expr :: proc(
	expr: semantics.TExpr,
	specializations: map[string]base.Canonical_Name,
	env: ^Mono_Env,
) -> semantics.TExpr {
	switch e in expr {
	case ^semantics.TExpr_Call:
		// Rewrite generic callee names to specialized names
		if name_expr, is_name := e.callee.(^semantics.TExpr_Name); is_name {
			if d, ok := env.decl_map[name_expr.name]; ok {
				if lambda, is_lambda := d.body.(^semantics.TExpr_Lambda);
				   is_lambda && len(lambda.type_params) > 0 {
					type_args := extract_type_args(name_expr, lambda, env)
					if len(type_args) > 0 {
						item := Mono_Item {
							original  = name_expr.name,
							type_args = type_args,
							span      = e.span,
						}
						key := specialization_key(item, env.store, env.interner)
						if spec_name, ok := specializations[key]; ok {
							name_expr.name = spec_name
						}
					}
					delete(type_args)
				}
			}
		}
		for i in 0 ..< len(e.args) {
			e.args[i] = rewrite_calls_in_expr(e.args[i], specializations, env)
		}
		e.callee = rewrite_calls_in_expr(e.callee, specializations, env)
	case ^semantics.TExpr_Method_Call:
		for i in 0 ..< len(e.args) {
			e.args[i] = rewrite_calls_in_expr(e.args[i], specializations, env)
		}
		e.receiver = rewrite_calls_in_expr(e.receiver, specializations, env)

		no_type_args := map[base.Intern_ID]base.Type_Var_ID{}
		receiver_type_name := resolve_mono_type(e.receiver, no_type_args, env)
		if receiver_type_name != base.NO_NAME {
			impl_name, found := find_method_impl(receiver_type_name, e.method.name, env.store)
			if found {
				callee := new(semantics.TExpr_Name)
				callee^ = semantics.TExpr_Name {
					name  = impl_name,
					type_ = e.type_,
					eff_  = e.eff_,
					span  = e.span,
				}

				all_args := make([dynamic]semantics.TExpr, len(e.args) + 1)
				append(&all_args, e.receiver)
				for a in e.args {
					append(&all_args, a)
				}

				result := new(semantics.TExpr_Call)
				result^ = semantics.TExpr_Call {
					callee = semantics.TExpr(callee),
					args   = all_args,
					type_  = e.type_,
					eff_   = e.eff_,
					span   = e.span,
				}
				return semantics.TExpr(result)
			}
		}
	case ^semantics.TExpr_Lambda:
		e.body = rewrite_calls_in_expr(e.body, specializations, env)
	case ^semantics.TExpr_Block:
		for i in 0 ..< len(e.statements) {
			e.statements[i] = rewrite_calls_in_expr(e.statements[i], specializations, env)
		}
	case ^semantics.TExpr_If:
		e.condition = rewrite_calls_in_expr(e.condition, specializations, env)
		e.then_branch = rewrite_calls_in_expr(e.then_branch, specializations, env)
		e.else_branch = rewrite_calls_in_expr(e.else_branch, specializations, env)
	case ^semantics.TExpr_Match:
		e.scrutinee = rewrite_calls_in_expr(e.scrutinee, specializations, env)
		for i in 0 ..< len(e.arms) {
			if e.arms[i].guard != nil {
				e.arms[i].guard = rewrite_calls_in_expr(e.arms[i].guard, specializations, env)
			}
			e.arms[i].body = rewrite_calls_in_expr(e.arms[i].body, specializations, env)
		}
	case ^semantics.TExpr_BinOp:
		e.left = rewrite_calls_in_expr(e.left, specializations, env)
		e.right = rewrite_calls_in_expr(e.right, specializations, env)
	case ^semantics.TExpr_PrefixOp:
		e.operand = rewrite_calls_in_expr(e.operand, specializations, env)
	case ^semantics.TExpr_Field_Access:
		e.record = rewrite_calls_in_expr(e.record, specializations, env)
	case ^semantics.TExpr_Tuple:
		for i in 0 ..< len(e.elements) {
			e.elements[i] = rewrite_calls_in_expr(e.elements[i], specializations, env)
		}
	case ^semantics.TExpr_Field_Index:
		e.record = rewrite_calls_in_expr(e.record, specializations, env)
	case ^semantics.TExpr_Record_Update:
		e.rest = rewrite_calls_in_expr(e.rest, specializations, env)
	case ^semantics.TExpr_Assign:
		e.target = rewrite_calls_in_expr(e.target, specializations, env)
		e.value = rewrite_calls_in_expr(e.value, specializations, env)
	case ^semantics.TExpr_Return:
		e.value = rewrite_calls_in_expr(e.value, specializations, env)
	case ^semantics.TExpr_Crash:
		e.message = rewrite_calls_in_expr(e.message, specializations, env)
	case ^semantics.TExpr_Interpolated_String:
		for i in 0 ..< len(e.parts) {
			switch p in e.parts[i] {
			case ^semantics.TExpr_String_Literal:
			case ^semantics.TExpr_String_Expr:
				p.expr = rewrite_calls_in_expr(p.expr, specializations, env)
			case semantics.TPattern:
			}
		}
	case ^semantics.TExpr_Handle:
		e.body = rewrite_calls_in_expr(e.body, specializations, env)
	case ^semantics.TExpr_Perform:
		for i in 0 ..< len(e.args) {
			e.args[i] = rewrite_calls_in_expr(e.args[i], specializations, env)
		}
	case ^semantics.TExpr_Int,
	     ^semantics.TExpr_Float,
	     ^semantics.TExpr_String,
	     ^semantics.TExpr_Bool,
	     ^semantics.TExpr_Char,
	     ^semantics.TExpr_Todo,
	     ^semantics.TExpr_Tag,
	     ^semantics.TExpr_Nominal_Construct,
	     ^semantics.TExpr_Record,
	     ^semantics.TExpr_List,
	     ^semantics.TExpr_Name,
	     ^semantics.TExpr_For,
	     ^semantics.TExpr_Par:
	}
	return expr
}


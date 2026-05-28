package semantics

import "core:fmt"

import "camp:base"
import "camp:diagnostics"
import "camp:frontend"

typecheck_decl :: proc(decl: CDecl, env: ^Type_Env, store: ^Type_Store) -> TDecl {
	switch d in decl {
	case ^CDecl_Const:
		check_shadow(env, d.name.name, store, d.span)
		self_var := fresh_value_var(store, d.span)
		env.bindings[d.name.name] = self_var
		store.rec_vars[self_var] = true

		enter_level(store)
		result := typecheck_synth(d.body, env, store)

		unify(store, self_var, result.var_id)

		delete_key(&store.rec_vars, self_var)

		if d.type_ann != nil {
			ann_var := convert_type_to_var(d.type_ann, store, env)
			unify(store, result.var_id, ann_var)
		}

		if !d.is_effectful {
			resolved := resolve_var(store, result.var_id)
			v := store.vars[int(resolved)]
			if it, ok := v.link.(Inferred_Type); ok {
				if inf, ok := it.(Inferred_Function); ok {
					if effect_row_nonempty(store, inf.effect_id) {
						name_str := base.intern_get(store.interner, d.name.name)
						effects_str := format_effect_row(store, inf.effect_id)
						diagnostics.collector_add_diag(
							store.collector,
							diagnostics.diag_effectful_naming(name_str, effects_str, d.span),
						)
					}
				}
			}
		}

		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		env.bindings[d.name.name] = result.var_id

		type_ir := lower_type(store, result.var_id)
		eff_ir := lower_effect_type(store, result.effects)
		td := new(TDecl_Const)
		td^ = TDecl_Const {
			name           = d.name,
			is_pub         = d.is_pub,
			is_effectful   = d.is_effectful,
			type_ann       = d.type_ann,
			body           = result.texpr,
			type_          = type_ir,
			eff_           = eff_ir,
			derive_targets = d.derive_targets,
			span           = d.span,
		}
		return TDecl(td)

	case ^CDecl_Effect:
		append(&store.declared_effects, d.name.name)
		enter_level(store)
		for tp in d.type_params {
			tv := fresh_value_var(store, d.span)
			if tp.is_effect {
				tv = fresh_effect_row(store, d.span)
			}
			env.bindings[tp.name] = tv
		}
		op_sigs := make([dynamic]Effect_Op_Sig, 0, len(d.operations))
		ops_t := make([dynamic]TEffect_Op, len(d.operations))
		for op, i in d.operations {
			param_types := make([]base.Type_Var_ID, len(op.params), store.allocator)
			params_t := make([dynamic]TFunc_Param, len(op.params))
			for p, j in op.params {
				if p.type_ann != nil {
					param_types[j] = convert_type_to_var(p.type_ann, store, env)
				} else {
					param_types[j] = fresh_value_var(store, d.span)
				}
				params_t[j] = TFunc_Param {
					name  = p.name,
					type_ = lower_type(store, param_types[j]),
					eff_  = lower_effect_type(store, fresh_effect_row(store, p.span)),
					span  = p.span,
				}
			}
			ret_type := fresh_value_var(store, d.span)
			if op.return_type != nil {
				ret_type = convert_type_to_var(op.return_type, store, env)
			}
			append(
				&op_sigs,
				Effect_Op_Sig {
					name = op.name,
					param_count = len(op.params),
					param_types = param_types,
					return_type = ret_type,
				},
			)
			ops_t[i] = TEffect_Op {
				name           = op.name,
				is_effectful   = op.is_effectful,
				params         = params_t,
				return_type    = lower_type(store, ret_type),
				return_effects = lower_effect_type(store, fresh_effect_row(store, op.span)),
				span           = op.span,
			}
		}
		store.effect_ops[d.name.name] = op_sigs[:]
		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		tp_t := make([dynamic]frontend.Type_Param, len(d.type_params))
		for tp, i in d.type_params {
			constraints := make([dynamic]base.Intern_ID, len(tp.constraints), store.allocator)
			for c, j in tp.constraints {
				constraints[j] = c
			}
			tp_t[i] = frontend.Type_Param {
				name        = tp.name,
				constraints = constraints,
				is_effect   = tp.is_effect,
			}
		}

		td := new(TDecl_Effect)
		td^ = TDecl_Effect {
			name        = d.name,
			is_pub      = d.is_pub,
			operations  = ops_t,
			type_params = tp_t,
			span        = d.span,
		}
		return TDecl(td)

	case ^CDecl_Effect_Alias:
		append(&store.declared_effects, d.name.name)
		convert_type_to_var(d.target, store, env)
		td := new(TDecl_Effect_Alias)
		td^ = TDecl_Effect_Alias {
			name   = d.name,
			target = d.target,
			is_pub = d.is_pub,
			span   = d.span,
		}
		return TDecl(td)

	case ^CDecl_Trait:
		typecheck_trait_decl(d, env, store)
		td := new(TDecl_Trait)
		td^ = TDecl_Trait {
			name    = d.name,
			is_pub  = d.is_pub,
			parent  = d.parent,
			methods = make([dynamic]TTrait_Method, len(d.methods)),
			span    = d.span,
		}
		for m, i in d.methods {
			td.methods[i] = TTrait_Method {
				name        = m.name,
				params      = make([dynamic]TFunc_Param, len(m.params)),
				return_type = lower_type(store, fresh_value_var(store, m.span)),
				effects     = lower_effect_type(store, fresh_effect_row(store, m.span)),
				span        = m.span,
			}
			for p, j in m.params {
				if p.type_ann != nil {
					pv := convert_type_to_var(p.type_ann, store, env)
					td.methods[i].params[j] = TFunc_Param {
						name  = p.name,
						type_ = lower_type(store, pv),
						eff_  = lower_effect_type(store, fresh_effect_row(store, p.span)),
						span  = p.span,
					}
				} else {
					td.methods[i].params[j] = TFunc_Param {
						name  = p.name,
						type_ = lower_type(store, fresh_value_var(store, p.span)),
						eff_  = lower_effect_type(store, fresh_effect_row(store, p.span)),
						span  = p.span,
					}
				}
			}
		}
		return TDecl(td)

	case ^CDecl_Alias:
		convert_type_to_var(d.target, store, env)
		td := new(TDecl_Alias)
		td^ = TDecl_Alias {
			name   = d.name,
			is_pub = d.is_pub,
			target = d.target,
			span   = d.span,
		}
		if d.target != nil && ctype_contains_self(d.target^) {
			methods := extract_trait_methods_from_ctype(d.target, store, env)
			trait_module := d.name.module
			if trait_module == base.NO_NAME {
				trait_module = env.current_module
			}
			trait_info := Trait_Info {
				name    = d.name.name,
				module  = trait_module,
				parent  = 0,
				methods = methods,
			}
			store.trait_registry[d.name.name] = trait_info
			trait_var := fresh_value_var(store, d.span)
			env.bindings[d.name.name] = trait_var
			store.bindings[d.name.name] = trait_var
		}
		return TDecl(td)

	case ^CDecl_Newtype:
		typecheck_newtype_decl(d, env, store)
		nt_var, has_nt := env.bindings[d.name.name]
		if !has_nt {
			nt_var = store.bindings[d.name.name]
		}
		td := new(TDecl_Newtype)
		td^ = TDecl_Newtype {
			name           = d.name,
			is_pub         = d.is_pub,
			type_params    = d.type_params,
			inner_type     = d.inner_type,
			type_          = lower_type(store, nt_var),
			derive_targets = d.derive_targets,
			span           = d.span,
		}
		return TDecl(td)

	case ^CDecl_Test:
		result := typecheck_synth(d.body, env, store)
		td := new(TDecl_Test)
		td^ = TDecl_Test {
			name = d.name,
			body = result.texpr,
			span = d.span,
		}
		return TDecl(td)

	case ^CDecl_Expect:
		result := typecheck_synth(d.condition, env, store)
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, base.Source_Span_ZERO)
		unify(store, result.var_id, bool_var)
		td := new(TDecl_Expect)
		td^ = TDecl_Expect {
			condition = result.texpr,
			span      = d.span,
		}
		return TDecl(td)

	case ^CDecl_Import:
		td := new(TDecl_Import)
		td^ = TDecl_Import {
			deferred = d.deferred,
			span     = d.span,
		}
		return TDecl(td)

	case ^CDecl_Is_Impl:
		methods := make([dynamic]TIs_Method, len(d.methods))
		for m, i in d.methods {
			body_result := typecheck_synth(m.body, env, store)
			methods[i] = TIs_Method {
				name   = m.name,
				params = make([dynamic]TFunc_Param, 0),
				body   = body_result.texpr,
				type_  = lower_type(store, body_result.var_id),
				eff_   = lower_effect_type(store, body_result.effects),
				is_pub = false,
				span   = m.span,
			}
		}
		td := new(TDecl_Is_Impl)
		td^ = TDecl_Is_Impl {
			type_name  = d.type_name,
			trait_name = d.trait_name,
			methods    = methods,
			span       = d.span,
		}
		type_module := d.type_name.module
		if type_module == base.NO_NAME {
			type_module = env.current_module
		}
		ok := verify_trait_conformance(
			d.type_name.name,
			type_module,
			d.trait_name.name,
			d.span,
			store,
			env,
		)
		if !ok {
			// Conformance check already emitted diagnostics.
			// Continue with the impl so downstream passes don't crash on nil.
		}
		return TDecl(td)
	}
	unreachable()
}

typecheck_newtype_decl :: proc(d: ^CDecl_Newtype, env: ^Type_Env, store: ^Type_Store) {
	param_vars := make([dynamic]base.Type_Var_ID, 0, len(d.type_params))
	enter_level(store)

	for tp in d.type_params {
		tv := fresh_value_var(store, d.span)
		append(&param_vars, tv)
		env.bindings[tp] = tv
	}

	inner_type_var := convert_type_to_var(d.inner_type, store, env)

	owned_tags := make([dynamic]base.Intern_ID, 0, 8)
	inner_resolved := store.vars[int(resolve_var(store, inner_type_var))]
	if inf, is_inf := inner_resolved.link.(Inferred_Type); is_inf {
		if tu_inf, tu_ok := inf.(Inferred_Tag_Union_Row); tu_ok {
			for te in tu_inf.tag_entries {
				append(&owned_tags, te.name)
			}
		}
	}

	param_ids_slice := make([]base.Intern_ID, len(d.type_params), store.allocator)
	for i in 0 ..< len(d.type_params) {
		param_ids_slice[i] = d.type_params[i]
	}

	nt_var := fresh_value_var(store, d.span)
	link_var(
		store,
		nt_var,
		Inferred_Newtype {
			primitive_name = d.name.name,
			arity = len(d.type_params),
			param_ids = param_vars[:],
			inner_id = inner_type_var,
		},
	)

	for i := 0; i < len(d.type_params); i += 1 {
		delete_key(&env.bindings, d.type_params[i])
	}

	level := store.current_level
	exit_level(store)
	generalize_at_level(store, level)

	check_shadow(env, d.name.name, store, d.span)
	env.bindings[d.name.name] = nt_var
	store.bindings[d.name.name] = nt_var

	owned_tags_slice := make([]base.Intern_ID, len(owned_tags), store.allocator)
	for i in 0 ..< len(owned_tags) {
		owned_tags_slice[i] = owned_tags[i]
	}

	defining_module := d.name.module
	if defining_module == base.NO_NAME {
		defining_module = env.current_module
	}

	store.newtype_decls[d.name.name] = Newtype_Decl_Info {
		name         = d.name.name,
		module       = defining_module,
		pub_variants = d.pub_variants,
		type_params  = param_ids_slice[:],
		inner_type   = inner_type_var,
		owned_tags   = owned_tags_slice[:],
	}

	delete(param_vars)
	delete(owned_tags)
}

typecheck_trait_decl :: proc(d: ^CDecl_Trait, env: ^Type_Env, store: ^Type_Store) {
	methods := make([]Trait_Method_Info, len(d.methods))
	for i in 0 ..< len(d.methods) {
		m := d.methods[i]
		self_var := fresh_value_var(store, m.span)
		param_types := make([dynamic]base.Type_Var_ID, 0, len(m.params) + 1)
		append(&param_types, self_var)

		for p in m.params {
			if p.type_ann != nil {
				param_var := convert_type_to_var(p.type_ann, store, env)
				append(&param_types, param_var)
			} else {
				param_var := fresh_value_var(store, p.span)
				append(&param_types, param_var)
			}
		}

		return_type := fresh_value_var(store, m.span)
		if m.return_type != nil {
			return_type = convert_type_to_var(m.return_type, store, env)
		}

		methods[i] = Trait_Method_Info {
			name        = m.name,
			param_types = param_types[:],
			return_type = return_type,
		}
	}

	trait_info := Trait_Info {
		name    = d.name.name,
		module  = d.name.module,
		parent  = d.parent,
		methods = methods,
	}

	store.trait_registry[d.name.name] = trait_info

	trait_var := fresh_value_var(store, d.span)
	env.bindings[d.name.name] = trait_var
	store.bindings[d.name.name] = trait_var
}

verify_trait_conformance :: proc(
	type_name: base.Intern_ID,
	type_module: base.Intern_ID,
	trait_name: base.Intern_ID,
	span: base.Source_Span,
	store: ^Type_Store,
	env: ^Type_Env,
) -> bool {
	trait_info, ok := store.trait_registry[trait_name]
	if !ok {
		trait_str := base.intern_get(store.interner, trait_name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_internal(
				fmt.tprintf("trait `{}` not found in registry", trait_str),
				span,
			),
		)
		return false
	}

	if type_module != trait_info.module && type_module != base.NO_NAME {
		type_str := base.intern_get(store.interner, type_name)
		trait_str := base.intern_get(store.interner, trait_name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_orphan_rule_violation(type_str, trait_str, span),
		)
		return false
	}

	for impl in store.trait_impls {
		if impl.trait_name == trait_name && impl.type_name == type_name {
			type_str := base.intern_get(store.interner, type_name)
			trait_str := base.intern_get(store.interner, trait_name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_overlapping_instance(type_str, trait_str, span),
			)
			return false
		}
	}

	required_traits := collect_all_traits(trait_name, store.trait_registry)
	defer delete(required_traits)

	for req_trait_name in required_traits {
		req_info := store.trait_registry[req_trait_name]
		for method in req_info.methods {
			impl_fn_name := fmt.tprintf(
				"{}_{}",
				base.intern_get(store.interner, type_name),
				base.intern_get(store.interner, method.name),
			)
			impl_fn_id := base.intern(store.interner, impl_fn_name)

			impl_fn_var: base.Type_Var_ID
			found := false
			for name_id, var_id in store.bindings {
				if name_id == impl_fn_id {
					found = true
					impl_fn_var = var_id
					break
				}
			}
			if !found {
				for name_id, var_id in env.bindings {
					if name_id == impl_fn_id {
						found = true
						impl_fn_var = var_id
						break
					}
				}
			}
			if !found {
				type_str := base.intern_get(store.interner, type_name)
				req_trait_str := base.intern_get(store.interner, req_trait_name)
				method_str := base.intern_get(store.interner, method.name)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_missing_trait_method(
						type_str,
						req_trait_str,
						method_str,
						span,
					),
				)
				return false
			}

			clone_subst := make(map[base.Type_Var_ID]base.Type_Var_ID, 8)
			defer delete(clone_subst)

			expected_params := store_alloc(store, base.Type_Var_ID, len(method.param_types))
			for i in 0 ..< len(method.param_types) {
				expected_params[i] = deep_clone_type(
					store,
					method.param_types[i],
					span,
					&clone_subst,
				)
			}

			type_var := store.bindings[type_name]
			unify(store, expected_params[0], type_var)

			expected_return := deep_clone_type(store, method.return_type, span, &clone_subst)
			expected_effect := fresh_effect_row(store, span)

			expected_fn_var := fresh_value_var(store, span)
			link_var(
				store,
				expected_fn_var,
				Inferred_Function {
					param_ids = expected_params,
					return_id = expected_return,
					effect_id = expected_effect,
				},
			)

			expected_sig := format_type_var(store, expected_fn_var)
			actual_sig := format_type_var(store, impl_fn_var)

			diag_count_before := len(store.collector.diagnostics)
			unify_ok := unify(store, impl_fn_var, expected_fn_var)

			if !unify_ok {
				for len(store.collector.diagnostics) > diag_count_before {
					d := &store.collector.diagnostics[len(store.collector.diagnostics) - 1]
					switch d.category {
					case .Warning:
						store.collector.warning_count -= 1
					case .Error:
						store.collector.error_count -= 1
					case .Internal:
						store.collector.internal_count -= 1
					}
					delete(d.labels)
					delete(d.hints)
					pop(&store.collector.diagnostics)
				}

				type_str := base.intern_get(store.interner, type_name)
				req_trait_str := base.intern_get(store.interner, req_trait_name)
				method_str := base.intern_get(store.interner, method.name)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_trait_method_signature_mismatch(
						type_str,
						req_trait_str,
						method_str,
						expected_sig,
						actual_sig,
						span,
					),
				)
				return false
			}
		}
	}

	methods := make(map[base.Intern_ID]base.Canonical_Name, len(trait_info.methods))
	for method in trait_info.methods {
		impl_fn_name := fmt.tprintf(
			"{}_{}",
			base.intern_get(store.interner, type_name),
			base.intern_get(store.interner, method.name),
		)
		impl_fn_id := base.intern(store.interner, impl_fn_name)
		methods[method.name] = base.Canonical_Name {
			module   = type_module,
			name     = impl_fn_id,
			is_local = false,
		}
	}

	impl := Trait_Impl {
		trait_name  = trait_name,
		type_name   = type_name,
		type_module = type_module,
		methods     = methods,
	}
	append(&store.trait_impls, impl)

	return true
}

ctype_contains_self :: proc(t: CType) -> bool {
	#partial switch ty in t {
	case ^CType_Self:
		return true
	case ^CType_Record:
		for f in ty.fields {
			if ctype_contains_self(f.type) {
				return true
			}
		}
	case ^CType_Function:
		for p in ty.params {
			if ctype_contains_self(p) {
				return true
			}
		}
		return ctype_contains_self(ty.return_)
	case ^CType_Tag_Union:
		for tg in ty.tags {
			for p in tg.payload {
				if ctype_contains_self(p) {
					return true
				}
			}
		}
	case ^CType_Applied:
		for a in ty.args {
			if ctype_contains_self(a) {
				return true
			}
		}
	case ^CType_Primitive, ^CType_Variable, ^CType_Wildcard, ^CType_Effect_Row:
		return false
	}
	return false
}

convert_ctype_self_aware :: proc(
	t: CType,
	self_var: base.Type_Var_ID,
	store: ^Type_Store,
	env: ^Type_Env,
) -> base.Type_Var_ID {
	#partial switch ty in t {
	case ^CType_Self:
		return self_var
	case ^CType_Primitive,
	     ^CType_Applied,
	     ^CType_Function,
	     ^CType_Record,
	     ^CType_Tag_Union,
	     ^CType_Effect_Row,
	     ^CType_Variable,
	     ^CType_Wildcard:
		return convert_type_to_var_val(t, store, env, closed = true)
	}
	return fresh_value_var(store, base.Source_Span_ZERO)
}

extract_trait_methods_from_ctype :: proc(
	t: ^CType,
	store: ^Type_Store,
	env: ^Type_Env,
) -> []Trait_Method_Info {
	#partial switch ty in t^ {
	case ^CType_Record:
		methods := make([]Trait_Method_Info, len(ty.fields))
		for f, i in ty.fields {
			self_var := fresh_value_var(store, ty.span)
			param_types := make([dynamic]base.Type_Var_ID, 0, 4)

			#partial switch ft in f.type {
			case ^CType_Function:
				for p in ft.params {
					append(&param_types, convert_ctype_self_aware(p, self_var, store, env))
				}
				methods[i] = Trait_Method_Info {
					name        = f.name,
					param_types = param_types[:],
					return_type = convert_ctype_self_aware(ft.return_, self_var, store, env),
				}
			case ^CType_Primitive,
			     ^CType_Applied,
			     ^CType_Record,
			     ^CType_Tag_Union,
			     ^CType_Effect_Row,
			     ^CType_Variable,
			     ^CType_Wildcard,
			     ^CType_Self:
				methods[i] = Trait_Method_Info {
					name        = f.name,
					param_types = param_types[:],
					return_type = self_var,
				}
			}
		}
		return methods
	case ^CType_Primitive,
	     ^CType_Applied,
	     ^CType_Function,
	     ^CType_Tag_Union,
	     ^CType_Effect_Row,
	     ^CType_Variable,
	     ^CType_Wildcard,
	     ^CType_Self:
	}
	return make([]Trait_Method_Info, 0)
}

check_constraint_violation :: proc(type_var_id: base.Type_Var_ID, store: ^Type_Store) {
	constraints, has_constraints := store.type_constraints[type_var_id]
	if !has_constraints {
		return
	}

	resolved := resolve_var(store, type_var_id)
	rv := store.vars[int(resolved)]

	impl_type_name: base.Intern_ID = base.NO_NAME
	if inf, is_inf := rv.link.(Inferred_Type); is_inf {
		if nt, nt_ok := inf.(Inferred_Newtype); nt_ok {
			impl_type_name = nt.primitive_name
		} else if prim, prim_ok := inf.(Inferred_Primitive); prim_ok {
			impl_type_name = prim.primitive_name
		} else if cons, cons_ok := inf.(Inferred_Constructor); cons_ok {
			impl_type_name = cons.primitive_name
		}
	}

	for constraint_name in constraints {
		found := false
		for impl in store.trait_impls {
			if impl.trait_name == constraint_name && impl.type_name == impl_type_name {
				found = true
				break
			}
		}
		if !found {
			constraint_str := base.intern_get(store.interner, constraint_name)
			type_name := "?"
			if impl_type_name != base.NO_NAME {
				type_name = base.intern_get(store.interner, impl_type_name)
			}
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_constraint_violation(type_name, constraint_str, rv.span),
			)
		}
	}
}


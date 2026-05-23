package camp

import "core:fmt"
import "core:strings"

Type_Env :: struct {
	bindings:        map[Intern_ID]Type_Var_ID,
	parent:          ^Type_Env,
	handled_effects: [dynamic]Intern_ID,
	current_module:  Intern_ID,
	spawned_handles: [dynamic]Source_Span,
}

Type_Result :: struct {
	var_id:  Type_Var_ID,
	effects: Type_Var_ID,
}

Synth_Result :: struct {
	var_id:  Type_Var_ID,
	effects: Type_Var_ID,
	texpr:   TExpr,
}

Pat_Result :: struct {
	var_id:  Type_Var_ID,
	effects: Type_Var_ID,
	tpat:    TPattern,
}

tc_ir_type :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> IR_Type {
	return lower_type(store, var_id)
}

tc_eff_type :: proc(store: ^Type_Store, eff_var: Type_Var_ID) -> IR_Type {
	return lower_effect_type(store, eff_var)
}

env_lookup :: proc(env: ^Type_Env, name: Intern_ID) -> (Type_Var_ID, bool) {
	current := env
	for current != nil {
		if existing, ok := current.bindings[name]; ok {
			return existing, true
		}
		current = current.parent
	}
	return Type_Var_ID(-1), false
}

check_shadow :: proc(env: ^Type_Env, name: Intern_ID, store: ^Type_Store, span: Source_Span) {
	if _, exists := env_lookup(env, name); exists {
		name_str := intern_get(store.interner, name)
		collector_add_diag(store.collector, diag_shadow(name, name_str, span))
	}
}

levenshtein_distance :: proc(a: string, b: string) -> int {
	if len(a) == 0 do return len(b)
	if len(b) == 0 do return len(a)

	a_len := len(a)
	b_len := len(b)
	dist: [dynamic][dynamic]int
	dist = make([dynamic][dynamic]int, a_len + 1)
	for i in 0..<a_len + 1 {
		dist[i] = make([dynamic]int, b_len + 1)
		dist[i][0] = i
	}
	for j in 0..<b_len + 1 {
		dist[0][j] = j
	}
	defer {
		for i in 0..<a_len + 1 {
			delete(dist[i])
		}
		delete(dist)
	}

	for i in 1..<a_len + 1 {
		for j in 1..<b_len + 1 {
			cost := 1
			if a[i-1] == b[j-1] do cost = 0
			dist[i][j] = min(
				dist[i-1][j] + 1,
				dist[i][j-1] + 1,
				dist[i-1][j-1] + cost,
			)
		}
	}

	return dist[a_len][b_len]
}

find_similar_names :: proc(name: string, env: ^Type_Env, interner: ^Intern_Table) -> [dynamic]string {
	names: [dynamic]string
	current := env
	for current != nil {
		for k, _ in current.bindings {
			k_str := intern_get(interner, k)
			if levenshtein_distance(name, k_str) <= 2 {
				append(&names, k_str)
			}
		}
		current = current.parent
	}
	return names
}

format_effect_row :: proc(store: ^Type_Store, effects: Type_Var_ID) -> string {
	rid := resolve_var(store, effects)
	rv := get_var(store, rid)
	it, is_inferred := rv.link.(Inferred_Type)
	if is_inferred && it.tag == .Effect_Row {
		if len(it.effects) == 0 do return "[]"
		builder: strings.Builder
		strings.builder_init_len_cap(&builder, 0, 64)
		strings.write_rune(&builder, '[')
		for entry, i in it.effects {
			if i > 0 do strings.write_string(&builder, " | ")
			strings.write_string(&builder, intern_get(store.interner, Intern_ID(entry.name)))
		}
		strings.write_rune(&builder, ']')
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	}
	return "[]"
}

typecheck_file :: proc(file: CFile, store: ^Type_Store, current_module: Intern_ID = NO_NAME) -> TFile {
	env: Type_Env
	env.bindings = make(map[Intern_ID]Type_Var_ID, 64)
	env.parent = nil
	env.handled_effects = make([dynamic]Intern_ID, 0, 8)
	env.current_module = current_module
	env.spawned_handles = make([dynamic]Source_Span, 0, 8)
	defer delete(env.bindings)
	defer delete(env.handled_effects)
	defer delete(env.spawned_handles)

	tdecls := make([dynamic]TDecl, 0, len(file.decls))
	imports: [dynamic]Deferred_Import
	imports = file.imports

	for decl in file.decls {
		td := typecheck_decl(decl, &env, store)
		append(&tdecls, td)
	}

	for name_id, var_id in env.bindings {
		store.bindings[name_id] = var_id
	}

	for decl in file.decls {
		#partial switch d in decl {
		case ^CDecl_Newtype:
			for tc in d.trait_conforms {
				type_mod := d.name.module
				if type_mod == NO_NAME {
					type_mod = env.current_module
				}
				verify_trait_conformance(d.name.name, type_mod, tc, d.span, store, &env)
			}
		case:
		}
	}

	return TFile{path = file.path, decls = tdecls, imports = imports, span = file.span}
}

inject_prelude :: proc(store: ^Type_Store) {
	for bt in PRELUDE_BUILTIN_TYPES {
		name_id := intern(store.interner, bt.name)
		var_id := fresh_value_var(store, Source_Span_ZERO)
		inf := Inferred_Type{tag = bt.kind, primitive_name = name_id}
		if bt.kind == .Constructor {
			inf = Inferred_Type{tag = .Constructor, primitive_name = name_id, arity = 0}
		}
		link_var(store, var_id, inf)
		store.bindings[name_id] = var_id
	}

	for ct in PRELUDE_CONSTRUCTOR_TYPES {
		name_id := intern(store.interner, ct.name)
		var_id := fresh_value_var(store, Source_Span_ZERO)
		link_var(store, var_id, Inferred_Type{tag = .Constructor, primitive_name = name_id, arity = ct.arity})
		store.bindings[name_id] = var_id
	}

	for td in PRELUDE_TAG_DECLS {
		name_id := intern(store.interner, td.name)
		var_id := fresh_value_var(store, Source_Span_ZERO)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		payload: []Type_Var_ID = nil
		if td.has_payload {
			p := fresh_value_var(store, Source_Span_ZERO)
			payload = make([]Type_Var_ID, 1, store.allocator)
			payload[0] = p
		}
		tag_entries[0] = Type_Tag_Entry{name = name_id, payload = payload}
		rest := fresh_tag_row(store, Source_Span_ZERO)
		link_var(store, var_id, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = rest,
		})
		store.bindings[name_id] = var_id
	}

	inject_prelude_effects_typecheck(store)
}

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
			ann_var := convert_type_to_var(d.type_ann, store)
			unify(store, result.var_id, ann_var)
		}

		if !d.is_effectful && effect_row_nonempty(store, result.effects) {
		name_str := intern_get(store.interner, d.name.name)
		effects_str := format_effect_row(store, result.effects)
		collector_add_diag(store.collector, diag_effectful_naming(name_str, effects_str, d.span))
		}

		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		env.bindings[d.name.name] = result.var_id

		type_ir := tc_ir_type(store, result.var_id)
		eff_ir := tc_eff_type(store, result.effects)
		td := new(TDecl_Const)
		td^ = TDecl_Const{
			name = d.name,
			is_pub = d.is_pub,
			is_effectful = d.is_effectful,
			type_ann = d.type_ann,
			body = result.texpr,
			type_ = type_ir,
			eff_ = eff_ir,
			derive_targets = d.derive_targets,
			span = d.span,
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
			param_types := make([]Type_Var_ID, len(op.params))
			params_t := make([dynamic]TFunc_Param, len(op.params))
			for p, j in op.params {
				if p.type_ann != nil {
					param_types[j] = convert_type_to_var(p.type_ann, store)
				} else {
					param_types[j] = fresh_value_var(store, d.span)
				}
				params_t[j] = TFunc_Param{
					name = p.name,
					type_ = tc_ir_type(store, param_types[j]),
					eff_ = tc_eff_type(store, fresh_effect_row(store, p.span)),
					span = p.span,
				}
			}
			ret_type := fresh_value_var(store, d.span)
			if op.return_type != nil {
				ret_type = convert_type_to_var(op.return_type, store)
			}
			append(&op_sigs, Effect_Op_Sig{
				name = op.name,
				param_count = len(op.params),
				param_types = param_types,
				return_type = ret_type,
			})
			ops_t[i] = TEffect_Op{
				name = op.name,
				is_effectful = op.is_effectful,
				params = params_t,
				return_type = tc_ir_type(store, ret_type),
				return_effects = tc_eff_type(store, fresh_effect_row(store, op.span)),
				span = op.span,
			}
		}
		store.effect_ops[d.name.name] = op_sigs[:]
		level := store.current_level
		exit_level(store)
		generalize_at_level(store, level)

		tp_t := make([dynamic]Type_Param, len(d.type_params))
		for tp, i in d.type_params {
			constraints := make([dynamic]Intern_ID, len(tp.constraints))
			for c, j in tp.constraints {
				constraints[j] = c
			}
			tp_t[i] = Type_Param{name = tp.name, constraints = constraints, is_effect = tp.is_effect}
		}

		td := new(TDecl_Effect)
		td^ = TDecl_Effect{
			name = d.name,
			is_pub = d.is_pub,
			operations = ops_t,
			type_params = tp_t,
			span = d.span,
		}
		return TDecl(td)

	case ^CDecl_Trait:
		typecheck_trait_decl(d, env, store)
		td := new(TDecl_Trait)
		td^ = TDecl_Trait{
			name = d.name,
			is_pub = d.is_pub,
			parent = d.parent,
			methods = make([dynamic]TTrait_Method, len(d.methods)),
			span = d.span,
		}
		for m, i in d.methods {
			td.methods[i] = TTrait_Method{
				name = m.name,
				params = make([dynamic]TFunc_Param, len(m.params)),
				return_type = tc_ir_type(store, fresh_value_var(store, m.span)),
				effects = tc_eff_type(store, fresh_effect_row(store, m.span)),
				span = m.span,
			}
			for p, j in m.params {
				if p.type_ann != nil {
					pv := convert_type_to_var(p.type_ann, store)
					td.methods[i].params[j] = TFunc_Param{
						name = p.name,
						type_ = tc_ir_type(store, pv),
						eff_ = tc_eff_type(store, fresh_effect_row(store, p.span)),
						span = p.span,
					}
				} else {
					td.methods[i].params[j] = TFunc_Param{
						name = p.name,
						type_ = tc_ir_type(store, fresh_value_var(store, p.span)),
						eff_ = tc_eff_type(store, fresh_effect_row(store, p.span)),
						span = p.span,
					}
				}
			}
		}
		return TDecl(td)

	case ^CDecl_Alias:
		convert_type_to_var(d.target, store)
		td := new(TDecl_Alias)
		td^ = TDecl_Alias{
			name = d.name,
			is_pub = d.is_pub,
			target = d.target,
			span = d.span,
		}
		if d.target != nil && ctype_contains_self(d.target^) {
			methods := extract_trait_methods_from_ctype(d.target, store)
			trait_module := d.name.module
			if trait_module == NO_NAME {
				trait_module = env.current_module
			}
			trait_info := Trait_Info{
				name = d.name.name,
				module = trait_module,
				parent = 0,
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
		td^ = TDecl_Newtype{
			name = d.name,
			is_pub = d.is_pub,
			type_params = d.type_params,
			trait_conforms = d.trait_conforms,
			inner_type = d.inner_type,
			type_ = tc_ir_type(store, nt_var),
			derive_targets = d.derive_targets,
			span = d.span,
		}
		return TDecl(td)

	case ^CDecl_Test:
		result := typecheck_synth(d.body, env, store)
		td := new(TDecl_Test)
		td^ = TDecl_Test{
			name = d.name,
			body = result.texpr,
			span = d.span,
		}
		return TDecl(td)

	case ^CDecl_Expect:
		result := typecheck_synth(d.condition, env, store)
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, Source_Span_ZERO)
		unify(store, result.var_id, bool_var)
		td := new(TDecl_Expect)
		td^ = TDecl_Expect{
			condition = result.texpr,
			span = d.span,
		}
		return TDecl(td)

	case ^CDecl_Import:
		td := new(TDecl_Import)
		td^ = TDecl_Import{
			deferred = d.deferred,
			span = d.span,
		}
		return TDecl(td)
	}
	unreachable()
}

typecheck_newtype_decl :: proc(d: ^CDecl_Newtype, env: ^Type_Env, store: ^Type_Store) {
	param_vars := make([dynamic]Type_Var_ID, 0, len(d.type_params))
	enter_level(store)

	for tp in d.type_params {
		tv := fresh_value_var(store, d.span)
		append(&param_vars, tv)
		env.bindings[tp] = tv
	}

	inner_type_var := convert_type_to_var(d.inner_type, store)

	owned_tags := make([dynamic]Intern_ID, 0, 8)
	inner_resolved := get_var(store, resolve_var(store, inner_type_var))
	if inf, is_inf := inner_resolved.link.(Inferred_Type); is_inf && inf.tag == .Tag_Union_Row {
		for te in inf.tag_entries {
			append(&owned_tags, te.name)
		}
	}

	param_ids_slice := make([]Intern_ID, len(d.type_params))
	for i in 0..<len(d.type_params) {
		param_ids_slice[i] = d.type_params[i]
	}

	nt_var := fresh_value_var(store, d.span)
	link_var(store, nt_var, Inferred_Type{
		tag = .Newtype,
		primitive_name = d.name.name,
		arity = len(d.type_params),
		param_ids = param_vars[:],
		inner_id = inner_type_var,
	})

	for i := 0; i < len(d.type_params); i += 1 {
		delete_key(&env.bindings, d.type_params[i])
	}

	level := store.current_level
	exit_level(store)
	generalize_at_level(store, level)

	check_shadow(env, d.name.name, store, d.span)
	env.bindings[d.name.name] = nt_var
	store.bindings[d.name.name] = nt_var

	owned_tags_slice := make([]Intern_ID, len(owned_tags))
	for i in 0..<len(owned_tags) {
		owned_tags_slice[i] = owned_tags[i]
	}

	defining_module := d.name.module
	if defining_module == NO_NAME {
		defining_module = env.current_module
	}

	store.newtype_decls[d.name.name] = Newtype_Decl_Info{
		name = d.name.name,
		module = defining_module,
		pub_variants = d.pub_variants,
		type_params = param_ids_slice[:],
		inner_type = inner_type_var,
		owned_tags = owned_tags_slice[:],
	}

	delete(param_vars)
	delete(owned_tags)
}

typecheck_synth :: proc(expr: CExpr, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	switch e in expr {
	case ^CExpr_Int:
		name := intern(store.interner, "I64")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Int)
		t^ = TExpr_Int{value = e.value, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Float:
		name := intern(store.interner, "F64")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Float)
		t^ = TExpr_Float{value = e.value, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_String:
		name := intern(store.interner, "Str")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_String)
		t^ = TExpr_String{value = e.value, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Bool:
		name := intern(store.interner, "Bool")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Bool)
		t^ = TExpr_Bool{value = e.value, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Name:
		if existing, ok := env_lookup(env, e.name.name); ok {
			inst := instantiate(store, existing)
			eff := fresh_effect_row(store, e.span)
			t := new(TExpr_Name)
			t^ = TExpr_Name{name = e.name, type_ = tc_ir_type(store, inst), eff_ = tc_eff_type(store, eff), span = e.span}
			return Synth_Result{var_id = inst, effects = eff, texpr = TExpr(t)}
		}
		var_id := fresh_value_var(store, e.span)
		name_str := intern_get(store.interner, e.name.name)
		similar := find_similar_names(name_str, env, store.interner)
		defer delete(similar)
		collector_add_diag(store.collector, diag_undefined_name(name_str, similar[:], e.span))
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Name)
		t^ = TExpr_Name{name = e.name, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Lambda:
		return typecheck_lambda(e, env, store)

	case ^CExpr_Call:
		return typecheck_call(e, env, store)

	case ^CExpr_If:
		return typecheck_if(e, env, store)

	case ^CExpr_Block:
		return typecheck_block(e, env, store)

	case ^CExpr_BinOp:
		return typecheck_binop(e, env, store)

	case ^CExpr_PrefixOp:
		return typecheck_prefixop(e, env, store)

	case ^CExpr_Tag:
		return typecheck_tag(e, env, store)

	case ^CExpr_Record:
		return typecheck_record(e, env, store)

	case ^CExpr_Field_Access:
		return typecheck_field_access(e, env, store)

	case ^CExpr_Match:
		return typecheck_match(e, env, store)

	case ^CExpr_List:
		return typecheck_list(e, env, store)

	case ^CExpr_Record_Update:
		return typecheck_record_update(e, env, store)

	case ^CExpr_Assign:
		result := typecheck_synth(e.value, env, store)
		target_t: TExpr
		#partial switch target in e.target {
		case ^CExpr_Name:
			check_shadow(env, target.name.name, store, e.span)
			env.bindings[target.name.name] = result.var_id
			t_name := new(TExpr_Name)
			t_name^ = TExpr_Name{name = target.name, type_ = tc_ir_type(store, result.var_id), eff_ = tc_eff_type(store, result.effects), span = target.span}
			target_t = TExpr(t_name)
		case:
			target_t = typecheck_synth(e.target, env, store).texpr
		}
		t := new(TExpr_Assign)
		t^ = TExpr_Assign{target = target_t, value = result.texpr, type_ = tc_ir_type(store, result.var_id), eff_ = tc_eff_type(store, result.effects), span = e.span}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Return:
		result := typecheck_synth(e.value, env, store)
		t := new(TExpr_Return)
		t^ = TExpr_Return{value = result.texpr, type_ = tc_ir_type(store, result.var_id), eff_ = tc_eff_type(store, result.effects), span = e.span}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Crash:
		var_id := fresh_value_var(store, e.span)
		eff := fresh_effect_row(store, e.span)
		msg_result := typecheck_synth(e.message, env, store)
		t := new(TExpr_Crash)
		t^ = TExpr_Crash{message = msg_result.texpr, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Interpolated_String:
		str_name := intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, e.span)
		eff := fresh_effect_row(store, e.span)
		display_name := intern(store.interner, "Display")
		to_str_name := intern(store.interner, "to_str")
		parts_t := make([dynamic]TExpr_String_Part, 0, len(e.parts))
		for part in e.parts {
			switch p in part {
			case ^CExpr_String_Literal:
				clit := new(TExpr_String_Literal)
				clit^ = TExpr_String_Literal{
					value = p.value,
					type_ = tc_ir_type(store, str_var),
					eff_ = tc_eff_type(store, eff),
					span = p.span,
				}
				append(&parts_t, TExpr_String_Part(clit))
			case CExpr:
				part_result := typecheck_synth(p, env, store)
				unify(store, eff, part_result.effects)

				expr_part := new(TExpr_String_Expr)
				expr_part.expr = part_result.texpr

				resolved := resolve_var(store, part_result.var_id)
				v := get_var(store, resolved)
				type_name: Intern_ID = NO_NAME
				if inf, ok := v.link.(Inferred_Type); ok {
					type_name = inf.primitive_name
				}

				if type_name == str_name {
					expr_part.needs_to_str = false
					expr_part.display_impl = Canonical_Name{}
				} else if type_name != NO_NAME {
					impl, found := find_trait_impl(store, display_name, type_name)
					if found {
						if to_str_impl, has := impl.methods[to_str_name]; has {
							expr_part.needs_to_str = true
							expr_part.display_impl = to_str_impl
						} else {
							type_str := intern_get(store.interner, type_name)
							collector_add_diag(store.collector, diag_display_not_implemented(type_str, e.span))
							expr_part.needs_to_str = false
							expr_part.display_impl = Canonical_Name{}
						}
					} else {
						type_str := intern_get(store.interner, type_name)
						collector_add_diag(store.collector, diag_display_not_implemented(type_str, e.span))
						expr_part.needs_to_str = false
						expr_part.display_impl = Canonical_Name{}
					}
				} else {
					collector_add_diag(store.collector, diag_display_not_implemented("unknown type", e.span))
					expr_part.needs_to_str = false
					expr_part.display_impl = Canonical_Name{}
				}

				append(&parts_t, TExpr_String_Part(expr_part))
			}
		}
		t := new(TExpr_Interpolated_String)
		t^ = TExpr_Interpolated_String{
			parts = parts_t,
			is_raw = e.is_raw,
			is_multiline = e.is_multiline,
			type_ = tc_ir_type(store, str_var),
			eff_ = tc_eff_type(store, eff),
			span = e.span,
		}
		return Synth_Result{var_id = str_var, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Method_Call:
		return typecheck_method_call(e, env, store)

	case ^CExpr_Handle:
		append(&env.handled_effects, e.effect.name)
		saved_handles_len := len(env.spawned_handles)
		body_result := typecheck_synth(e.body, env, store)
		_ = pop(&env.handled_effects)

		arms_t := make([dynamic]THandler_Arm, len(e.arms))

		op_sigs, has_sigs := store.effect_ops[e.effect.name]
		for arm, arm_idx in e.arms {
			arm_env: Type_Env
			arm_env.bindings = make(map[Intern_ID]Type_Var_ID, len(arm.params) + 4)
			arm_env.parent = env
			arm_env.handled_effects = make([dynamic]Intern_ID, 0, 8)
			arm_env.current_module = env.current_module

			arm_body_result: Synth_Result

			if has_sigs {
				sig_idx := -1
				for sig, si in op_sigs {
					if sig.name == arm.op {
						sig_idx = si
						break
					}
				}
				if sig_idx >= 0 {
					sig := op_sigs[sig_idx]
					for i in 0..<len(arm.params) {
						pv := fresh_value_var(store, arm.span)
						check_shadow(&arm_env, arm.params[i], store, arm.span)
						arm_env.bindings[arm.params[i]] = pv
						param_sig_idx := i - 1
						if param_sig_idx >= 0 && param_sig_idx < len(sig.param_types) {
							inst_param := instantiate(store, sig.param_types[param_sig_idx])
							unify(store, pv, inst_param)
						}
					}

					arm_body_result = typecheck_synth(arm.body, &arm_env, store)

					inst_ret := instantiate(store, sig.return_type)
					unify(store, arm_body_result.var_id, inst_ret)
					unify(store, arm_body_result.effects, body_result.effects)

					actual_param_count := len(arm.params) - 1
					expected_param_count := sig.param_count
					if actual_param_count != expected_param_count {
						collector_add_diag(store.collector, diag_internal(fmt.tprintf(
							"handler arm `{}` has {} parameters, expected {}",
							intern_get(store.interner, arm.op),
							actual_param_count,
							expected_param_count,
						), arm.span))
					}
				} else {
					effect_str := intern_get(store.interner, e.effect.name)
					op_str := intern_get(store.interner, arm.op)
					collector_add_diag(store.collector, diag_internal(fmt.tprintf(
						"operation `{}` not found in effect `{}`",
						op_str, effect_str,
					), arm.span))
					for p in arm.params {
						check_shadow(&arm_env, p, store, arm.span)
						arm_env.bindings[p] = fresh_value_var(store, arm.span)
					}
					arm_body_result = typecheck_synth(arm.body, &arm_env, store)
					unify(store, arm_body_result.effects, body_result.effects)
				}
			} else {
				for p in arm.params {
					check_shadow(&arm_env, p, store, arm.span)
					arm_env.bindings[p] = fresh_value_var(store, arm.span)
				}
				arm_body_result = typecheck_synth(arm.body, &arm_env, store)
				unify(store, arm_body_result.effects, body_result.effects)
			}

			arms_t[arm_idx] = THandler_Arm{op = arm.op, params = arm.params, body = arm_body_result.texpr, span = arm.span}

			delete(arm_env.bindings)
			delete(arm_env.handled_effects)
		}

		result_effects := subtract_effect_from_row(store, body_result.effects, e.effect.name, e.span)
		t := new(TExpr_Handle)
		t^ = TExpr_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = body_result.texpr,
			arms = arms_t,
			type_ = tc_ir_type(store, body_result.var_id),
			eff_ = tc_eff_type(store, result_effects),
			span = e.span,
		}
		return Synth_Result{var_id = body_result.var_id, effects = result_effects, texpr = TExpr(t)}

	case ^CExpr_Perform:
		var_id := fresh_value_var(store, e.span)
		effects := fresh_effect_row(store, e.span)
		args_t := make([dynamic]TExpr, len(e.args))
		for arg, i in e.args {
			arg_result := typecheck_synth(arg, env, store)
			_ = arg_result
			args_t[i] = arg_result.texpr
		}
		t := new(TExpr_Perform)
		t^ = TExpr_Perform{effect = e.effect, op = e.op, args = args_t, type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, effects), span = e.span}
		return Synth_Result{var_id = var_id, effects = effects, texpr = TExpr(t)}

	case ^CExpr_Par:
		var_id := fresh_value_var(store, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Int)
		t^ = TExpr_Int{type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_For:
		eff := fresh_effect_row(store, e.span)
		iter_result := typecheck_synth(e.iterable, env, store)
		unify(store, eff, iter_result.effects)

		element_var := fresh_value_var(store, e.span)

		check_shadow(env, e.var, store, e.span)
		env.bindings[e.var] = element_var

		body_result := typecheck_synth(e.body, env, store)
		unify(store, eff, body_result.effects)

		unit_name := intern(store.interner, "Unit")
		unit_var := make_primitive_type(store, unit_name, e.span)

		tfor := new(TExpr_For)
		tfor^ = TExpr_For{
			var      = e.var,
			iterable = iter_result.texpr,
			body     = body_result.texpr,
			type_    = lower_type(store, unit_var),
			eff_     = lower_effect_type(store, eff),
			span     = e.span,
		}
		return Synth_Result{var_id = unit_var, effects = eff, texpr = TExpr(tfor)}
	}
	var_id := fresh_value_var(store, Source_Span_ZERO)
	eff := fresh_effect_row(store, Source_Span_ZERO)
	t := new(TExpr_Int)
	t^ = TExpr_Int{type_ = tc_ir_type(store, var_id), eff_ = tc_eff_type(store, eff), span = Source_Span_ZERO}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

mark_effect_type_params_in_ctype :: proc(type_params: [dynamic]Type_Param, effects_type: ^CType) {
	if effects_type == nil do return
	#partial switch t in effects_type^ {
	case ^CType_Effect_Row:
		if t.rest != 0 {
			for &tp in type_params {
				if tp.name == t.rest {
					tp.is_effect = true
					break
				}
			}
		}
	}
}

typecheck_lambda :: proc(e: ^CExpr_Lambda, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	child_env: Type_Env
	child_env.bindings = make(map[Intern_ID]Type_Var_ID, len(e.params) + len(e.type_params) + 4)
	child_env.parent = env
	child_env.handled_effects = make([dynamic]Intern_ID, 0, 8)
	child_env.current_module = env.current_module
	child_env.spawned_handles = make([dynamic]Source_Span, 0, 8)
	defer delete(child_env.bindings)
	defer delete(child_env.handled_effects)
	defer delete(child_env.spawned_handles)

	param_ids := store_alloc(store, Type_Var_ID, len(e.params))

	mark_effect_type_params_in_ctype(e.type_params, e.effects)

	for tp in e.type_params {
		tv: Type_Var_ID
		if tp.is_effect {
			tv = fresh_effect_row(store, e.span)
		} else {
			tv = fresh_value_var(store, e.span)
		}
		check_shadow(&child_env, tp.name, store, e.span)
		child_env.bindings[tp.name] = tv
		store.type_constraints[tv] = tp.constraints[:]
	}

	params_t := make([dynamic]TFunc_Param, len(e.params))
	for i in 0..<len(e.params) {
		param := e.params[i]
		param_var := fresh_value_var(store, param.span)
		if param.type_ann != nil {
			ann_var := convert_type_to_var(param.type_ann, store)
			unify(store, param_var, ann_var)
		}
		check_shadow(&child_env, param.name, store, param.span)
		child_env.bindings[param.name] = param_var
		param_ids[i] = param_var
		params_t[i] = TFunc_Param{
			name = param.name,
			type_ = tc_ir_type(store, param_var),
			eff_ = tc_eff_type(store, fresh_effect_row(store, param.span)),
			span = param.span,
		}
	}

	body_result := typecheck_synth(e.body, &child_env, store)

	effect_id := fresh_effect_row(store, e.span)
	unify(store, effect_id, body_result.effects)
	if e.effects != nil {
		ann_effects := convert_type_to_var(e.effects, store)
		unify(store, effect_id, ann_effects)
	}

	return_id := fresh_value_var(store, e.span)
	if e.return_type != nil {
		ann_return := convert_type_to_var(e.return_type, store)
		unify(store, return_id, ann_return)
		unify(store, body_result.var_id, ann_return)
	} else {
		unify(store, return_id, body_result.var_id)
	}

	fn_var := fresh_value_var(store, e.span)
	link_var(store, fn_var, Inferred_Type{
		tag = .Function,
		param_ids = param_ids,
		return_id = return_id,
		effect_id = effect_id,
	})

	outer_eff := fresh_effect_row(store, e.span)
	t := new(TExpr_Lambda)
	t^ = TExpr_Lambda{
		type_params = e.type_params,
		params = params_t,
		return_type = tc_ir_type(store, return_id),
		effects = tc_eff_type(store, effect_id),
		body = body_result.texpr,
		type_ = tc_ir_type(store, fn_var),
		eff_ = tc_eff_type(store, outer_eff),
		span = e.span,
	}
	return Synth_Result{var_id = fn_var, effects = outer_eff, texpr = TExpr(t)}
}

typecheck_call :: proc(e: ^CExpr_Call, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	callee_result := typecheck_synth(e.callee, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, callee_result.effects)

	args_t := make([dynamic]TExpr, len(e.args))
	param_ids := store_alloc(store, Type_Var_ID, len(e.args))
	for i in 0..<len(e.args) {
		arg_result := typecheck_synth(e.args[i], env, store)
		unify(store, eff, arg_result.effects)
		param_ids[i] = arg_result.var_id
		args_t[i] = arg_result.texpr
	}

	return_var := fresh_value_var(store, e.span)
	callee_effect := fresh_effect_row(store, e.span)

	expected_fn := Inferred_Type{
		tag = .Function,
		param_ids = param_ids,
		return_id = return_var,
		effect_id = callee_effect,
	}
	expected_fn_var := fresh_value_var(store, e.span)
	link_var(store, expected_fn_var, expected_fn)

	unify(store, callee_result.var_id, expected_fn_var)
	unify(store, eff, callee_effect)

	t := new(TExpr_Call)
	t^ = TExpr_Call{
		callee = callee_result.texpr,
		args = args_t,
		type_ = tc_ir_type(store, return_var),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
}

typecheck_if :: proc(e: ^CExpr_If, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	cond_result := typecheck_synth(e.condition, env, store)
	bool_name := intern(store.interner, "Bool")
	bool_var := make_primitive_type(store, bool_name, e.span)
	unify(store, cond_result.var_id, bool_var)

	then_result := typecheck_synth(e.then_branch, env, store)
	else_result := typecheck_synth(e.else_branch, env, store)

	unify(store, then_result.var_id, else_result.var_id)

	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, cond_result.effects)
	unify(store, effect_row, then_result.effects)
	unify(store, effect_row, else_result.effects)

	t := new(TExpr_If)
	t^ = TExpr_If{
		condition = cond_result.texpr,
		then_branch = then_result.texpr,
		else_branch = else_result.texpr,
		type_ = tc_ir_type(store, then_result.var_id),
		eff_ = tc_eff_type(store, effect_row),
		span = e.span,
	}
	return Synth_Result{var_id = then_result.var_id, effects = effect_row, texpr = TExpr(t)}
}

typecheck_block :: proc(e: ^CExpr_Block, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	if len(e.statements) == 0 {
		unit_name := intern(store.interner, "Unit")
		var_id := make_primitive_type(store, unit_name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Block)
		t^ = TExpr_Block{
			type_ = tc_ir_type(store, var_id),
			eff_ = tc_eff_type(store, eff),
			span = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	last_result: Synth_Result
	effect_row := fresh_effect_row(store, e.span)
	stmts_t := make([dynamic]TExpr, 0, len(e.statements))
	for stmt in e.statements {
		last_result = typecheck_synth(stmt, env, store)
		unify(store, effect_row, last_result.effects)
		append(&stmts_t, last_result.texpr)
	}
	t := new(TExpr_Block)
	t^ = TExpr_Block{
		statements = stmts_t,
		type_ = tc_ir_type(store, last_result.var_id),
		eff_ = tc_eff_type(store, effect_row),
		span = e.span,
	}
	return Synth_Result{var_id = last_result.var_id, effects = effect_row, texpr = TExpr(t)}
}

typecheck_binop :: proc(e: ^CExpr_BinOp, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	left_result := typecheck_synth(e.left, env, store)
	right_result := typecheck_synth(e.right, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, left_result.effects)
	unify(store, eff, right_result.effects)

	result_var: Type_Var_ID
	#partial switch e.op {
	case .Kw_And, .Kw_Or:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, left_result.var_id, bool_var)
		unify(store, right_result.var_id, bool_var)
		result_var = bool_var

	case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		unify(store, left_result.var_id, right_result.var_id)
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		result_var = bool_var

	case .Plus, .Minus, .Star, .Slash, .Percent, .Caret:
		unify(store, left_result.var_id, right_result.var_id)
		result_var = left_result.var_id

	case:
		result_var = left_result.var_id
	}

	t := new(TExpr_BinOp)
	t^ = TExpr_BinOp{
		op = e.op,
		left = left_result.texpr,
		right = right_result.texpr,
		type_ = tc_ir_type(store, result_var),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = result_var, effects = eff, texpr = TExpr(t)}
}

typecheck_prefixop :: proc(e: ^CExpr_PrefixOp, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	operand_result := typecheck_synth(e.operand, env, store)

	result_var: Type_Var_ID
	result_eff: Type_Var_ID
	#partial switch e.op {
	case .Kw_Not:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, e.span)
		unify(store, operand_result.var_id, bool_var)
		result_var = bool_var
		result_eff = operand_result.effects
	case .Minus:
		result_var = operand_result.var_id
		result_eff = operand_result.effects
	case:
		result_var = operand_result.var_id
		result_eff = operand_result.effects
	}

	t := new(TExpr_PrefixOp)
	t^ = TExpr_PrefixOp{
		op = e.op,
		operand = operand_result.texpr,
		type_ = tc_ir_type(store, result_var),
		eff_ = tc_eff_type(store, result_eff),
		span = e.span,
	}
	return Synth_Result{var_id = result_var, effects = result_eff, texpr = TExpr(t)}
}

typecheck_tag :: proc(e: ^CExpr_Tag, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	if is_declared_newtype(store, e.name.name) {
		if len(e.payload) == 1 {
			return typecheck_newtype_construct(e, env, store)
		}
		if len(e.payload) == 0 {
			nt_binding, has_binding := env_lookup(env, e.name.name)
			if !has_binding {
				nt_binding = store.bindings[e.name.name]
			}
			inst := instantiate(store, nt_binding)
			payload_t := make([dynamic]TExpr, 0)
			t := new(TExpr_Tag)
			t^ = TExpr_Tag{
				name = e.name,
				payload = payload_t,
				type_ = tc_ir_type(store, inst),
				eff_ = tc_eff_type(store, eff),
				span = e.span,
			}
			return Synth_Result{var_id = inst, effects = eff, texpr = TExpr(t)}
		}
	}

	nt_name, owned := newtype_owning_tag(store, e.name.name)
	if owned {
		nt_info := store.newtype_decls[nt_name]
		same_mod := is_same_module(env, nt_info.module)
		if !same_mod && !nt_info.pub_variants {
			nt_str := intern_get(store.interner, nt_name)
			tag_str := intern_get(store.interner, e.name.name)
			collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, fmt.tprintf("construct variant {}", tag_str), e.span))
		} else if !same_mod && e.name.module == NO_NAME {
			nt_str := intern_get(store.interner, nt_name)
			tag_str := intern_get(store.interner, e.name.name)
			collector_add_diag(store.collector, diag_unqualified_tag(nt_str, tag_str, e.span))
		} else if same_mod && e.name.module == NO_NAME && !nt_info.pub_variants {
			nt_str := intern_get(store.interner, nt_name)
			tag_str := intern_get(store.interner, e.name.name)
			collector_add_diag(store.collector, diag_unqualified_tag(nt_str, tag_str, e.span))
		}
	}

	payload_ids := store_alloc(store, Type_Var_ID, len(e.payload))
	payload_t := make([dynamic]TExpr, len(e.payload))
	for p, i in e.payload {
		p_result := typecheck_synth(p, env, store)
		unify(store, eff, p_result.effects)
		payload_ids[i] = resolve_var(store, p_result.var_id)
		payload_t[i] = p_result.texpr
	}

	tag_var := fresh_value_var(store, e.span)
	rest_var := fresh_tag_row(store, e.span)
	tag_entries := store_alloc(store, Type_Tag_Entry, 1)
	tag_entries[0] = Type_Tag_Entry{name = e.name.name, payload = payload_ids}
	inf := Inferred_Type{
		tag = .Tag_Union_Row,
		tag_entries = tag_entries,
		tag_rest = resolve_var(store, rest_var),
	}
	link_var(store, tag_var, inf)

	t := new(TExpr_Tag)
	t^ = TExpr_Tag{
		name = e.name,
		payload = payload_t,
		type_ = tc_ir_type(store, tag_var),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = tag_var, effects = eff, texpr = TExpr(t)}
}

typecheck_record :: proc(e: ^CExpr_Record, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	record_fields := store_alloc(store, Type_Field_Entry, len(e.fields))
	fields_t := make([dynamic]TRecord_Field, len(e.fields))
	for i in 0..<len(e.fields) {
		field := e.fields[i]
		field_result := typecheck_synth(field.value, env, store)
		unify(store, eff, field_result.effects)
		record_fields[i] = Type_Field_Entry{name = field.name, var = field_result.var_id}
		fields_t[i] = TRecord_Field{name = field.name, value = field_result.texpr, span = field.span}
	}

	record_rest := fresh_record_row(store, e.span)
	rest_t: TExpr
	_, has_rest := e.rest.(^CExpr_Record)
	if has_rest {
		rest_result := typecheck_synth(e.rest, env, store)
		unify(store, eff, rest_result.effects)
		unify(store, record_rest, rest_result.var_id)
		rest_t = rest_result.texpr
	}

	var_id := fresh_value_var(store, e.span)
	link_var(store, var_id, Inferred_Type{
		tag = .Record_Row,
		record_fields = record_fields,
		record_rest = record_rest,
	})

	t := new(TExpr_Record)
	t^ = TExpr_Record{
		fields = fields_t,
		rest = rest_t,
		is_open = e.is_open,
		type_ = tc_ir_type(store, var_id),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_field_access :: proc(e: ^CExpr_Field_Access, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	record_result := typecheck_synth(e.record, env, store)
	field_var := fresh_value_var(store, e.span)
	rest_var := fresh_value_var(store, e.span)
	record_fields := store_alloc(store, Type_Field_Entry, 1)
	record_fields[0] = Type_Field_Entry{name = e.field, var = resolve_var(store, field_var)}
	inf := Inferred_Type{
		tag = .Record_Row,
		record_fields = record_fields,
		record_rest = resolve_var(store, rest_var),
	}
	link_var(store, record_result.var_id, inf)

	t := new(TExpr_Field_Access)
	t^ = TExpr_Field_Access{
		record = record_result.texpr,
		field = e.field,
		type_ = tc_ir_type(store, field_var),
		eff_ = tc_eff_type(store, record_result.effects),
		span = e.span,
	}
	return Synth_Result{var_id = field_var, effects = record_result.effects, texpr = TExpr(t)}
}

typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Pat_Result {
	eff := fresh_effect_row(store, Source_Span_ZERO)

	#partial switch p in pattern {
	case ^CPattern_Identifier:
		check_shadow(env, p.name, store, p.span)
		env.bindings[p.name] = scrutinee_var
		tp := new(TPattern_Identifier)
		tp^ = TPattern_Identifier{name = p.name, span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Wildcard:
		tp := new(TPattern_Wildcard)
		tp^ = TPattern_Wildcard{span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Bool:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, p.span)
		unify(store, scrutinee_var, bool_var)
		tp := new(TPattern_Bool)
		tp^ = TPattern_Bool{value = p.value, span = p.span}
		return Pat_Result{var_id = bool_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Int:
		i64_name := intern(store.interner, "I64")
		i64_var := make_primitive_type(store, i64_name, p.span)
		unify(store, scrutinee_var, i64_var)
		tp := new(TPattern_Int)
		tp^ = TPattern_Int{value = p.value, span = p.span}
		return Pat_Result{var_id = i64_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_String:
		str_name := intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, p.span)
		unify(store, scrutinee_var, str_var)
		tp := new(TPattern_String)
		tp^ = TPattern_String{value = p.value, span = p.span}
		return Pat_Result{var_id = str_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Tag:
		nt_name, owned := newtype_owning_tag(store, p.name.name)
		if owned && !is_same_module(env, store.newtype_decls[nt_name].module) {
			nt_info := store.newtype_decls[nt_name]
			if !nt_info.pub_variants {
				nt_str := intern_get(store.interner, nt_name)
				collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, "destructure variant", p.span))
			}
		}

		payload_ids := store_alloc(store, Type_Var_ID, len(p.payload))
		payload_t := make([dynamic]TPattern, len(p.payload))
		for sp, i in p.payload {
			payload_ids[i] = fresh_value_var(store, p.span)
			pat_result := typecheck_pattern(sp, payload_ids[i], env, store)
			unify(store, eff, pat_result.effects)
			payload_t[i] = pat_result.tpat
		}
		rest_var := fresh_tag_row(store, p.span)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		tag_entries[0] = Type_Tag_Entry{name = p.name.name, payload = payload_ids}
		tag_var := fresh_value_var(store, p.span)
		link_var(store, tag_var, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, tag_var)
		tp := new(TPattern_Tag)
		tp^ = TPattern_Tag{name = p.name, payload = payload_t, span = p.span}
		return Pat_Result{var_id = tag_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Record:
		field_entries := store_alloc(store, Type_Field_Entry, len(p.fields))
		fields_t := make([dynamic]TPattern_Field, len(p.fields))
		for sf, i in p.fields {
			field_entries[i].name = sf.name
			field_entries[i].var = fresh_value_var(store, p.span)
			env.bindings[sf.binding] = field_entries[i].var
			fields_t[i] = TPattern_Field{name = sf.name, binding = sf.binding, span = sf.span}
		}
		rest_var := fresh_record_row(store, p.span)
		rec_var := fresh_value_var(store, p.span)
		link_var(store, rec_var, Inferred_Type{
			tag = .Record_Row,
			record_fields = field_entries,
			record_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, rec_var)
		tp := new(TPattern_Record)
		tp^ = TPattern_Record{fields = fields_t, is_open = p.is_open, span = p.span}
		return Pat_Result{var_id = rec_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Or:
		alternatives := make([dynamic]TPattern, 0, len(p.alternatives))
		for alt in p.alternatives {
			pat_result := typecheck_pattern(alt, scrutinee_var, env, store)
			append(&alternatives, pat_result.tpat)
		}
		tp := new(TPattern_Or)
		tp^ = TPattern_Or{alternatives = alternatives, span = p.span}
		return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}

	case ^CPattern_Destructure:
		if is_declared_newtype(store, p.type_name.name) {
			nt_info, nt_ok := store.newtype_decls[p.type_name.name]
			if nt_ok && !is_same_module(env, nt_info.module) {
				nt_str := intern_get(store.interner, p.type_name.name)
				collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, "destructure", p.span))
			}
		}
		inner_var := fresh_value_var(store, p.span)
		pat_result := typecheck_pattern(p.inner, inner_var, env, store)
		unify(store, eff, pat_result.effects)

		nt_binding, has_binding := env_lookup(env, p.type_name.name)
		if !has_binding {
			nt_binding = store.bindings[p.type_name.name]
		}
		inst_binding := instantiate(store, nt_binding)
		unify(store, scrutinee_var, inst_binding)
		unify(store, inner_var, store.newtype_decls[p.type_name.name].inner_type)

		tp := new(TPattern_Destructure)
		tp^ = TPattern_Destructure{type_name = p.type_name, inner = pat_result.tpat, span = p.span}
		return Pat_Result{var_id = inst_binding, effects = eff, tpat = TPattern(tp)}
	}

	tp := new(TPattern_Wildcard)
	tp^ = TPattern_Wildcard{span = Source_Span_ZERO}
	return Pat_Result{var_id = scrutinee_var, effects = eff, tpat = TPattern(tp)}
}

Match_Coverage :: struct {
	tags:          map[Intern_ID]bool,
	bool_values:   map[bool]bool,
	int_values:    map[i64]bool,
	string_values: map[string]bool,
	saturated:     bool,
}

match_coverage_init :: proc(cov: ^Match_Coverage, capacity: int) {
	cov.tags = make(map[Intern_ID]bool, capacity)
	cov.bool_values = make(map[bool]bool, 2)
	cov.int_values = make(map[i64]bool, capacity)
	cov.string_values = make(map[string]bool, capacity)
	cov.saturated = false
}

match_coverage_destroy :: proc(cov: ^Match_Coverage) {
	delete(cov.tags)
	delete(cov.bool_values)
	delete(cov.int_values)
	delete(cov.string_values)
}

collect_pattern_coverage :: proc(pattern: CPattern, cov: ^Match_Coverage) {
	#partial switch p in pattern {
	case ^CPattern_Wildcard, ^CPattern_Identifier:
		cov.saturated = true
	case ^CPattern_Tag:
		cov.tags[p.name.name] = true
	case ^CPattern_Bool:
		cov.bool_values[p.value] = true
	case ^CPattern_Int:
		cov.int_values[p.value] = true
	case ^CPattern_String:
		cov.string_values[p.value] = true
	case ^CPattern_Or:
		for alt in p.alternatives {
			collect_pattern_coverage(alt, cov)
		}
	case:
	}
}

typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, e.span)
		eff := scrutinee_result.effects
		arms_t := make([dynamic]TMatch_Arm, 0)
		t := new(TExpr_Match)
		t^ = TExpr_Match{
			scrutinee = scrutinee_result.texpr,
			arms = arms_t,
			type_ = tc_ir_type(store, var_id),
			eff_ = tc_eff_type(store, eff),
			span = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	saved_bindings := make(map[Intern_ID]Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	result_var := fresh_value_var(store, e.span)
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)

	cov: Match_Coverage
	match_coverage_init(&cov, len(e.arms))
	defer match_coverage_destroy(&cov)

	// Track per-arm coverage for redundancy detection
	arm_coverages := make([dynamic]Match_Coverage, len(e.arms))
	for i in 0..<len(e.arms) {
		match_coverage_init(&arm_coverages[i], 1)
	}
	defer for i in 0..<len(arm_coverages) {
		match_coverage_destroy(&arm_coverages[i])
	}
	defer delete(arm_coverages)

	arms_t := make([dynamic]TMatch_Arm, len(e.arms))

	for i := 0; i < len(e.arms); i += 1 {
		arm := e.arms[i]

		for k in env.bindings {
			delete_key(&env.bindings, k)
		}
		for k, v in saved_bindings {
			env.bindings[k] = v
		}

		pat_result := typecheck_pattern(arm.pattern, scrutinee_result.var_id, env, store)
		unify(store, effect_row, pat_result.effects)

		// Check redundancy: is this pattern already covered by earlier arms?
		is_redundant := false
		if cov.saturated {
			is_redundant = true
		} else {
			#partial switch p in arm.pattern {
			case ^CPattern_Bool:
				if cov.bool_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_Int:
				if cov.int_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_String:
				if cov.string_values[p.value] {
					is_redundant = true
				}
			case ^CPattern_Tag:
				if cov.tags[p.name.name] {
					is_redundant = true
				}
			case:
			}
		}
		if is_redundant {
			collector_add_diag(store.collector, diag_redundant_pattern(arm.span))
		}

		collect_pattern_coverage(arm.pattern, &cov)
		collect_pattern_coverage(arm.pattern, &arm_coverages[i])

		arm_result := typecheck_synth(arm.body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)

		arms_t[i] = TMatch_Arm{pattern = pat_result.tpat, body = arm_result.texpr, span = arm.span}
	}

	// Exhaustiveness checking
	resolved_scrut := get_var(store, resolve_var(store, scrutinee_result.var_id))
	#partial switch inf in resolved_scrut.link {
	case Inferred_Type:
		if inf.tag == .Tag_Union_Row && len(inf.tag_entries) > 0 && !cov.saturated {
			missing_list: [dynamic]string
			missing_list = make([dynamic]string, 0, len(inf.tag_entries))
			defer delete(missing_list)
			for te in inf.tag_entries {
				if !cov.tags[te.name] {
					append(&missing_list, intern_get(store.interner, te.name))
				}
			}
			if len(missing_list) > 0 {
				missing := missing_list[0]
				for j := 1; j < len(missing_list); j += 1 {
					missing = fmt.tprintf("{}, {}", missing, missing_list[j])
				}
				collector_add_diag(store.collector, diag_internal(
					fmt.tprintf("non-exhaustive match: missing branch for {}", missing),
					e.span))
			}
		}
		// Bool exhaustiveness: must cover both true and false
		if inf.tag == .Primitive && inf.primitive_name == intern(store.interner, "Bool") && !cov.saturated {
			if !cov.bool_values[true] || !cov.bool_values[false] {
				missing: string
				if !cov.bool_values[true] && !cov.bool_values[false] {
					missing = "true and false"
				} else if !cov.bool_values[true] {
					missing = "true"
				} else {
					missing = "false"
				}
				collector_add_diag(store.collector, diag_non_exhaustive_bool(missing, e.span))
			}
		}
		// Int/String exhaustiveness: can never be exhaustive without wildcard
		if inf.tag == .Primitive && !cov.saturated {
			prim_name := intern_get(store.interner, inf.primitive_name)
			if prim_name == "I64" || prim_name == "I32" || prim_name == "I16" || prim_name == "I8" ||
			   prim_name == "U64" || prim_name == "U32" || prim_name == "U16" || prim_name == "U8" {
				collector_add_diag(store.collector, diag_non_exhaustive_int_string(prim_name, e.span))
			}
			if prim_name == "Str" {
				collector_add_diag(store.collector, diag_non_exhaustive_int_string(prim_name, e.span))
			}
		}
	case:
	}

	t := new(TExpr_Match)
	t^ = TExpr_Match{
		scrutinee = scrutinee_result.texpr,
		arms = arms_t,
		type_ = tc_ir_type(store, result_var),
		eff_ = tc_eff_type(store, effect_row),
		span = e.span,
	}
	return Synth_Result{var_id = result_var, effects = effect_row, texpr = TExpr(t)}
}

typecheck_list :: proc(e: ^CExpr_List, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	element_var := fresh_value_var(store, e.span)
	eff := fresh_effect_row(store, e.span)

	elements_t := make([dynamic]TExpr, len(e.elements))
	for el, i in e.elements {
		el_result := typecheck_synth(el, env, store)
		unify(store, element_var, el_result.var_id)
		unify(store, eff, el_result.effects)
		elements_t[i] = el_result.texpr
	}

	var_id := fresh_value_var(store, e.span)
	t := new(TExpr_List)
	t^ = TExpr_List{
		elements = elements_t,
		type_ = tc_ir_type(store, var_id),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_record_update :: proc(e: ^CExpr_Record_Update, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	rest_result := typecheck_synth(e.rest, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, rest_result.effects)

	updates_t := make([dynamic]TRecord_Field, len(e.updates))
	for u, i in e.updates {
		u_result := typecheck_synth(u.value, env, store)
		unify(store, eff, u_result.effects)
		updates_t[i] = TRecord_Field{name = u.name, value = u_result.texpr, span = u.span}
	}

	t := new(TExpr_Record_Update)
	t^ = TExpr_Record_Update{
		rest = rest_result.texpr,
		updates = updates_t,
		type_ = tc_ir_type(store, rest_result.var_id),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = rest_result.var_id, effects = eff, texpr = TExpr(t)}
}

typecheck_method_call :: proc(e: ^CExpr_Method_Call, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	inner_name := intern(store.interner, "inner")
	if e.method.name == inner_name && len(e.args) == 0 {
		receiver_result := typecheck_synth(e.receiver, env, store)
		receiver_resolved := get_var(store, resolve_var(store, receiver_result.var_id))
		if inf, is_inf := receiver_resolved.link.(Inferred_Type); is_inf && inf.tag == .Newtype {
			nt_info, nt_ok := store.newtype_decls[inf.primitive_name]
			if nt_ok && !is_same_module(env, nt_info.module) {
				nt_str := intern_get(store.interner, inf.primitive_name)
				collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, "unwrap", e.span))
			}
			args_t := make([dynamic]TExpr, 0)
			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call{
				receiver = receiver_result.texpr,
				method = e.method,
				args = args_t,
				type_ = tc_ir_type(store, inf.inner_id),
				eff_ = tc_eff_type(store, receiver_result.effects),
				resolved_ = e.method,
				span = e.span,
			}
			return Synth_Result{var_id = inf.inner_id, effects = receiver_result.effects, texpr = TExpr(t)}
		}
	}

	receiver_result := typecheck_synth(e.receiver, env, store)
	eff := fresh_effect_row(store, e.span)
	unify(store, eff, receiver_result.effects)

	is_effect_op := false
	effect_name: Intern_ID = NO_NAME

	#partial switch r in e.receiver {
	case ^CExpr_Tag:
		if is_declared_newtype(store, r.name.name) && len(r.payload) == 0 && len(e.args) >= 1 {
			return typecheck_qualified_tag_construct(r, e, env, store)
		}
		if len(r.payload) == 0 && is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	case ^CExpr_Name:
		if is_declared_effect(store, r.name.name) {
			is_effect_op = true
			effect_name = r.name.name
		}
	}

	args_t := make([dynamic]TExpr, 0, len(e.args))

	if is_effect_op {
		is_prelude := is_prelude_effect(effect_name, store.interner)
		if !is_prelude && !is_effect_handled(env, effect_name) {
			effect_str := intern_get(store.interner, effect_name)
			collector_add_diag(store.collector, diag_unhandled_effect(effect_str, e.span))
		}

		effect_entries := store_alloc(store, Effect_Row_Entry, 1)
		effect_entries[0] = Effect_Row_Entry{name = effect_name, type_args = {}}
		rest := fresh_effect_row(store, e.span)
		row := fresh_effect_row(store, e.span)
		link_var(store, row, Inferred_Type{
			tag = .Effect_Row,
			effects = effect_entries,
			rest_id = rest,
		})
		unify(store, eff, row)

		spawn_name := intern(store.interner, "spawn!")
		join_name := intern(store.interner, "join!")
		is_scheduler := effect_name == intern(store.interner, "Spawn!") ||
			effect_name == intern(store.interner, "Async!")

		if is_scheduler && e.method.name == spawn_name && len(e.args) == 1 {
			arg_result := typecheck_synth(e.args[0], env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)

			arg_resolved := get_var(store, resolve_var(store, arg_result.var_id))
			if inf, is_inf := arg_resolved.link.(Inferred_Type); is_inf && inf.tag == .Function {
				handle_var := fresh_value_var(store, e.span)
				link_var(store, handle_var, Inferred_Type{
					tag = .Handle,
					inner_id = inf.return_id,
					effect_id = inf.effect_id,
				})
				append(&env.spawned_handles, e.span)
				t := new(TExpr_Method_Call)
				t^ = TExpr_Method_Call{
					receiver = receiver_result.texpr,
					method = e.method,
					args = args_t,
					type_ = tc_ir_type(store, handle_var),
					eff_ = tc_eff_type(store, eff),
					resolved_ = e.method,
					span = e.span,
				}
				return Synth_Result{var_id = handle_var, effects = eff, texpr = TExpr(t)}
			}
			inner_var := fresh_value_var(store, e.span)
			effect_var := fresh_effect_row(store, e.span)
			handle_var := fresh_value_var(store, e.span)
			link_var(store, handle_var, Inferred_Type{
				tag = .Handle,
				inner_id = inner_var,
				effect_id = effect_var,
			})
			append(&env.spawned_handles, e.span)
			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call{
				receiver = receiver_result.texpr,
				method = e.method,
				args = args_t,
				type_ = tc_ir_type(store, handle_var),
				eff_ = tc_eff_type(store, eff),
				resolved_ = e.method,
				span = e.span,
			}
			return Synth_Result{var_id = handle_var, effects = eff, texpr = TExpr(t)}
		}

		if is_scheduler && e.method.name == join_name && len(e.args) == 1 {
			arg_result := typecheck_synth(e.args[0], env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)

			arg_resolved := get_var(store, resolve_var(store, arg_result.var_id))
			if inf, is_inf := arg_resolved.link.(Inferred_Type); is_inf && inf.tag == .Handle {
				unify(store, eff, inf.effect_id)
				t := new(TExpr_Method_Call)
				t^ = TExpr_Method_Call{
					receiver = receiver_result.texpr,
					method = e.method,
					args = args_t,
					type_ = tc_ir_type(store, inf.inner_id),
					eff_ = tc_eff_type(store, eff),
					resolved_ = e.method,
					span = e.span,
				}
				return Synth_Result{var_id = inf.inner_id, effects = eff, texpr = TExpr(t)}
			}
			return_var := fresh_value_var(store, e.span)
			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call{
				receiver = receiver_result.texpr,
				method = e.method,
				args = args_t,
				type_ = tc_ir_type(store, return_var),
				eff_ = tc_eff_type(store, eff),
				resolved_ = e.method,
				span = e.span,
			}
			return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
		}

		is_parallel := effect_name == intern(store.interner, "Parallel!")
		if is_parallel {
			spawn_effect_name := intern(store.interner, "Spawn!")
			spawn_effect_entries := store_alloc(store, Effect_Row_Entry, 1)
			spawn_effect_entries[0] = Effect_Row_Entry{name = spawn_effect_name, type_args = {}}
			spawn_rest := fresh_effect_row(store, e.span)
			spawn_row := fresh_effect_row(store, e.span)
			link_var(store, spawn_row, Inferred_Type{
				tag = .Effect_Row,
				effects = spawn_effect_entries,
				rest_id = spawn_rest,
			})
			unify(store, eff, spawn_row)

			for a in e.args {
				arg_result := typecheck_synth(a, env, store)
				unify(store, eff, arg_result.effects)
				append(&args_t, arg_result.texpr)
			}

			map_name := intern(store.interner, "map!")
			all_name := intern(store.interner, "all!")
			filter_name := intern(store.interner, "filter!")
			for_each_name := intern(store.interner, "for_each!")
			reduce_name := intern(store.interner, "reduce!")
			any_name := intern(store.interner, "any!")

			result_var: Type_Var_ID

			if e.method.name == for_each_name {
				unit_name := intern(store.interner, "Unit")
				result_var = make_primitive_type(store, unit_name, e.span)
			} else if e.method.name == any_name && len(e.args) >= 2 {
				result_var = fresh_value_var(store, e.span)
			} else if e.method.name == reduce_name && len(e.args) >= 3 {
				init_result := typecheck_synth(e.args[2], env, store)
				result_var = init_result.var_id
			} else {
				result_var = fresh_value_var(store, e.span)
			}

			t := new(TExpr_Method_Call)
			t^ = TExpr_Method_Call{
				receiver = receiver_result.texpr,
				method = e.method,
				args = args_t,
				type_ = tc_ir_type(store, result_var),
				eff_ = tc_eff_type(store, eff),
				resolved_ = e.method,
				span = e.span,
			}
			return Synth_Result{var_id = result_var, effects = eff, texpr = TExpr(t)}
		}
	}

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
		append(&args_t, arg_result.texpr)

		if is_effect_op {
			arg_resolved := resolve_var(store, arg_result.var_id)
			arg_var := get_var(store, arg_resolved)
			if inf, is_inf := arg_var.link.(Inferred_Type); is_inf && inf.tag == .Function {
				unify(store, eff, inf.effect_id)
			}
		}
	}

	return_var := fresh_value_var(store, e.span)
	t := new(TExpr_Method_Call)
	t^ = TExpr_Method_Call{
		receiver = receiver_result.texpr,
		method = e.method,
		args = args_t,
		type_ = tc_ir_type(store, return_var),
		eff_ = tc_eff_type(store, eff),
		resolved_ = e.method,
		span = e.span,
	}
	return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
}

typecheck_qualified_tag_construct :: proc(receiver: ^CExpr_Tag, e: ^CExpr_Method_Call, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)
	args_t := make([dynamic]TExpr, 0, len(e.args))

	nt_info, ok := store.newtype_decls[receiver.name.name]
	if !ok {
		return_var := fresh_value_var(store, e.span)
		for a in e.args {
			arg_result := typecheck_synth(a, env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)
		}
		t := new(TExpr_Method_Call)
		t^ = TExpr_Method_Call{
			receiver = TExpr(new(TExpr_Tag)),
			method = e.method,
			args = args_t,
			type_ = tc_ir_type(store, return_var),
			eff_ = tc_eff_type(store, eff),
			resolved_ = e.method,
			span = e.span,
		}
		return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
	}

	if !is_same_module(env, nt_info.module) && !nt_info.pub_variants {
		nt_str := intern_get(store.interner, receiver.name.name)
		collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, "construct variant", e.span))
	}

	tag_owned := false
	for owned in nt_info.owned_tags {
		if owned == e.method.name {
			tag_owned = true
			break
		}
	}
	if !tag_owned {
		nt_str := intern_get(store.interner, receiver.name.name)
		tag_str := intern_get(store.interner, e.method.name)
		collector_add_diag(store.collector, diag_tag_not_owned(nt_str, tag_str, e.span))
		return_var := fresh_value_var(store, e.span)
		for a in e.args {
			arg_result := typecheck_synth(a, env, store)
			unify(store, eff, arg_result.effects)
			append(&args_t, arg_result.texpr)
		}
		t := new(TExpr_Method_Call)
		t^ = TExpr_Method_Call{
			receiver = TExpr(new(TExpr_Tag)),
			method = e.method,
			args = args_t,
			type_ = tc_ir_type(store, return_var),
			eff_ = tc_eff_type(store, eff),
			resolved_ = e.method,
			span = e.span,
		}
		return Synth_Result{var_id = return_var, effects = eff, texpr = TExpr(t)}
	}

	nt_binding, has_binding := env_lookup(env, receiver.name.name)
	if !has_binding {
		nt_binding = store.bindings[receiver.name.name]
	}
	inst_binding := instantiate(store, nt_binding)

	nt_resolved := get_var(store, resolve_var(store, inst_binding))
	nt_inf, is_nt := nt_resolved.link.(Inferred_Type)

	if is_nt && nt_inf.tag == .Newtype {
		inner_resolved := get_var(store, resolve_var(store, nt_inf.inner_id))
		if inner_inf, inner_ok := inner_resolved.link.(Inferred_Type); inner_ok && inner_inf.tag == .Tag_Union_Row {
			for te in inner_inf.tag_entries {
				if te.name == e.method.name && len(te.payload) == len(e.args) {
					for a, i in e.args {
						arg_result := typecheck_synth(a, env, store)
						unify(store, eff, arg_result.effects)
						unify(store, arg_result.var_id, te.payload[i])
						append(&args_t, arg_result.texpr)
					}
					t := new(TExpr_Method_Call)
					t^ = TExpr_Method_Call{
						receiver = TExpr(new(TExpr_Tag)),
						method = e.method,
						args = args_t,
						type_ = tc_ir_type(store, inst_binding),
						eff_ = tc_eff_type(store, eff),
						resolved_ = e.method,
						span = e.span,
					}
					return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
				}
			}
		}
	}

	for a in e.args {
		arg_result := typecheck_synth(a, env, store)
		unify(store, eff, arg_result.effects)
		append(&args_t, arg_result.texpr)
	}

	t := new(TExpr_Method_Call)
	t^ = TExpr_Method_Call{
		receiver = TExpr(new(TExpr_Tag)),
		method = e.method,
		args = args_t,
		type_ = tc_ir_type(store, inst_binding),
		eff_ = tc_eff_type(store, eff),
		resolved_ = e.method,
		span = e.span,
	}
	return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
}

convert_type_to_var :: proc(t: ^CType, store: ^Type_Store) -> Type_Var_ID {
	return convert_type_to_var_val(t^, store)
}

convert_type_to_var_val :: proc(t: CType, store: ^Type_Store) -> Type_Var_ID {
	switch ty in t {
	case ^CType_Primitive:
		return make_primitive_type(store, ty.name, ty.span)

	case ^CType_Variable:
		return fresh_value_var(store, ty.span)

	case ^CType_Wildcard:
		return fresh_value_var(store, ty.span)

	case ^CType_Self:
		return fresh_value_var(store, ty.span)

	case ^CType_Function:
		ft := ty
		param_ids := store_alloc(store, Type_Var_ID, len(ft.params))
		for i in 0..<len(ft.params) {
			param_ids[i] = convert_type_to_var_val(ft.params[i], store)
		}
		return_id := convert_type_to_var_val(ft.return_, store)
		effect_id := fresh_effect_row(store, ft.span)
		if ft.effects != nil {
			effect_id = convert_type_to_var(ft.effects, store)
		}
		vid := fresh_value_var(store, ft.span)
		link_var(store, vid, Inferred_Type{
			tag = .Function,
			param_ids = param_ids,
			return_id = return_id,
			effect_id = effect_id,
		})
		return vid

	case ^CType_Applied:
		arg_ids := store_alloc(store, Type_Var_ID, len(ty.args))
		for &a, i in ty.args {
			arg_ids[i] = convert_type_to_var_val(a, store)
		}
		vid := fresh_value_var(store, ty.span)
		handle_name := intern(store.interner, "Handle")
		if ty.name == handle_name && len(ty.args) == 2 {
			link_var(store, vid, Inferred_Type{
				tag = .Handle,
				inner_id = arg_ids[0],
				effect_id = arg_ids[1],
			})
		} else {
			link_var(store, vid, Inferred_Type{
				tag = .Constructor,
				primitive_name = ty.name,
				arity = len(ty.args),
			})
		}
		return vid

	case ^CType_Record:
		rt := ty
		record_fields := store_alloc(store, Type_Field_Entry, len(rt.fields))
		for i in 0..<len(rt.fields) {
			record_fields[i] = Type_Field_Entry{
				name = rt.fields[i].name,
				var  = convert_type_to_var_val(rt.fields[i].type, store),
			}
		}
		record_rest := fresh_record_row(store, rt.span)
		vid := fresh_value_var(store, rt.span)
		link_var(store, vid, Inferred_Type{
			tag = .Record_Row,
			record_fields = record_fields,
			record_rest = record_rest,
		})
		return vid

	case ^CType_Tag_Union:
		tt := ty
		tag_entries := store_alloc(store, Type_Tag_Entry, len(tt.tags))
		for i in 0..<len(tt.tags) {
			tg := tt.tags[i]
			payload := store_alloc(store, Type_Var_ID, len(tg.payload))
			for j in 0..<len(tg.payload) {
				payload[j] = convert_type_to_var_val(tg.payload[j], store)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = tg.name,
				payload = payload,
			}
		}
		tag_rest := fresh_tag_row(store, tt.span)
		vid := fresh_value_var(store, tt.span)
		link_var(store, vid, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = tag_rest,
		})
		return vid

	case ^CType_Effect_Row:
		ert := ty
		if len(ert.effects) == 0 {
			return fresh_effect_row(store, ert.span)
		}
		effect_entries := store_alloc(store, Effect_Row_Entry, len(ert.effects))
		for i in 0..<len(ert.effects) {
			ce := ert.effects[i]
			type_args := store_alloc(store, Type_Var_ID, len(ce.type_args))
			for j in 0..<len(ce.type_args) {
				type_args[j] = convert_type_to_var(&ce.type_args[j], store)
			}
			effect_entries[i] = Effect_Row_Entry{name = ce.name, type_args = type_args}
		}
		rest_id := fresh_effect_row(store, ert.span)
		vid := fresh_effect_row(store, ert.span)
		link_var(store, vid, Inferred_Type{
			tag = .Effect_Row,
			effects = effect_entries,
			rest_id = rest_id,
		})
		return vid
	}
	return fresh_value_var(store, Source_Span_ZERO)
}

instantiate :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> Type_Var_ID {
	subst := make(map[Type_Var_ID]Type_Var_ID, 8)
	defer delete(subst)
	return instantiate_rec(store, var_id, &subst)
}

instantiate_rec :: proc(store: ^Type_Store, var_id: Type_Var_ID, subst: ^map[Type_Var_ID]Type_Var_ID) -> Type_Var_ID {
	resolved := resolve_var(store, var_id)
	v := get_var(store, resolved)

	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked && is_generic(store, resolved) {
		if existing, ok := subst[resolved]; ok {
			return existing
		}
		new_id := fresh_var(store, v.kind, v.name, v.span)
		subst[resolved] = new_id
		return new_id
	}

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return resolved
	}

	switch inf.tag {
	case .Primitive, .Constructor:
		return resolved

	case .Newtype:
		param_ids := store_alloc(store, Type_Var_ID, len(inf.param_ids))
		for i in 0..<len(inf.param_ids) {
			param_ids[i] = instantiate_rec(store, inf.param_ids[i], subst)
		}
		inner_id := instantiate_rec(store, inf.inner_id, subst)
		vid := fresh_value_var(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Newtype,
			primitive_name = inf.primitive_name,
			arity = inf.arity,
			param_ids = param_ids,
			inner_id = inner_id,
		})
		return vid

	case .Function:
		param_ids := store_alloc(store, Type_Var_ID, len(inf.param_ids))
		for i in 0..<len(inf.param_ids) {
			param_ids[i] = instantiate_rec(store, inf.param_ids[i], subst)
		}
		return_id := instantiate_rec(store, inf.return_id, subst)
		effect_id := instantiate_rec(store, inf.effect_id, subst)
		vid := fresh_value_var(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Function,
			param_ids = param_ids,
			return_id = return_id,
			effect_id = effect_id,
		})
		return vid

	case .Effect_Row:
		effect_entries := store_alloc(store, Effect_Row_Entry, len(inf.effects))
		for i in 0..<len(inf.effects) {
			entry := inf.effects[i]
			type_args := store_alloc(store, Type_Var_ID, len(entry.type_args))
			for j in 0..<len(entry.type_args) {
				type_args[j] = instantiate_rec(store, entry.type_args[j], subst)
			}
			effect_entries[i] = Effect_Row_Entry{name = entry.name, type_args = type_args}
		}
		rest_id := instantiate_rec(store, inf.rest_id, subst)
		vid := fresh_effect_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Effect_Row,
			effects = effect_entries,
			rest_id = rest_id,
		})
		return vid

	case .Record_Row:
		record_fields := store_alloc(store, Type_Field_Entry, len(inf.record_fields))
		for i in 0..<len(inf.record_fields) {
			f := inf.record_fields[i]
			record_fields[i] = Type_Field_Entry{
				name = f.name,
				var  = instantiate_rec(store, f.var, subst),
			}
		}
		record_rest := instantiate_rec(store, inf.record_rest, subst)
		vid := fresh_record_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Record_Row,
			record_fields = record_fields,
			record_rest = record_rest,
		})
		return vid

	case .Tag_Union_Row:
		tag_entries := store_alloc(store, Type_Tag_Entry, len(inf.tag_entries))
		for i in 0..<len(inf.tag_entries) {
			te := inf.tag_entries[i]
			payload := store_alloc(store, Type_Var_ID, len(te.payload))
			for j in 0..<len(te.payload) {
				payload[j] = instantiate_rec(store, te.payload[j], subst)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := instantiate_rec(store, inf.tag_rest, subst)
		vid := fresh_tag_row(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = tag_rest,
		})
		return vid

	case .Handle:
		inner_id := instantiate_rec(store, inf.inner_id, subst)
		effect_id := instantiate_rec(store, inf.effect_id, subst)
		vid := fresh_value_var(store, v.span)
		link_var(store, vid, Inferred_Type{
			tag = .Handle,
			inner_id = inner_id,
			effect_id = effect_id,
		})
		return vid
	}

	return resolved
}

deep_clone_type :: proc(store: ^Type_Store, id: Type_Var_ID, span: Source_Span, subst: ^map[Type_Var_ID]Type_Var_ID) -> Type_Var_ID {
	resolved := resolve_var(store, id)

	if existing, ok := subst[resolved]; ok {
		return existing
	}

	v := get_var(store, resolved)

	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked {
		fresh := fresh_var(store, v.kind, v.name, span)
		subst[resolved] = fresh
		return fresh
	}

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return resolved
	}

	switch inf.tag {
	case .Primitive, .Constructor:
		return resolved

	case .Newtype:
		param_ids := store_alloc(store, Type_Var_ID, len(inf.param_ids))
		for i in 0..<len(inf.param_ids) {
			param_ids[i] = deep_clone_type(store, inf.param_ids[i], span, subst)
		}
		inner_id := deep_clone_type(store, inf.inner_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Newtype,
			primitive_name = inf.primitive_name,
			arity = inf.arity,
			param_ids = param_ids,
			inner_id = inner_id,
		})
		subst[resolved] = fresh
		return fresh

	case .Function:
		param_ids := store_alloc(store, Type_Var_ID, len(inf.param_ids))
		for i in 0..<len(inf.param_ids) {
			param_ids[i] = deep_clone_type(store, inf.param_ids[i], span, subst)
		}
		return_id := deep_clone_type(store, inf.return_id, span, subst)
		effect_id := deep_clone_type(store, inf.effect_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Function,
			param_ids = param_ids,
			return_id = return_id,
			effect_id = effect_id,
		})
		subst[resolved] = fresh
		return fresh

	case .Effect_Row:
		effect_entries := store_alloc(store, Effect_Row_Entry, len(inf.effects))
		for i in 0..<len(inf.effects) {
			entry := inf.effects[i]
			type_args := store_alloc(store, Type_Var_ID, len(entry.type_args))
			for j in 0..<len(entry.type_args) {
				type_args[j] = deep_clone_type(store, entry.type_args[j], span, subst)
			}
			effect_entries[i] = Effect_Row_Entry{name = entry.name, type_args = type_args}
		}
		rest_id := deep_clone_type(store, inf.rest_id, span, subst)
		fresh := fresh_effect_row(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Effect_Row,
			effects = effect_entries,
			rest_id = rest_id,
		})
		subst[resolved] = fresh
		return fresh

	case .Record_Row:
		record_fields := store_alloc(store, Type_Field_Entry, len(inf.record_fields))
		for i in 0..<len(inf.record_fields) {
			f := inf.record_fields[i]
			record_fields[i] = Type_Field_Entry{
				name = f.name,
				var  = deep_clone_type(store, f.var, span, subst),
			}
		}
		record_rest := deep_clone_type(store, inf.record_rest, span, subst)
		fresh := fresh_record_row(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Record_Row,
			record_fields = record_fields,
			record_rest = record_rest,
		})
		subst[resolved] = fresh
		return fresh

	case .Tag_Union_Row:
		tag_entries := store_alloc(store, Type_Tag_Entry, len(inf.tag_entries))
		for i in 0..<len(inf.tag_entries) {
			te := inf.tag_entries[i]
			payload := store_alloc(store, Type_Var_ID, len(te.payload))
			for j in 0..<len(te.payload) {
				payload[j] = deep_clone_type(store, te.payload[j], span, subst)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := deep_clone_type(store, inf.tag_rest, span, subst)
		fresh := fresh_tag_row(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			tag_rest = tag_rest,
		})
		subst[resolved] = fresh
		return fresh

	case .Handle:
		inner_id := deep_clone_type(store, inf.inner_id, span, subst)
		effect_id := deep_clone_type(store, inf.effect_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(store, fresh, Inferred_Type{
			tag = .Handle,
			inner_id = inner_id,
			effect_id = effect_id,
		})
		subst[resolved] = fresh
		return fresh
	}

	return resolved
}

subtract_effect_from_row :: proc(store: ^Type_Store, row: Type_Var_ID, effect: Intern_ID, span: Source_Span) -> Type_Var_ID {
	rid := resolve_var(store, row)
	rv := get_var(store, rid)

	inf, is_inf := rv.link.(Inferred_Type)
	if is_inf && inf.tag == .Effect_Row {
		found := false
		for entry in inf.effects {
			if entry.name == effect {
				found = true
				break
			}
		}
		if found {
			if len(inf.effects) == 1 {
				return inf.rest_id
			}
			new_entries := store_alloc(store, Effect_Row_Entry, len(inf.effects) - 1)
			j := 0
			for entry in inf.effects {
				if entry.name != effect {
					new_entries[j] = entry
					j += 1
				}
			}
			new_row := fresh_effect_row(store, span)
			link_var(store, new_row, Inferred_Type{
				tag = .Effect_Row,
				effects = new_entries,
				rest_id = inf.rest_id,
			})
			return new_row
		}
		return rid
	}

	_, is_unlinked := rv.link.(Type_Unlinked)
	if is_unlinked {
		handled_rest := fresh_effect_row(store, span)
		effect_entries := store_alloc(store, Effect_Row_Entry, 1)
		effect_entries[0] = Effect_Row_Entry{name = effect, type_args = {}}
		handled_row := fresh_effect_row(store, span)
		link_var(store, handled_row, Inferred_Type{
			tag = .Effect_Row,
			effects = effect_entries,
			rest_id = handled_rest,
		})
		unify(store, rid, handled_row)
		return handled_rest
	}

	return rid
}

effect_row_nonempty :: proc(store: ^Type_Store, effect_var: Type_Var_ID) -> bool {
	resolved := resolve_var(store, effect_var)
	v := get_var(store, resolved)

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf || inf.tag != .Effect_Row {
		return false
	}

	if len(inf.effects) > 0 {
		return true
	}

	rest_resolved := resolve_var(store, inf.rest_id)
	rest_v := get_var(store, rest_resolved)
	_, rest_unlinked := rest_v.link.(Type_Unlinked)
	if rest_unlinked && !is_generic(store, rest_resolved) {
		return true
	}

	rest_inf, rest_is_inf := rest_v.link.(Inferred_Type)
	if rest_is_inf && rest_inf.tag == .Effect_Row {
		return effect_row_nonempty(store, inf.rest_id)
	}

	return false
}

is_effect_handled :: proc(env: ^Type_Env, effect_id: Intern_ID) -> bool {
	current := env
	for current != nil {
		for e in current.handled_effects {
			if e == effect_id {
				return true
			}
		}
		current = current.parent
	}
	return false
}

typecheck_newtype_construct :: proc(e: ^CExpr_Tag, env: ^Type_Env, store: ^Type_Store) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	nt_info, ok := store.newtype_decls[e.name.name]
	if !ok {
		var_id := fresh_value_var(store, e.span)
		payload_t := make([dynamic]TExpr, 0)
		t := new(TExpr_Tag)
		t^ = TExpr_Tag{
			name = e.name,
			payload = payload_t,
			type_ = tc_ir_type(store, var_id),
			eff_ = tc_eff_type(store, eff),
			span = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	if !is_same_module(env, nt_info.module) {
		nt_str := intern_get(store.interner, e.name.name)
		collector_add_diag(store.collector, diag_newtype_opaque_violation(nt_str, "construct", e.span))
	}

	nt_binding, has_binding := env_lookup(env, e.name.name)
	if !has_binding {
		nt_binding = store.bindings[e.name.name]
	}
	inst_binding := instantiate(store, nt_binding)

	nt_resolved := get_var(store, resolve_var(store, inst_binding))
	nt_inf, is_nt := nt_resolved.link.(Inferred_Type)

	arg_var: Type_Var_ID
	arg_texpr: TExpr
	arg_typed := false
	if is_nt && nt_inf.tag == .Newtype && is_numeric_primitive(store, nt_inf.inner_id) {
		is_int_lit := false
		is_float_lit := false
		#partial switch arg in e.payload[0] {
		case ^CExpr_Int:
			is_int_lit = true
		case ^CExpr_Float:
			is_float_lit = true
		}

		inner_resolved := get_var(store, resolve_var(store, nt_inf.inner_id))
		if inner_inf, inner_ok := inner_resolved.link.(Inferred_Type); inner_ok && inner_inf.tag == .Primitive {
			if is_int_lit || is_float_lit {
				arg_var = make_primitive_type(store, inner_inf.primitive_name, e.span)
				arg_typed = true
				arg_synth := typecheck_synth(e.payload[0], env, store)
				arg_texpr = arg_synth.texpr
			}
		}
	}

	if !arg_typed {
		arg_result := typecheck_synth(e.payload[0], env, store)
		unify(store, eff, arg_result.effects)
		arg_var = arg_result.var_id
		arg_texpr = arg_result.texpr
	}

	if is_nt && nt_inf.tag == .Newtype {
		unify(store, arg_var, nt_inf.inner_id)
	}

	payload_t := make([dynamic]TExpr, 1)
	payload_t[0] = arg_texpr
	t := new(TExpr_Tag)
	t^ = TExpr_Tag{
		name = e.name,
		payload = payload_t,
		type_ = tc_ir_type(store, inst_binding),
		eff_ = tc_eff_type(store, eff),
		span = e.span,
	}
	return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
}

newtype_owning_tag :: proc(store: ^Type_Store, tag_name: Intern_ID) -> (Intern_ID, bool) {
	for nt_name, info in store.newtype_decls {
		for owned in info.owned_tags {
			if owned == tag_name {
				return nt_name, true
			}
		}
	}
	return NO_NAME, false
}

is_same_module :: proc(env: ^Type_Env, defining_module: Intern_ID) -> bool {
	current := env
	for current != nil {
		if current.current_module == defining_module {
			return true
		}
		if current.current_module != NO_NAME && defining_module != NO_NAME {
			if current.current_module == defining_module {
				return true
			}
		}
		current = current.parent
	}
	if defining_module == NO_NAME {
		return true
	}
	return false
}

typecheck_trait_decl :: proc(d: ^CDecl_Trait, env: ^Type_Env, store: ^Type_Store) {
	methods := make([]Trait_Method_Info, len(d.methods))
	for i in 0..<len(d.methods) {
		m := d.methods[i]
		self_var := fresh_value_var(store, m.span)
		param_types := make([dynamic]Type_Var_ID, 0, len(m.params) + 1)
		append(&param_types, self_var)

		for p in m.params {
			if p.type_ann != nil {
				param_var := convert_type_to_var(p.type_ann, store)
				append(&param_types, param_var)
			} else {
				param_var := fresh_value_var(store, p.span)
				append(&param_types, param_var)
			}
		}

		return_type := fresh_value_var(store, m.span)
		if m.return_type != nil {
			return_type = convert_type_to_var(m.return_type, store)
		}

		methods[i] = Trait_Method_Info{
			name = m.name,
			param_types = param_types[:],
			return_type = return_type,
		}
	}

	trait_info := Trait_Info{
		name = d.name.name,
		module = d.name.module,
		parent = d.parent,
		methods = methods,
	}

	store.trait_registry[d.name.name] = trait_info

	trait_var := fresh_value_var(store, d.span)
	env.bindings[d.name.name] = trait_var
	store.bindings[d.name.name] = trait_var
}

verify_trait_conformance :: proc(type_name: Intern_ID, type_module: Intern_ID, trait_name: Intern_ID, span: Source_Span, store: ^Type_Store, env: ^Type_Env) -> bool {
	trait_info, ok := store.trait_registry[trait_name]
	if !ok {
		trait_str := intern_get(store.interner, trait_name)
		collector_add_diag(store.collector, diag_internal(
			fmt.tprintf("trait `{}` not found in registry", trait_str), span))
		return false
	}

	if type_module != trait_info.module && type_module != NO_NAME {
		type_str := intern_get(store.interner, type_name)
		trait_str := intern_get(store.interner, trait_name)
		collector_add_diag(store.collector, diag_orphan_rule_violation(type_str, trait_str, span))
		return false
	}

	for impl in store.trait_impls {
		if impl.trait_name == trait_name && impl.type_name == type_name {
			type_str := intern_get(store.interner, type_name)
			trait_str := intern_get(store.interner, trait_name)
			collector_add_diag(store.collector, diag_overlapping_instance(type_str, trait_str, span))
			return false
		}
	}

	required_traits := collect_all_traits(trait_name, store.trait_registry)

	for req_trait_name in required_traits {
		req_info := store.trait_registry[req_trait_name]
		for method in req_info.methods {
			impl_fn_name := fmt.tprintf("{}_{}", intern_get(store.interner, type_name), intern_get(store.interner, method.name))
			impl_fn_id := intern(store.interner, impl_fn_name)

			impl_fn_var: Type_Var_ID
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
				type_str := intern_get(store.interner, type_name)
				req_trait_str := intern_get(store.interner, req_trait_name)
				method_str := intern_get(store.interner, method.name)
				collector_add_diag(store.collector, diag_missing_trait_method(type_str, req_trait_str, method_str, span))
				return false
			}

			clone_subst := make(map[Type_Var_ID]Type_Var_ID, 8)
			defer delete(clone_subst)

			expected_params := store_alloc(store, Type_Var_ID, len(method.param_types))
			for i in 0..<len(method.param_types) {
				expected_params[i] = deep_clone_type(store, method.param_types[i], span, &clone_subst)
			}

			type_var := store.bindings[type_name]
			unify(store, expected_params[0], type_var)

			expected_return := deep_clone_type(store, method.return_type, span, &clone_subst)
			expected_effect := fresh_effect_row(store, span)

			expected_fn_var := fresh_value_var(store, span)
			link_var(store, expected_fn_var, Inferred_Type{
				tag = .Function,
				param_ids = expected_params,
				return_id = expected_return,
				effect_id = expected_effect,
			})

			expected_sig := format_type_var(store, expected_fn_var)
			actual_sig := format_type_var(store, impl_fn_var)

			diag_count_before := len(store.collector.diagnostics)
			unify_ok := unify(store, impl_fn_var, expected_fn_var)

			if !unify_ok {
				for len(store.collector.diagnostics) > diag_count_before {
					d := &store.collector.diagnostics[len(store.collector.diagnostics) - 1]
					switch d.category {
					case .Warning:  store.collector.warning_count -= 1
					case .Error:    store.collector.error_count -= 1
					case .Internal: store.collector.internal_count -= 1
					}
					delete(d.labels)
					delete(d.hints)
					pop(&store.collector.diagnostics)
				}

				type_str := intern_get(store.interner, type_name)
				req_trait_str := intern_get(store.interner, req_trait_name)
				method_str := intern_get(store.interner, method.name)
				collector_add_diag(store.collector, diag_trait_method_signature_mismatch(
					type_str, req_trait_str, method_str, expected_sig, actual_sig, span))
				return false
			}
		}
	}

	methods := make(map[Intern_ID]Canonical_Name, len(trait_info.methods))
	for method in trait_info.methods {
		impl_fn_name := fmt.tprintf("{}_{}", intern_get(store.interner, type_name), intern_get(store.interner, method.name))
		impl_fn_id := intern(store.interner, impl_fn_name)
		methods[method.name] = Canonical_Name{module = type_module, name = impl_fn_id, is_local = false}
	}

	impl := Trait_Impl{
		trait_name = trait_name,
		type_name = type_name,
		type_module = type_module,
		methods = methods,
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
	case:
		return false
	}
	return false
}

convert_ctype_self_aware :: proc(t: CType, self_var: Type_Var_ID, store: ^Type_Store) -> Type_Var_ID {
	#partial switch ty in t {
	case ^CType_Self:
		return self_var
	case:
		return convert_type_to_var_val(t, store)
	}
	return fresh_value_var(store, Source_Span_ZERO)
}

extract_trait_methods_from_ctype :: proc(t: ^CType, store: ^Type_Store) -> []Trait_Method_Info {
	#partial switch ty in t^ {
	case ^CType_Record:
		methods := make([]Trait_Method_Info, len(ty.fields))
		for f, i in ty.fields {
			self_var := fresh_value_var(store, ty.span)
			param_types := make([dynamic]Type_Var_ID, 0, 4)

			#partial switch ft in f.type {
			case ^CType_Function:
				for p in ft.params {
					append(&param_types, convert_ctype_self_aware(p, self_var, store))
				}
				methods[i] = Trait_Method_Info{
					name = f.name,
					param_types = param_types[:],
					return_type = convert_ctype_self_aware(ft.return_, self_var, store),
				}
			case:
				methods[i] = Trait_Method_Info{
					name = f.name,
					param_types = param_types[:],
					return_type = self_var,
				}
			}
		}
		return methods
	case:
	}
	return make([]Trait_Method_Info, 0)
}

check_constraint_violation :: proc(type_var_id: Type_Var_ID, store: ^Type_Store) {
	constraints, has_constraints := store.type_constraints[type_var_id]
	if !has_constraints {
		return
	}

	resolved := resolve_var(store, type_var_id)
	rv := get_var(store, resolved)

	impl_type_name: Intern_ID = NO_NAME
	if inf, is_inf := rv.link.(Inferred_Type); is_inf {
		if inf.tag == .Newtype || inf.tag == .Primitive || inf.tag == .Constructor {
			impl_type_name = inf.primitive_name
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
			constraint_str := intern_get(store.interner, constraint_name)
			type_name := "?"
			if impl_type_name != NO_NAME {
				type_name = intern_get(store.interner, impl_type_name)
			}
			collector_add_diag(store.collector, diag_constraint_violation(type_name, constraint_str, rv.span))
		}
	}
}

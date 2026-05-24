package semantics

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:frontend"
import "camp:diagnostics"

Type_Env :: struct {
	bindings:        map[base.Intern_ID]base.Type_Var_ID,
	parent:          ^Type_Env,
	handled_effects: [dynamic]base.Intern_ID,
	current_module:  base.Intern_ID,
	spawned_handles: [dynamic]base.Source_Span,
}

Type_Result :: struct {
	var_id:  base.Type_Var_ID,
	effects: base.Type_Var_ID,
}

Synth_Result :: struct {
	var_id:  base.Type_Var_ID,
	effects: base.Type_Var_ID,
	texpr:   TExpr,
}

Pat_Result :: struct {
	var_id:  base.Type_Var_ID,
	effects: base.Type_Var_ID,
	tpat:    TPattern,
}

env_lookup :: proc(env: ^Type_Env, name: base.Intern_ID) -> (base.Type_Var_ID, bool) {
	current := env
	for current != nil {
		if existing, ok := current.bindings[name]; ok {
			return existing, true
		}
		current = current.parent
	}
	return base.Type_Var_ID(-1), false
}

check_shadow :: proc(env: ^Type_Env, name: base.Intern_ID, store: ^Type_Store, span: base.Source_Span) {
	if _, exists := env_lookup(env, name); exists {
		name_str := base.intern_get(store.interner, name)
		diagnostics.collector_add_diag(store.collector, diagnostics.diag_shadow(name, name_str, span))
	}
}

fresh_with_effects :: proc(store: ^Type_Store, span: base.Source_Span) -> (base.Type_Var_ID, base.Type_Var_ID) {
	v := fresh_value_var(store, span)
	e := fresh_effect_row(store, span)
	return v, e
}

type_eff_pair :: proc(store: ^Type_Store, var_id: base.Type_Var_ID, eff_var: base.Type_Var_ID) -> (base.IR_Type, base.IR_Type) {
	return lower_type(store, var_id), lower_effect_type(store, eff_var)
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

find_similar_names :: proc(name: string, env: ^Type_Env, interner: ^base.Intern_Table) -> [dynamic]string {
	names: [dynamic]string
	current := env
	for current != nil {
		for k, _ in current.bindings {
			k_str := base.intern_get(interner, k)
			if levenshtein_distance(name, k_str) <= 2 {
				append(&names, k_str)
			}
		}
		current = current.parent
	}
	return names
}

format_effect_row :: proc(store: ^Type_Store, effects: base.Type_Var_ID) -> string {
	rid := resolve_var(store, effects)
	rv := store.vars[int(rid)]
	it, is_inferred := rv.link.(Inferred_Type)
	if is_inferred && it.tag == .Effect_Row {
		if len(it.effects) == 0 do return "[]"
		builder: strings.Builder
		strings.builder_init_len_cap(&builder, 0, 64)
		strings.write_rune(&builder, '[')
		for entry, i in it.effects {
			if i > 0 do strings.write_string(&builder, " | ")
			strings.write_string(&builder, base.intern_get(store.interner, base.Intern_ID(entry.name)))
		}
		strings.write_rune(&builder, ']')
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	}
	return "[]"
}

typecheck_file :: proc(file: CFile, store: ^Type_Store, current_module: base.Intern_ID = base.NO_NAME) -> TFile {
	env: Type_Env
	env.bindings = make(map[base.Intern_ID]base.Type_Var_ID, 64)
	env.parent = nil
	env.handled_effects = make([dynamic]base.Intern_ID, 0, 8)
	env.current_module = current_module
	env.spawned_handles = make([dynamic]base.Source_Span, 0, 8)
	defer delete(env.bindings)
	defer delete(env.handled_effects)
	defer delete(env.spawned_handles)

	tdecls := make([dynamic]TDecl, 0, len(file.decls))
	imports: [dynamic]base.Deferred_Import
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
				if type_mod == base.NO_NAME {
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
		name_id := base.intern(store.interner, bt.name)
		var_id := fresh_value_var(store, base.Source_Span_ZERO)
		inf := Inferred_Type{tag = bt.kind, primitive_name = name_id}
		if bt.kind == .Constructor {
			inf = Inferred_Type{tag = .Constructor, primitive_name = name_id, arity = 0}
		}
		link_var(store, var_id, inf)
		store.bindings[name_id] = var_id
	}

	for ct in PRELUDE_CONSTRUCTOR_TYPES {
		name_id := base.intern(store.interner, ct.name)
		var_id := fresh_value_var(store, base.Source_Span_ZERO)
		link_var(store, var_id, Inferred_Type{tag = .Constructor, primitive_name = name_id, arity = ct.arity})
		store.bindings[name_id] = var_id
	}

	for td in PRELUDE_TAG_DECLS {
		name_id := base.intern(store.interner, td.name)
		var_id := fresh_value_var(store, base.Source_Span_ZERO)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		payload: []base.Type_Var_ID = nil
		if td.has_payload {
			p := fresh_value_var(store, base.Source_Span_ZERO)
			payload = make([]base.Type_Var_ID, 1, store.allocator)
			payload[0] = p
		}
		tag_entries[0] = Type_Tag_Entry{name = name_id, payload = payload}
		rest := fresh_tag_row(store, base.Source_Span_ZERO)
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
			ann_var := convert_type_to_var(d.type_ann, store, env)
			unify(store, result.var_id, ann_var)
		}

		if !d.is_effectful {
			resolved := resolve_var(store, result.var_id)
			v := store.vars[int(resolved)]
			if inf, ok := v.link.(Inferred_Type); ok && inf.tag == .Function {
				if effect_row_nonempty(store, inf.effect_id) {
					name_str := base.intern_get(store.interner, d.name.name)
					effects_str := format_effect_row(store, inf.effect_id)
					diagnostics.collector_add_diag(store.collector, diagnostics.diag_effectful_naming(name_str, effects_str, d.span))
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
			param_types := make([]base.Type_Var_ID, len(op.params), store.allocator)
			params_t := make([dynamic]TFunc_Param, len(op.params))
			for p, j in op.params {
				if p.type_ann != nil {
					param_types[j] = convert_type_to_var(p.type_ann, store, env)
				} else {
					param_types[j] = fresh_value_var(store, d.span)
				}
				params_t[j] = TFunc_Param{
					name = p.name,
					type_ = lower_type(store, param_types[j]),
					eff_ = lower_effect_type(store, fresh_effect_row(store, p.span)),
					span = p.span,
				}
			}
			ret_type := fresh_value_var(store, d.span)
			if op.return_type != nil {
				ret_type = convert_type_to_var(op.return_type, store, env)
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
				return_type = lower_type(store, ret_type),
				return_effects = lower_effect_type(store, fresh_effect_row(store, op.span)),
				span = op.span,
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
			tp_t[i] = frontend.Type_Param{name = tp.name, constraints = constraints, is_effect = tp.is_effect}
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
				return_type = lower_type(store, fresh_value_var(store, m.span)),
				effects = lower_effect_type(store, fresh_effect_row(store, m.span)),
				span = m.span,
			}
			for p, j in m.params {
				if p.type_ann != nil {
					pv := convert_type_to_var(p.type_ann, store, env)
					td.methods[i].params[j] = TFunc_Param{
						name = p.name,
						type_ = lower_type(store, pv),
						eff_ = lower_effect_type(store, fresh_effect_row(store, p.span)),
						span = p.span,
					}
				} else {
					td.methods[i].params[j] = TFunc_Param{
						name = p.name,
						type_ = lower_type(store, fresh_value_var(store, p.span)),
						eff_ = lower_effect_type(store, fresh_effect_row(store, p.span)),
						span = p.span,
					}
				}
			}
		}
		return TDecl(td)

	case ^CDecl_Alias:
		convert_type_to_var(d.target, store, env)
		td := new(TDecl_Alias)
		td^ = TDecl_Alias{
			name = d.name,
			is_pub = d.is_pub,
			target = d.target,
			span = d.span,
		}
		if d.target != nil && ctype_contains_self(d.target^) {
			methods := extract_trait_methods_from_ctype(d.target, store, env)
			trait_module := d.name.module
			if trait_module == base.NO_NAME {
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
			type_ = lower_type(store, nt_var),
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
		bool_name := base.intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, base.Source_Span_ZERO)
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
	if inf, is_inf := inner_resolved.link.(Inferred_Type); is_inf && inf.tag == .Tag_Union_Row {
		for te in inf.tag_entries {
			append(&owned_tags, te.name)
		}
	}

	param_ids_slice := make([]base.Intern_ID, len(d.type_params), store.allocator)
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

	owned_tags_slice := make([]base.Intern_ID, len(owned_tags), store.allocator)
	for i in 0..<len(owned_tags) {
		owned_tags_slice[i] = owned_tags[i]
	}

	defining_module := d.name.module
	if defining_module == base.NO_NAME {
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
		name := base.intern(store.interner, "I64")
		var_id := make_primitive_type(store, name, e.span)
		store.literal_int_values[var_id] = i128(e.value)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Int)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Int{value = e.value, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Float:
		name := base.intern(store.interner, "F64")
		var_id := make_primitive_type(store, name, e.span)
		store.literal_float_values[var_id] = e.value
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Float)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Float{value = e.value, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_String:
		name := base.intern(store.interner, "Str")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_String)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_String{value = e.value, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Bool:
		name := base.intern(store.interner, "Bool")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Bool)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Bool{value = e.value, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Name:
		if existing, ok := env_lookup(env, e.name.name); ok {
			inst := instantiate(store, existing)
			eff := fresh_effect_row(store, e.span)
			t := new(TExpr_Name)
			type_ir, eff_ir := type_eff_pair(store, inst, eff)
			t^ = TExpr_Name{name = e.name, type_ = type_ir, eff_ = eff_ir, span = e.span}
			return Synth_Result{var_id = inst, effects = eff, texpr = TExpr(t)}
		}
		var_id := fresh_value_var(store, e.span)
		name_str := base.intern_get(store.interner, e.name.name)
		similar := find_similar_names(name_str, env, store.interner)
		defer delete(similar)
		diagnostics.collector_add_diag(store.collector, diagnostics.diag_undefined_name(name_str, similar[:], e.span))
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Name)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Name{name = e.name, type_ = type_ir, eff_ = eff_ir, span = e.span}
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

	case ^CExpr_Nominal_Construct:
		type_var, eff := fresh_with_effects(store, e.span)
		payload := make([dynamic]TExpr, len(e.payload))
		for p, i in e.payload {
			p_result := typecheck_synth(p, env, store)
			unify(store, eff, p_result.effects)
			payload[i] = p_result.texpr
		}
		t := new(TExpr_Nominal_Construct)
		t^ = TExpr_Nominal_Construct{
			type_name = e.type_name,
			variant = e.variant,
			payload = payload,
			resolved_type = type_var,
			span = e.span,
		}
		return Synth_Result{var_id = type_var, effects = eff, texpr = TExpr(t)}

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
		if e.type_ann != nil {
			ann_var := convert_type_to_var(e.type_ann, store, env)
			unify(store, result.var_id, ann_var)
		}
		target_t: TExpr
		#partial switch target in e.target {
		case ^CExpr_Name:
			check_shadow(env, target.name.name, store, e.span)
			env.bindings[target.name.name] = result.var_id
			t_name := new(TExpr_Name)
			type_ir, eff_ir := type_eff_pair(store, result.var_id, result.effects)
			t_name^ = TExpr_Name{name = target.name, type_ = type_ir, eff_ = eff_ir, span = target.span}
			target_t = TExpr(t_name)
		case:
			target_t = typecheck_synth(e.target, env, store).texpr
		}
		t := new(TExpr_Assign)
		type_ir, eff_ir := type_eff_pair(store, result.var_id, result.effects)
		t^ = TExpr_Assign{target = target_t, value = result.texpr, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Return:
		result := typecheck_synth(e.value, env, store)
		t := new(TExpr_Return)
		type_ir, eff_ir := type_eff_pair(store, result.var_id, result.effects)
		t^ = TExpr_Return{value = result.texpr, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Crash:
		var_id, eff := fresh_with_effects(store, e.span)
		msg_result := typecheck_synth(e.message, env, store)
		t := new(TExpr_Crash)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Crash{message = msg_result.texpr, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Interpolated_String:
		str_name := base.intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, e.span)
		eff := fresh_effect_row(store, e.span)
		display_name := base.intern(store.interner, "Display")
		to_str_name := base.intern(store.interner, "to_str")
		parts_t := make([dynamic]TExpr_String_Part, 0, len(e.parts))
		for part in e.parts {
			switch p in part {
			case ^CExpr_String_Literal:
				clit := new(TExpr_String_Literal)
				type_ir, eff_ir := type_eff_pair(store, str_var, eff)
				clit^ = TExpr_String_Literal{
					value = p.value,
					type_ = type_ir,
					eff_ = eff_ir,
					span = p.span,
				}
				append(&parts_t, TExpr_String_Part(clit))
			case CExpr:
				part_result := typecheck_synth(p, env, store)
				unify(store, eff, part_result.effects)

				expr_part := new(TExpr_String_Expr)
				expr_part.expr = part_result.texpr

				resolved := resolve_var(store, part_result.var_id)
				v := store.vars[int(resolved)]
				type_name: base.Intern_ID = base.NO_NAME
				if inf, ok := v.link.(Inferred_Type); ok {
					type_name = inf.primitive_name
				}

				if type_name == str_name {
					expr_part.needs_to_str = false
					expr_part.display_impl = base.Canonical_Name{}
				} else if type_name != base.NO_NAME {
					impl, found := find_trait_impl(store, display_name, type_name)
					if found {
						if to_str_impl, has := impl.methods[to_str_name]; has {
							expr_part.needs_to_str = true
							expr_part.display_impl = to_str_impl
						} else {
							type_str := base.intern_get(store.interner, type_name)
							diagnostics.collector_add_diag(store.collector, diagnostics.diag_display_not_implemented(type_str, e.span))
							expr_part.needs_to_str = false
							expr_part.display_impl = base.Canonical_Name{}
						}
					} else {
						type_str := base.intern_get(store.interner, type_name)
						diagnostics.collector_add_diag(store.collector, diagnostics.diag_display_not_implemented(type_str, e.span))
						expr_part.needs_to_str = false
						expr_part.display_impl = base.Canonical_Name{}
					}
				} else {
					diagnostics.collector_add_diag(store.collector, diagnostics.diag_display_not_implemented("unknown type", e.span))
					expr_part.needs_to_str = false
					expr_part.display_impl = base.Canonical_Name{}
				}

				append(&parts_t, TExpr_String_Part(expr_part))
			}
		}
		t := new(TExpr_Interpolated_String)
		type_ir, eff_ir := type_eff_pair(store, str_var, eff)
		t^ = TExpr_Interpolated_String{
			parts = parts_t,
			is_raw = e.is_raw,
			is_multiline = e.is_multiline,
			type_ = type_ir,
			eff_ = eff_ir,
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
			arm_env.bindings = make(map[base.Intern_ID]base.Type_Var_ID, len(arm.params) + 4)
			arm_env.parent = env
			arm_env.handled_effects = make([dynamic]base.Intern_ID, 0, 8)
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
						diagnostics.collector_add_diag(store.collector, diagnostics.diag_internal(fmt.tprintf(
							"handler arm `{}` has {} parameters, expected {}",
							base.intern_get(store.interner, arm.op),
							actual_param_count,
							expected_param_count,
						), arm.span))
					}
				} else {
					effect_str := base.intern_get(store.interner, e.effect.name)
					op_str := base.intern_get(store.interner, arm.op)
					diagnostics.collector_add_diag(store.collector, diagnostics.diag_internal(fmt.tprintf(
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
		type_ir, eff_ir := type_eff_pair(store, body_result.var_id, result_effects)
		t^ = TExpr_Handle{
			effect = e.effect,
			is_shallow = e.is_shallow,
			body = body_result.texpr,
			arms = arms_t,
			type_ = type_ir,
			eff_ = eff_ir,
			span = e.span,
		}
		return Synth_Result{var_id = body_result.var_id, effects = result_effects, texpr = TExpr(t)}

	case ^CExpr_Perform:
		var_id, effects := fresh_with_effects(store, e.span)
		args_t := make([dynamic]TExpr, len(e.args))
		for arg, i in e.args {
			arg_result := typecheck_synth(arg, env, store)
			_ = arg_result
			args_t[i] = arg_result.texpr
		}
		t := new(TExpr_Perform)
		type_ir, eff_ir := type_eff_pair(store, var_id, effects)
		t^ = TExpr_Perform{effect = e.effect, op = e.op, args = args_t, type_ = type_ir, eff_ = eff_ir, span = e.span}
		return Synth_Result{var_id = var_id, effects = effects, texpr = TExpr(t)}

	case ^CExpr_Par:
		var_id, eff := fresh_with_effects(store, e.span)

		if e.for_var != 0 {
			iter_result := typecheck_synth(e.for_iter, env, store)
			unify(store, eff, iter_result.effects)
			element_var := fresh_value_var(store, e.span)
			check_shadow(env, e.for_var, store, e.span)
			env.bindings[e.for_var] = element_var
			body_result := typecheck_synth(e.for_body, env, store)
			unify(store, eff, body_result.effects)
			t := new(TExpr_Par)
			type_ir, eff_ir := type_eff_pair(store, var_id, eff)
			t^ = TExpr_Par{
				for_var = e.for_var,
				for_iter = iter_result.texpr,
				for_body = body_result.texpr,
				type_ = type_ir,
				eff_ = eff_ir,
				span = e.span,
			}
			return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
		}

		exprs := make([dynamic]TExpr, 0, len(e.expressions))
		last_var_id: base.Type_Var_ID = var_id
		for expr in e.expressions {
			result := typecheck_synth(expr, env, store)
			unify(store, eff, result.effects)
			append(&exprs, result.texpr)
			last_var_id = result.var_id
		}
		unify(store, var_id, last_var_id)
		t := new(TExpr_Par)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Par{
			expressions = exprs,
			type_ = type_ir,
			eff_ = eff_ir,
			span = e.span,
		}
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

		unit_name := base.intern(store.interner, "Unit")
		unit_var := make_primitive_type(store, unit_name, e.span)

		tfor := new(TExpr_For)
		type_ir, eff_ir := type_eff_pair(store, unit_var, eff)
		tfor^ = TExpr_For{
			var      = e.var,
			iterable = iter_result.texpr,
			body     = body_result.texpr,
			type_    = type_ir,
			eff_     = eff_ir,
			span     = e.span,
		}
		return Synth_Result{var_id = unit_var, effects = eff, texpr = TExpr(tfor)}
	}
	var_id, eff := fresh_with_effects(store, base.Source_Span_ZERO)
	t := new(TExpr_Int)
	type_ir, eff_ir := type_eff_pair(store, var_id, eff)
	t^ = TExpr_Int{type_ = type_ir, eff_ = eff_ir, span = base.Source_Span_ZERO}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

mark_effect_type_params_in_ctype :: proc(type_params: [dynamic]frontend.Type_Param, effects_type: ^CType) {
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

convert_type_to_var :: proc(t: ^CType, store: ^Type_Store, env: ^Type_Env) -> base.Type_Var_ID {
	return convert_type_to_var_val(t^, store, env)
}

convert_type_to_var_val :: proc(t: CType, store: ^Type_Store, env: ^Type_Env) -> base.Type_Var_ID {
	switch ty in t {
	case ^CType_Primitive:
		return make_primitive_type(store, ty.name, ty.span)

	case ^CType_Variable:
		if existing, ok := env_lookup(env, ty.name); ok {
			return existing
		}
		return fresh_value_var(store, ty.span)

	case ^CType_Wildcard:
		return fresh_value_var(store, ty.span)

	case ^CType_Self:
		return fresh_value_var(store, ty.span)

	case ^CType_Function:
		ft := ty
		param_ids := store_alloc(store, base.Type_Var_ID, len(ft.params))
		for i in 0..<len(ft.params) {
			param_ids[i] = convert_type_to_var_val(ft.params[i], store, env)
		}
		return_id := convert_type_to_var_val(ft.return_, store, env)
		effect_id := fresh_effect_row(store, ft.span)
		if ft.effects != nil {
			effect_id = convert_type_to_var(ft.effects, store, env)
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
		arg_ids := store_alloc(store, base.Type_Var_ID, len(ty.args))
		for &a, i in ty.args {
			arg_ids[i] = convert_type_to_var_val(a, store, env)
		}
		vid := fresh_value_var(store, ty.span)
		handle_name := base.intern(store.interner, "Handle")
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
				var  = convert_type_to_var_val(rt.fields[i].type, store, env),
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
			payload := store_alloc(store, base.Type_Var_ID, len(tg.payload))
			for j in 0..<len(tg.payload) {
				payload[j] = convert_type_to_var_val(tg.payload[j], store, env)
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
			type_args := store_alloc(store, base.Type_Var_ID, len(ce.type_args))
			for j in 0..<len(ce.type_args) {
				type_args[j] = convert_type_to_var(&ce.type_args[j], store, env)
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
	return fresh_value_var(store, base.Source_Span_ZERO)
}

instantiate :: proc(store: ^Type_Store, var_id: base.Type_Var_ID) -> base.Type_Var_ID {
	subst := make(map[base.Type_Var_ID]base.Type_Var_ID, 8)
	defer delete(subst)
	return instantiate_rec(store, var_id, &subst)
}

instantiate_rec :: proc(store: ^Type_Store, var_id: base.Type_Var_ID, subst: ^map[base.Type_Var_ID]base.Type_Var_ID) -> base.Type_Var_ID {
	resolved := resolve_var(store, var_id)
	v := store.vars[int(resolved)]

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
		param_ids := store_alloc(store, base.Type_Var_ID, len(inf.param_ids))
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
		param_ids := store_alloc(store, base.Type_Var_ID, len(inf.param_ids))
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
			type_args := store_alloc(store, base.Type_Var_ID, len(entry.type_args))
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
		vid := fresh_value_var(store, v.span)
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
			payload := store_alloc(store, base.Type_Var_ID, len(te.payload))
			for j in 0..<len(te.payload) {
				payload[j] = instantiate_rec(store, te.payload[j], subst)
			}
			tag_entries[i] = Type_Tag_Entry{
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := instantiate_rec(store, inf.tag_rest, subst)
		vid := fresh_value_var(store, v.span)
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

deep_clone_type :: proc(store: ^Type_Store, id: base.Type_Var_ID, span: base.Source_Span, subst: ^map[base.Type_Var_ID]base.Type_Var_ID) -> base.Type_Var_ID {
	resolved := resolve_var(store, id)

	if existing, ok := subst[resolved]; ok {
		return existing
	}

	v := store.vars[int(resolved)]

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
		param_ids := store_alloc(store, base.Type_Var_ID, len(inf.param_ids))
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
		param_ids := store_alloc(store, base.Type_Var_ID, len(inf.param_ids))
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
			type_args := store_alloc(store, base.Type_Var_ID, len(entry.type_args))
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
			payload := store_alloc(store, base.Type_Var_ID, len(te.payload))
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

subtract_effect_from_row :: proc(store: ^Type_Store, row: base.Type_Var_ID, effect: base.Intern_ID, span: base.Source_Span) -> base.Type_Var_ID {
	rid := resolve_var(store, row)
	rv := store.vars[int(rid)]

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

effect_row_nonempty :: proc(store: ^Type_Store, effect_var: base.Type_Var_ID) -> bool {
	resolved := resolve_var(store, effect_var)
	v := store.vars[int(resolved)]

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf || inf.tag != .Effect_Row {
		return false
	}

	if len(inf.effects) > 0 {
		return true
	}

	rest_resolved := resolve_var(store, inf.rest_id)
	rest_v := store.vars[int(rest_resolved)]
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

is_effect_handled :: proc(env: ^Type_Env, effect_id: base.Intern_ID) -> bool {
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
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Tag{
			name = e.name,
			payload = payload_t,
			type_ = type_ir,
			eff_ = eff_ir,
			span = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	if !is_same_module(env, nt_info.module) {
		nt_str := base.intern_get(store.interner, e.name.name)
		diagnostics.collector_add_diag(store.collector, diagnostics.diag_newtype_opaque_violation(nt_str, "construct", e.span))
	}

	nt_binding, has_binding := env_lookup(env, e.name.name)
	if !has_binding {
		nt_binding = store.bindings[e.name.name]
	}
	inst_binding := instantiate(store, nt_binding)

	nt_resolved := store.vars[int(resolve_var(store, inst_binding))]
	nt_inf, is_nt := nt_resolved.link.(Inferred_Type)

	arg_var: base.Type_Var_ID
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

		inner_resolved := store.vars[int(resolve_var(store, nt_inf.inner_id))]
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
	type_ir, eff_ir := type_eff_pair(store, inst_binding, eff)
	t^ = TExpr_Tag{
		name = e.name,
		payload = payload_t,
		type_ = type_ir,
		eff_ = eff_ir,
		span = e.span,
	}
	return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
}

newtype_owning_tag :: proc(store: ^Type_Store, tag_name: base.Intern_ID) -> (base.Intern_ID, bool) {
	for nt_name, info in store.newtype_decls {
		for owned in info.owned_tags {
			if owned == tag_name {
				return nt_name, true
			}
		}
	}
	return base.NO_NAME, false
}

is_same_module :: proc(env: ^Type_Env, defining_module: base.Intern_ID) -> bool {
	current := env
	for current != nil {
		if current.current_module == defining_module {
			return true
		}
		if current.current_module != base.NO_NAME && defining_module != base.NO_NAME {
			if current.current_module == defining_module {
				return true
			}
		}
		current = current.parent
	}
	if defining_module == base.NO_NAME {
		return true
	}
	return false
}

typecheck_trait_decl :: proc(d: ^CDecl_Trait, env: ^Type_Env, store: ^Type_Store) {
	methods := make([]Trait_Method_Info, len(d.methods))
	for i in 0..<len(d.methods) {
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

verify_trait_conformance :: proc(type_name: base.Intern_ID, type_module: base.Intern_ID, trait_name: base.Intern_ID, span: base.Source_Span, store: ^Type_Store, env: ^Type_Env) -> bool {
	trait_info, ok := store.trait_registry[trait_name]
	if !ok {
		trait_str := base.intern_get(store.interner, trait_name)
		diagnostics.collector_add_diag(store.collector, diagnostics.diag_internal(
			fmt.tprintf("trait `{}` not found in registry", trait_str), span))
		return false
	}

	if type_module != trait_info.module && type_module != base.NO_NAME {
		type_str := base.intern_get(store.interner, type_name)
		trait_str := base.intern_get(store.interner, trait_name)
		diagnostics.collector_add_diag(store.collector, diagnostics.diag_orphan_rule_violation(type_str, trait_str, span))
		return false
	}

	for impl in store.trait_impls {
		if impl.trait_name == trait_name && impl.type_name == type_name {
			type_str := base.intern_get(store.interner, type_name)
			trait_str := base.intern_get(store.interner, trait_name)
			diagnostics.collector_add_diag(store.collector, diagnostics.diag_overlapping_instance(type_str, trait_str, span))
			return false
		}
	}

	required_traits := collect_all_traits(trait_name, store.trait_registry)

	for req_trait_name in required_traits {
		req_info := store.trait_registry[req_trait_name]
		for method in req_info.methods {
			impl_fn_name := fmt.tprintf("{}_{}", base.intern_get(store.interner, type_name), base.intern_get(store.interner, method.name))
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
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_missing_trait_method(type_str, req_trait_str, method_str, span))
				return false
			}

			clone_subst := make(map[base.Type_Var_ID]base.Type_Var_ID, 8)
			defer delete(clone_subst)

			expected_params := store_alloc(store, base.Type_Var_ID, len(method.param_types))
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

				type_str := base.intern_get(store.interner, type_name)
				req_trait_str := base.intern_get(store.interner, req_trait_name)
				method_str := base.intern_get(store.interner, method.name)
				diagnostics.collector_add_diag(store.collector, diagnostics.diag_trait_method_signature_mismatch(
					type_str, req_trait_str, method_str, expected_sig, actual_sig, span))
				return false
			}
		}
	}

	methods := make(map[base.Intern_ID]base.Canonical_Name, len(trait_info.methods))
	for method in trait_info.methods {
		impl_fn_name := fmt.tprintf("{}_{}", base.intern_get(store.interner, type_name), base.intern_get(store.interner, method.name))
		impl_fn_id := base.intern(store.interner, impl_fn_name)
		methods[method.name] = base.Canonical_Name{module = type_module, name = impl_fn_id, is_local = false}
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

convert_ctype_self_aware :: proc(t: CType, self_var: base.Type_Var_ID, store: ^Type_Store, env: ^Type_Env) -> base.Type_Var_ID {
	#partial switch ty in t {
	case ^CType_Self:
		return self_var
	case:
		return convert_type_to_var_val(t, store, env)
	}
	return fresh_value_var(store, base.Source_Span_ZERO)
}

extract_trait_methods_from_ctype :: proc(t: ^CType, store: ^Type_Store, env: ^Type_Env) -> []Trait_Method_Info {
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
				methods[i] = Trait_Method_Info{
					name = f.name,
					param_types = param_types[:],
					return_type = convert_ctype_self_aware(ft.return_, self_var, store, env),
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

check_constraint_violation :: proc(type_var_id: base.Type_Var_ID, store: ^Type_Store) {
	constraints, has_constraints := store.type_constraints[type_var_id]
	if !has_constraints {
		return
	}

	resolved := resolve_var(store, type_var_id)
	rv := store.vars[int(resolved)]

	impl_type_name: base.Intern_ID = base.NO_NAME
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
			constraint_str := base.intern_get(store.interner, constraint_name)
			type_name := "?"
			if impl_type_name != base.NO_NAME {
				type_name = base.intern_get(store.interner, impl_type_name)
			}
			diagnostics.collector_add_diag(store.collector, diagnostics.diag_constraint_violation(type_name, constraint_str, rv.span))
		}
	}
}

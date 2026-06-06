package semantics

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:diagnostics"
import "camp:frontend"

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

check_shadow :: proc(
	env: ^Type_Env,
	name: base.Intern_ID,
	store: ^Type_Store,
	span: base.Source_Span,
) {
	if _, exists := env_lookup(env, name); exists {
		name_str := base.intern_get(store.interner, name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_shadow(name, name_str, span),
		)
	}
}

fresh_with_effects :: proc(
	store: ^Type_Store,
	span: base.Source_Span,
) -> (
	base.Type_Var_ID,
	base.Type_Var_ID,
) {
	v := fresh_value_var(store, span)
	e := fresh_effect_row(store, span)
	return v, e
}

type_eff_pair :: proc(
	store: ^Type_Store,
	var_id: base.Type_Var_ID,
	eff_var: base.Type_Var_ID,
) -> (
	base.IR_Type,
	base.IR_Type,
) {
	return lower_type(store, var_id), lower_effect_type(store, eff_var)
}

levenshtein_distance :: proc(a: string, b: string) -> int {
	if len(a) == 0 do return len(b)
	if len(b) == 0 do return len(a)

	a_len := len(a)
	b_len := len(b)
	dist: [dynamic][dynamic]int
	dist = make([dynamic][dynamic]int, a_len + 1)
	for i in 0 ..< a_len + 1 {
		dist[i] = make([dynamic]int, b_len + 1)
		dist[i][0] = i
	}
	for j in 0 ..< b_len + 1 {
		dist[0][j] = j
	}
	defer {
		for i in 0 ..< a_len + 1 {
			delete(dist[i])
		}
		delete(dist)
	}

	for i in 1 ..< a_len + 1 {
		for j in 1 ..< b_len + 1 {
			cost := 1
			if a[i - 1] == b[j - 1] do cost = 0
			dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + cost)
		}
	}

	return dist[a_len][b_len]
}

find_similar_names :: proc(
	name: string,
	env: ^Type_Env,
	interner: ^base.Intern_Table,
) -> [dynamic]string {
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
	it_effect, is_effect := it.(Inferred_Effect_Row)
	if is_inferred && is_effect {
		if len(it_effect.effects) == 0 do return "[]"
		builder: strings.Builder
		strings.builder_init_len_cap(&builder, 0, 64)
		strings.write_rune(&builder, '[')
		for entry, i in it_effect.effects {
			if i > 0 do strings.write_string(&builder, " | ")
			strings.write_string(
				&builder,
				base.intern_get(store.interner, base.Intern_ID(entry.name)),
			)
		}
		strings.write_rune(&builder, ']')
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	}
	return "[]"
}

typecheck_file :: proc(
	file: CFile,
	store: ^Type_Store,
	current_module: base.Intern_ID = base.NO_NAME,
) -> TFile {
	env: Type_Env
	env.bindings = make(map[base.Intern_ID]base.Type_Var_ID, 64)
	env.parent = nil
	env.handled_effects = make([dynamic]base.Intern_ID, 0, 8)
	env.current_module = current_module
	env.spawned_handles = make([dynamic]base.Source_Span, 0, 8)
	defer delete(env.bindings)
	defer delete(env.handled_effects)
	defer delete(env.spawned_handles)
	defer {
		for span in env.spawned_handles {
			diagnostics.collector_add_diag(store.collector, diagnostics.diag_unjoined_spawn(span))
		}
	}

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


	return TFile{path = file.path, decls = tdecls, imports = imports, span = file.span}
}

inject_prelude :: proc(store: ^Type_Store) {
	for bt in PRELUDE_BUILTIN_TYPES {
		name_id := base.intern(store.interner, bt.name)
		var_id := fresh_value_var(store, base.Source_Span_ZERO)
		if bt.is_constructor {
			link_var(store, var_id, Inferred_Constructor{primitive_name = name_id, arity = 0})
		} else {
			link_var(store, var_id, Inferred_Primitive{primitive_name = name_id})
		}
		store.bindings[name_id] = var_id
	}

	for ct in PRELUDE_CONSTRUCTOR_TYPES {
		name_id := base.intern(store.interner, ct.name)
		var_id := fresh_value_var(store, base.Source_Span_ZERO)
		link_var(store, var_id, Inferred_Constructor{primitive_name = name_id, arity = ct.arity})
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
		tag_entries[0] = Type_Tag_Entry {
			name    = name_id,
			payload = payload,
		}
		rest := fresh_tag_row(store, base.Source_Span_ZERO)
		link_var(store, var_id, Inferred_Tag_Union_Row{tag_entries = tag_entries, tag_rest = rest})
		store.bindings[name_id] = var_id
	}

	inject_prelude_effects_typecheck(store)
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
		t^ = TExpr_Int {
			value = e.value,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Float:
		// Use type annotation if present, otherwise default to F64
		var_id: base.Type_Var_ID
		if e.type_ann != nil {
			var_id = convert_type_to_var(e.type_ann, store, env)
		} else {
			name := base.intern(store.interner, "F64")
			var_id = make_primitive_type(store, name, e.span)
		}
		store.literal_float_values[var_id] = e.value
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Float)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Float {
			value = e.value,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_String:
		name := base.intern(store.interner, "Str")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_String)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_String {
			value = e.value,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Bool:
		name := base.intern(store.interner, "Bool")
		var_id := make_primitive_type(store, name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Bool)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Bool {
			value = e.value,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Char:
		i64_name := base.intern(store.interner, "I64")
		var_id := make_primitive_type(store, i64_name, e.span)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Char)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Char {
			value = e.value,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Todo:
		var_id, eff := fresh_with_effects(store, e.span)
		msg: TExpr
		if e.message != nil {
			msg_result := typecheck_synth(e.message, env, store)
			msg = msg_result.texpr
			unify(store, eff, msg_result.effects)
		}
		t := new(TExpr_Todo)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Todo {
			message = msg,
			type_   = type_ir,
			eff_    = eff_ir,
			span    = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Name:
		if existing, ok := env_lookup(env, e.name.name); ok {
			inst := instantiate(store, existing)
			eff := fresh_effect_row(store, e.span)
			t := new(TExpr_Name)
			type_ir, eff_ir := type_eff_pair(store, inst, eff)
			t^ = TExpr_Name {
				name  = e.name,
				type_ = type_ir,
				eff_  = eff_ir,
				span  = e.span,
			}
			return Synth_Result{var_id = inst, effects = eff, texpr = TExpr(t)}
		}
		var_id := fresh_value_var(store, e.span)
		name_str := base.intern_get(store.interner, e.name.name)
		similar := find_similar_names(name_str, env, store.interner)
		defer delete(similar)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_undefined_name(name_str, similar[:], e.span),
		)
		eff := fresh_effect_row(store, e.span)
		t := new(TExpr_Name)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Name {
			name  = e.name,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
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
		resolved_var, found := env_lookup(env, e.type_name.name)
		if !found {
			if var, ok := store.bindings[e.type_name.name]; ok {
				resolved_var = var
				found = true
			}
		}
		if !found {
			type_str := base.intern_get(store.interner, e.type_name.name)
			diagnostics.collector_add_diag(
				store.collector,
				diagnostics.diag_undefined_type(type_str, {"newtype"}, e.span),
			)
		} else {
			// For a newtype wrapping a HEAP type (record/tag/list), link the
			// construct's type var to the nominal type. Without this the var
			// stays free and lower_type defaults to .I64, contradicting the
			// i32 heap pointer the construct produces (invalid WASM on access).
			// Scalar newtypes (e.g. `@UserId : U64`) are left transparent so
			// arithmetic like `uid + 1` still unifies — and their .I64 default
			// already matches the inner scalar's representation.
			nt_res := store.vars[int(resolve_var(store, resolved_var))]
			if nt_inf, ok := nt_res.link.(Inferred_Type); ok {
				if nt, is_nt := nt_inf.(Inferred_Newtype); is_nt {
					if lower_type(store, nt.inner_id).is_heap {
						unify(store, type_var, instantiate(store, resolved_var))
					}
				}
			}
		}
		t := new(TExpr_Nominal_Construct)
		t^ = TExpr_Nominal_Construct {
			type_name     = e.type_name,
			variant       = e.variant,
			payload       = payload,
			resolved_type = type_var,
			span          = e.span,
		}
		return Synth_Result{var_id = type_var, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Record:
		return typecheck_record(e, env, store)

	case ^CExpr_Tuple:
		return typecheck_tuple(e, env, store)

	case ^CExpr_Field_Index:
		return typecheck_field_index(e, env, store)
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
			t_name^ = TExpr_Name {
				name  = target.name,
				type_ = type_ir,
				eff_  = eff_ir,
				span  = target.span,
			}
			target_t = TExpr(t_name)
		case ^CExpr_Int,
		     ^CExpr_Float,
		     ^CExpr_String,
		     ^CExpr_Bool,
		     ^CExpr_Char,
		     ^CExpr_Tag,
		     ^CExpr_Nominal_Construct,
		     ^CExpr_Record,
		     ^CExpr_List,
		     ^CExpr_Call,
		     ^CExpr_Method_Call,
		     ^CExpr_Lambda,
		     ^CExpr_Block,
		     ^CExpr_If,
		     ^CExpr_Match,
		     ^CExpr_BinOp,
		     ^CExpr_PrefixOp,
		     ^CExpr_Field_Access,
		     ^CExpr_Record_Update,
		     ^CExpr_Return,
		     ^CExpr_Crash,
		     ^CExpr_Todo,
		     ^CExpr_Interpolated_String,
		     ^CExpr_Handle,
		     ^CExpr_Perform,
		     ^CExpr_Par,
		     ^CExpr_For:
			target_t = typecheck_synth(e.target, env, store).texpr
		}
		t := new(TExpr_Assign)
		type_ir, eff_ir := type_eff_pair(store, result.var_id, result.effects)
		t^ = TExpr_Assign {
			target = target_t,
			value  = result.texpr,
			type_  = type_ir,
			eff_   = eff_ir,
			span   = e.span,
		}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Return:
		result := typecheck_synth(e.value, env, store)
		t := new(TExpr_Return)
		type_ir, eff_ir := type_eff_pair(store, result.var_id, result.effects)
		t^ = TExpr_Return {
			value = result.texpr,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = result.var_id, effects = result.effects, texpr = TExpr(t)}

	case ^CExpr_Crash:
		var_id, eff := fresh_with_effects(store, e.span)
		msg_result := typecheck_synth(e.message, env, store)
		t := new(TExpr_Crash)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Crash {
			message = msg_result.texpr,
			type_   = type_ir,
			eff_    = eff_ir,
			span    = e.span,
		}
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
				clit^ = TExpr_String_Literal {
					value = p.value,
					type_ = type_ir,
					eff_  = eff_ir,
					span  = p.span,
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
					switch nf in inf {
					case Inferred_Primitive:
						type_name = nf.primitive_name
					case Inferred_Constructor:
						type_name = nf.primitive_name
					case Inferred_Newtype:
						type_name = nf.primitive_name
					case Inferred_Function,
					     Inferred_Record_Row,
					     Inferred_Tag_Union_Row,
					     Inferred_Effect_Row,
					     Inferred_Handle,
					     Inferred_Tuple:
					}
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
							diagnostics.collector_add_diag(
								store.collector,
								diagnostics.diag_display_not_implemented(type_str, e.span),
							)
							expr_part.needs_to_str = false
							expr_part.display_impl = base.Canonical_Name{}
						}
					} else {
						type_str := base.intern_get(store.interner, type_name)
						diagnostics.collector_add_diag(
							store.collector,
							diagnostics.diag_display_not_implemented(type_str, e.span),
						)
						expr_part.needs_to_str = false
						expr_part.display_impl = base.Canonical_Name{}
					}
				} else {
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_display_not_implemented("unknown type", e.span),
					)
					expr_part.needs_to_str = false
					expr_part.display_impl = base.Canonical_Name{}
				}

				append(&parts_t, TExpr_String_Part(expr_part))
			case CPattern:
			}
		}
		t := new(TExpr_Interpolated_String)
		type_ir, eff_ir := type_eff_pair(store, str_var, eff)
		t^ = TExpr_Interpolated_String {
			parts = parts_t,
			type_ = type_ir,
			eff_  = eff_ir,
			span  = e.span,
		}
		return Synth_Result{var_id = str_var, effects = eff, texpr = TExpr(t)}

	case ^CExpr_Method_Call:
		return typecheck_method_call(e, env, store)

	case ^CExpr_Handle:
		for eff in e.effects {
			append(&env.handled_effects, eff.name)
		}
		body_result := typecheck_synth(e.body, env, store)
		for _ in e.effects {
			_ = pop(&env.handled_effects)
		}

		arms_t := make([dynamic]THandler_Arm, len(e.arms))

		for arm, arm_idx in e.arms {
			arm_env: Type_Env
			arm_env.bindings = make(map[base.Intern_ID]base.Type_Var_ID, len(arm.params) + 4)
			arm_env.parent = env
			arm_env.handled_effects = make([dynamic]base.Intern_ID, 0, 8)
			arm_env.current_module = env.current_module

			arm_body_result: Synth_Result

			found_sig: Effect_Op_Sig
			sig_found := false
			for eff in e.effects {
				// Effect decls are keyed by the suffix-less name; handle
				// expressions may write `handle Ask!` or `handle Ask` (and
				// `handle Console`). Normalize for lookup.
				key := canonical_effect_name(store, eff.name)
				if op_sigs, has_sigs := store.effect_ops[key]; has_sigs {
					for sig in op_sigs {
						if sig.name == arm.op {
							found_sig = sig
							sig_found = true
							break
						}
					}
				}
				if sig_found do break
			}

			if sig_found {
				sig := found_sig
				for i in 0 ..< len(arm.params) {
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
					diagnostics.collector_add_diag(
						store.collector,
						diagnostics.diag_internal(
							fmt.tprintf(
								"handler arm `{}` has {} parameters, expected {}",
								base.intern_get(store.interner, arm.op),
								actual_param_count,
								expected_param_count,
							),
							arm.span,
						),
					)
				}
			} else {
				effect_str := "unknown"
				for eff, ei in e.effects {
					if ei == 0 {
						effect_str = base.intern_get(store.interner, eff.name)
					} else {
						effect_str = fmt.tprintf(
							"{}, {}",
							effect_str,
							base.intern_get(store.interner, eff.name),
						)
					}
				}
				op_str := base.intern_get(store.interner, arm.op)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_internal(
						fmt.tprintf(
							"operation `{}` not found in effects `{}`",
							op_str,
							effect_str,
						),
						arm.span,
					),
				)
				for p in arm.params {
					check_shadow(&arm_env, p, store, arm.span)
					arm_env.bindings[p] = fresh_value_var(store, arm.span)
				}
				arm_body_result = typecheck_synth(arm.body, &arm_env, store)
				unify(store, arm_body_result.effects, body_result.effects)
			}

			arms_t[arm_idx] = THandler_Arm {
				op     = arm.op,
				params = arm.params,
				body   = arm_body_result.texpr,
				span   = arm.span,
			}

			delete(arm_env.bindings)
			delete(arm_env.handled_effects)
		}

		result_effects := body_result.effects
		for eff in e.effects {
			result_effects = subtract_effect_from_row(store, result_effects, eff.name, e.span)
		}
		t := new(TExpr_Handle)
		type_ir, eff_ir := type_eff_pair(store, body_result.var_id, result_effects)
		t^ = TExpr_Handle {
			effects = e.effects,
			body    = body_result.texpr,
			arms    = arms_t,
			type_   = type_ir,
			eff_    = eff_ir,
			span    = e.span,
		}
		return Synth_Result {
			var_id = body_result.var_id,
			effects = result_effects,
			texpr = TExpr(t),
		}

	case ^CExpr_Perform:
		var_id, effects := fresh_with_effects(store, e.span)
		args_t := make([dynamic]TExpr, len(e.args))
		effect_key := canonical_effect_name(store, e.effect.name)
		op_sigs, has_sigs := store.effect_ops[effect_key]
		found_sig: Effect_Op_Sig
		sig_found := false
		if has_sigs {
			for sig in op_sigs {
				if sig.name == e.op {
					found_sig = sig
					sig_found = true
					break
				}
			}
		}
		if sig_found {
			if len(e.args) != len(found_sig.param_types) {
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_arity_mismatch(
						len(found_sig.param_types),
						len(e.args),
						e.span,
						e.span,
					),
				)
			}
			for arg, i in e.args {
				arg_result := typecheck_synth(arg, env, store)
				unify(store, effects, arg_result.effects)
				if i < len(found_sig.param_types) {
					unify(store, arg_result.var_id, found_sig.param_types[i])
				}
				args_t[i] = arg_result.texpr
			}
			inst_return := instantiate(store, found_sig.return_type)
			unify(store, var_id, inst_return)
		} else {
			for arg, i in e.args {
				arg_result := typecheck_synth(arg, env, store)
				unify(store, effects, arg_result.effects)
				args_t[i] = arg_result.texpr
			}
		}
		t := new(TExpr_Perform)
		type_ir, eff_ir := type_eff_pair(store, var_id, effects)
		t^ = TExpr_Perform {
			effect = e.effect,
			op     = e.op,
			args   = args_t,
			type_  = type_ir,
			eff_   = eff_ir,
			span   = e.span,
		}
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
			t^ = TExpr_Par {
				for_var  = e.for_var,
				for_iter = iter_result.texpr,
				for_body = body_result.texpr,
				type_    = type_ir,
				eff_     = eff_ir,
				span     = e.span,
			}
			return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
		}

		// Named par { name: expr, ... } — infer heterogeneous record type
		if len(e.names) > 0 {
			exprs := make([dynamic]TExpr, 0, len(e.expressions))
			field_entries := make([dynamic]Type_Field_Entry, 0, len(e.names))
			for idx in 0 ..< len(e.expressions) {
				result := typecheck_synth(e.expressions[idx], env, store)
				unify(store, eff, result.effects)
				append(&exprs, result.texpr)
				append(&field_entries, Type_Field_Entry{name = e.names[idx], var = result.var_id})
			}

			// Build record type: { name: T1, name2: T2, ... }
			record_rest := fresh_record_row(store, e.span)
			record_var_id := fresh_value_var(store, e.span)
			link_var(
				store,
				record_var_id,
				Inferred_Record_Row {
					record_fields = field_entries[:],
					record_rest = record_rest,
					closed = false,
				},
			)

			t := new(TExpr_Par)
			type_ir, eff_ir := type_eff_pair(store, record_var_id, eff)
			t^ = TExpr_Par {
				names       = e.names,
				expressions = exprs,
				type_       = type_ir,
				eff_        = eff_ir,
				span        = e.span,
			}
			return Synth_Result{var_id = record_var_id, effects = eff, texpr = TExpr(t)}
		}

		// Unnamed par { e1, e2 } — homogeneous (legacy, should error at parse)
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
		t^ = TExpr_Par {
			expressions = exprs,
			type_       = type_ir,
			eff_        = eff_ir,
			span        = e.span,
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
		tfor^ = TExpr_For {
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
	t^ = TExpr_Int {
		type_ = type_ir,
		eff_  = eff_ir,
		span  = base.Source_Span_ZERO,
	}
	return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
}

mark_effect_type_params_in_ctype :: proc(
	type_params: [dynamic]frontend.Type_Param,
	effects_type: ^CType,
) {
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

// expand_named_tag_union resolves a named type reference whose definition is a tag
// union into a fresh tag-union row, substituting the supplied type arguments for the
// definition's type parameters. This lets an annotation such as `xs: List(I64)`,
// `c: Color`, or `r: Result(I64, Str)` unify with the open tag-union rows that
// construction (`Cons`/`Nil`, `Ok`/`Err`) and pattern matching produce.
//
// Returns (var, true) when `name` denotes a tag-union type; otherwise (_, false), so
// scalar newtypes (`@UserId : U64`), opaque constructors, and abstract types keep
// their bare `Inferred_Constructor` representation and remain nominal.
expand_named_tag_union :: proc(
	store: ^Type_Store,
	env: ^Type_Env,
	name: base.Intern_ID,
	args: []base.Type_Var_ID,
	span: base.Source_Span,
) -> (
	base.Type_Var_ID,
	bool,
) {
	// Prelude tag-union builtins (`List`, `Result`, `Ordering`) are registered as bare
	// constructors with no decl body; synthesize their rows from PRELUDE_TAG_UNIONS.
	name_str := base.intern_get(store.interner, name)
	for def in PRELUDE_TAG_UNIONS {
		if def.name == name_str && def.arity == len(args) {
			tag_entries := store_alloc(store, Type_Tag_Entry, len(def.tags))
			for tag, ti in def.tags {
				payload: []base.Type_Var_ID = nil
				if len(tag.payload) > 0 {
					payload = store_alloc(store, base.Type_Var_ID, len(tag.payload))
					for slot, si in tag.payload {
						if slot >= 0 && slot < len(args) {
							payload[si] = args[slot]
						} else {
							// -1 (or out of range): a fresh open var, e.g. List's
							// recursive `Cons` tail, kept open to avoid a cyclic type.
							payload[si] = fresh_value_var(store, span)
						}
					}
				}
				tag_entries[ti] = Type_Tag_Entry {
					name    = base.intern(store.interner, tag.name),
					payload = payload,
				}
			}
			vid := fresh_value_var(store, span)
			link_var(
				store,
				vid,
				Inferred_Tag_Union_Row {
					tag_entries = tag_entries,
					tag_rest = fresh_tag_row(store, span),
				},
			)
			return vid, true
		}
	}

	// User `@Name(params) : [tags]` — expand only when the inner type is a tag union.
	info, ok := store.newtype_decls[name]
	if !ok {
		return 0, false
	}
	inner_resolved := store.vars[int(resolve_var(store, info.inner_type))]
	inner_inf, is_inf := inner_resolved.link.(Inferred_Type)
	if !is_inf {
		return 0, false
	}
	if _, is_tu := inner_inf.(Inferred_Tag_Union_Row); !is_tu {
		return 0, false
	}

	// Substitute the declared type parameters with the supplied arguments, then make a
	// fresh copy of the inner row.
	subst := make(map[base.Type_Var_ID]base.Type_Var_ID, 8)
	defer delete(subst)
	if nt_var, found := env_lookup(env, name); found {
		nt_resolved := store.vars[int(resolve_var(store, nt_var))]
		if nt_inf, nt_is := nt_resolved.link.(Inferred_Type); nt_is {
			if nt, nt_ok := nt_inf.(Inferred_Newtype); nt_ok {
				n := min(len(nt.param_ids), len(args))
				for i in 0 ..< n {
					subst[resolve_var(store, nt.param_ids[i])] = args[i]
				}
			}
		}
	}
	return instantiate_rec(store, info.inner_type, &subst), true
}

convert_type_to_var_val :: proc(
	t: CType,
	store: ^Type_Store,
	env: ^Type_Env,
	closed: bool = false,
) -> base.Type_Var_ID {
	switch ty in t {
	case ^CType_Primitive:
		// A bare name may denote a user tag-union type (`Color`, `NetErr`) or a nominal
		// record (`Pt`); resolve it. Real primitives (`I64`, `Str`), scalar newtypes,
		// and opaque types fall through.
		if expanded, ok := expand_named_tag_union(store, env, ty.name, nil, ty.span); ok {
			return expanded
		}
		return make_primitive_type(store, ty.name, ty.span)

	case ^CType_Variable:
		if expanded, ok := expand_named_tag_union(store, env, ty.name, nil, ty.span); ok {
			return expanded
		}
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
		for i in 0 ..< len(ft.params) {
			param_ids[i] = convert_type_to_var_val(ft.params[i], store, env, closed = true)
		}
		return_id := convert_type_to_var_val(ft.return_, store, env, closed = true)
		effect_id := fresh_effect_row(store, ft.span)
		if ft.effects != nil {
			effect_id = convert_type_to_var(ft.effects, store, env)
		}
		vid := fresh_value_var(store, ft.span)
		link_var(
			store,
			vid,
			Inferred_Function{param_ids = param_ids, return_id = return_id, effect_id = effect_id},
		)
		return vid

	case ^CType_Applied:
		arg_ids := store_alloc(store, base.Type_Var_ID, len(ty.args))
		for &a, i in ty.args {
			arg_ids[i] = convert_type_to_var_val(a, store, env)
		}
		handle_name := base.intern(store.interner, "Handle")
		if ty.name == handle_name && len(ty.args) == 2 {
			vid := fresh_value_var(store, ty.span)
			link_var(store, vid, Inferred_Handle{inner_id = arg_ids[0], effect_id = arg_ids[1]})
			return vid
		}
		// A named tag-union type (`List(a)`, user `@Color : [..]`, `Result(t,e)`)
		// expands to its underlying tag-union row so that an annotation unifies with
		// the rows produced by construction and pattern matching. Scalar newtypes and
		// opaque constructors keep their bare representation.
		if expanded, ok := expand_named_tag_union(store, env, ty.name, arg_ids, ty.span); ok {
			return expanded
		}
		vid := fresh_value_var(store, ty.span)
		link_var(store, vid, Inferred_Constructor{primitive_name = ty.name, arity = len(ty.args)})
		return vid

	case ^CType_Record:
		rt := ty
		record_fields := store_alloc(store, Type_Field_Entry, len(rt.fields))
		for i in 0 ..< len(rt.fields) {
			record_fields[i] = Type_Field_Entry {
				name = rt.fields[i].name,
				var  = convert_type_to_var_val(rt.fields[i].type, store, env, closed),
			}
		}
		record_rest := fresh_record_row(store, rt.span)
		vid := fresh_value_var(store, rt.span)
		link_var(
			store,
			vid,
			Inferred_Record_Row {
				record_fields = record_fields,
				record_rest = record_rest,
				closed = closed,
			},
		)
		return vid
	case ^CType_Tuple:
		element_ids := store_alloc(store, base.Type_Var_ID, len(ty.elements))
		for i in 0 ..< len(ty.elements) {
			element_ids[i] = convert_type_to_var_val(ty.elements[i], store, env, closed = true)
		}
		vid := fresh_value_var(store, ty.span)
		link_var(
			store,
			vid,
			Inferred_Tuple {
				element_types = element_ids,
				element_count = len(ty.elements),
				closed = true,
			},
		)
		return vid

	case ^CType_Tag_Union:
		tt := ty
		tag_entries := store_alloc(store, Type_Tag_Entry, len(tt.tags))
		for i in 0 ..< len(tt.tags) {
			tg := tt.tags[i]
			payload := store_alloc(store, base.Type_Var_ID, len(tg.payload))
			for j in 0 ..< len(tg.payload) {
				payload[j] = convert_type_to_var_val(tg.payload[j], store, env)
			}
			tag_entries[i] = Type_Tag_Entry {
				name    = tg.name,
				payload = payload,
			}
		}
		tag_rest := fresh_tag_row(store, tt.span)
		vid := fresh_value_var(store, tt.span)
		link_var(
			store,
			vid,
			Inferred_Tag_Union_Row{tag_entries = tag_entries, tag_rest = tag_rest},
		)
		return vid

	case ^CType_Effect_Row:
		ert := ty
		if len(ert.effects) == 0 {
			return fresh_effect_row(store, ert.span)
		}
		effect_entries := store_alloc(store, Effect_Row_Entry, len(ert.effects))
		for i in 0 ..< len(ert.effects) {
			ce := ert.effects[i]
			type_args := store_alloc(store, base.Type_Var_ID, len(ce.type_args))
			for j in 0 ..< len(ce.type_args) {
				type_args[j] = convert_type_to_var(&ce.type_args[j], store, env)
			}
			effect_entries[i] = Effect_Row_Entry {
				name      = ce.name,
				type_args = type_args,
			}
		}
		rest_id := fresh_effect_row(store, ert.span)
		vid := fresh_effect_row(store, ert.span)
		link_var(store, vid, Inferred_Effect_Row{effects = effect_entries, rest_id = rest_id})
		return vid
	}
	return fresh_value_var(store, base.Source_Span_ZERO)
}

instantiate :: proc(store: ^Type_Store, var_id: base.Type_Var_ID) -> base.Type_Var_ID {
	subst := make(map[base.Type_Var_ID]base.Type_Var_ID, 8)
	defer delete(subst)
	return instantiate_rec(store, var_id, &subst)
}

instantiate_rec :: proc(
	store: ^Type_Store,
	var_id: base.Type_Var_ID,
	subst: ^map[base.Type_Var_ID]base.Type_Var_ID,
) -> base.Type_Var_ID {
	resolved := resolve_var(store, var_id)

	// Universal memo: a var already being instantiated returns its representative.
	// For structural types this ties the knot on cyclic (equirecursive) types — an
	// annotated recursive list unifies its `Cons` tail with itself, so without this
	// memo instantiate_rec recursed forever copying the cycle.
	if existing, ok := subst[resolved]; ok {
		return existing
	}
	v := store.vars[int(resolved)]

	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked {
		if is_generic(store, resolved) {
			new_id := fresh_var(store, v.kind, v.name, v.span)
			subst[resolved] = new_id
			return new_id
		}
		return resolved
	}

	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return resolved
	}

	// Primitives and constructors are atomic and shared directly (no copy, no knot).
	#partial switch f in inf {
	case Inferred_Primitive, Inferred_Constructor:
		return resolved
	}

	// Structural type: allocate the fresh representative and memoize it BEFORE
	// recursing into children so cyclic references resolve back to `vid`.
	vid := fresh_var(store, v.kind, v.name, v.span)
	subst[resolved] = vid

	#partial switch f in inf {
	case Inferred_Newtype:
		param_ids := store_alloc(store, base.Type_Var_ID, len(f.param_ids))
		for i in 0 ..< len(f.param_ids) {
			param_ids[i] = instantiate_rec(store, f.param_ids[i], subst)
		}
		inner_id := instantiate_rec(store, f.inner_id, subst)
		link_var(
			store,
			vid,
			Inferred_Newtype {
				primitive_name = f.primitive_name,
				arity = f.arity,
				param_ids = param_ids,
				inner_id = inner_id,
			},
		)

	case Inferred_Function:
		param_ids := store_alloc(store, base.Type_Var_ID, len(f.param_ids))
		for i in 0 ..< len(f.param_ids) {
			param_ids[i] = instantiate_rec(store, f.param_ids[i], subst)
		}
		return_id := instantiate_rec(store, f.return_id, subst)
		effect_id := instantiate_rec(store, f.effect_id, subst)
		link_var(
			store,
			vid,
			Inferred_Function{param_ids = param_ids, return_id = return_id, effect_id = effect_id},
		)

	case Inferred_Effect_Row:
		effect_entries := store_alloc(store, Effect_Row_Entry, len(f.effects))
		for i in 0 ..< len(f.effects) {
			entry := f.effects[i]
			type_args := store_alloc(store, base.Type_Var_ID, len(entry.type_args))
			for j in 0 ..< len(entry.type_args) {
				type_args[j] = instantiate_rec(store, entry.type_args[j], subst)
			}
			effect_entries[i] = Effect_Row_Entry {
				name      = entry.name,
				type_args = type_args,
			}
		}
		rest_id := instantiate_rec(store, f.rest_id, subst)
		link_var(store, vid, Inferred_Effect_Row{effects = effect_entries, rest_id = rest_id})

	case Inferred_Record_Row:
		record_fields := store_alloc(store, Type_Field_Entry, len(f.record_fields))
		for i in 0 ..< len(f.record_fields) {
			rf := f.record_fields[i]
			record_fields[i] = Type_Field_Entry {
				name = rf.name,
				var  = instantiate_rec(store, rf.var, subst),
			}
		}
		record_rest := instantiate_rec(store, f.record_rest, subst)
		link_var(
			store,
			vid,
			Inferred_Record_Row {
				record_fields = record_fields,
				record_rest = record_rest,
				closed = f.closed,
			},
		)

	case Inferred_Tag_Union_Row:
		tag_entries := store_alloc(store, Type_Tag_Entry, len(f.tag_entries))
		for i in 0 ..< len(f.tag_entries) {
			te := f.tag_entries[i]
			payload := store_alloc(store, base.Type_Var_ID, len(te.payload))
			for j in 0 ..< len(te.payload) {
				payload[j] = instantiate_rec(store, te.payload[j], subst)
			}
			tag_entries[i] = Type_Tag_Entry {
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := instantiate_rec(store, f.tag_rest, subst)
		link_var(
			store,
			vid,
			Inferred_Tag_Union_Row{tag_entries = tag_entries, tag_rest = tag_rest},
		)

	case Inferred_Handle:
		inner_id := instantiate_rec(store, f.inner_id, subst)
		effect_id := instantiate_rec(store, f.effect_id, subst)
		link_var(store, vid, Inferred_Handle{inner_id = inner_id, effect_id = effect_id})

	case Inferred_Tuple:
		element_types := store_alloc(store, base.Type_Var_ID, len(f.element_types))
		for i in 0 ..< len(f.element_types) {
			element_types[i] = instantiate_rec(store, f.element_types[i], subst)
		}
		link_var(
			store,
			vid,
			Inferred_Tuple {
				element_types = element_types,
				element_count = f.element_count,
				closed = f.closed,
			},
		)
	}

	return vid
}

deep_clone_type :: proc(
	store: ^Type_Store,
	id: base.Type_Var_ID,
	span: base.Source_Span,
	subst: ^map[base.Type_Var_ID]base.Type_Var_ID,
) -> base.Type_Var_ID {
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

	switch f in inf {
	case Inferred_Primitive, Inferred_Constructor:
		return resolved

	case Inferred_Newtype:
		param_ids := store_alloc(store, base.Type_Var_ID, len(f.param_ids))
		for i in 0 ..< len(f.param_ids) {
			param_ids[i] = deep_clone_type(store, f.param_ids[i], span, subst)
		}
		inner_id := deep_clone_type(store, f.inner_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(
			store,
			fresh,
			Inferred_Newtype {
				primitive_name = f.primitive_name,
				arity = f.arity,
				param_ids = param_ids,
				inner_id = inner_id,
			},
		)
		subst[resolved] = fresh
		return fresh

	case Inferred_Function:
		param_ids := store_alloc(store, base.Type_Var_ID, len(f.param_ids))
		for i in 0 ..< len(f.param_ids) {
			param_ids[i] = deep_clone_type(store, f.param_ids[i], span, subst)
		}
		return_id := deep_clone_type(store, f.return_id, span, subst)
		effect_id := deep_clone_type(store, f.effect_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(
			store,
			fresh,
			Inferred_Function{param_ids = param_ids, return_id = return_id, effect_id = effect_id},
		)
		subst[resolved] = fresh
		return fresh

	case Inferred_Effect_Row:
		effect_entries := store_alloc(store, Effect_Row_Entry, len(f.effects))
		for i in 0 ..< len(f.effects) {
			entry := f.effects[i]
			type_args := store_alloc(store, base.Type_Var_ID, len(entry.type_args))
			for j in 0 ..< len(entry.type_args) {
				type_args[j] = deep_clone_type(store, entry.type_args[j], span, subst)
			}
			effect_entries[i] = Effect_Row_Entry {
				name      = entry.name,
				type_args = type_args,
			}
		}
		rest_id := deep_clone_type(store, f.rest_id, span, subst)
		fresh := fresh_effect_row(store, span)
		link_var(store, fresh, Inferred_Effect_Row{effects = effect_entries, rest_id = rest_id})
		subst[resolved] = fresh
		return fresh

	case Inferred_Record_Row:
		record_fields := store_alloc(store, Type_Field_Entry, len(f.record_fields))
		for i in 0 ..< len(f.record_fields) {
			rf := f.record_fields[i]
			record_fields[i] = Type_Field_Entry {
				name = rf.name,
				var  = deep_clone_type(store, rf.var, span, subst),
			}
		}
		record_rest := deep_clone_type(store, f.record_rest, span, subst)
		fresh := fresh_record_row(store, span)
		link_var(
			store,
			fresh,
			Inferred_Record_Row {
				record_fields = record_fields,
				record_rest = record_rest,
				closed = f.closed,
			},
		)
		subst[resolved] = fresh
		return fresh

	case Inferred_Tag_Union_Row:
		tag_entries := store_alloc(store, Type_Tag_Entry, len(f.tag_entries))
		for i in 0 ..< len(f.tag_entries) {
			te := f.tag_entries[i]
			payload := store_alloc(store, base.Type_Var_ID, len(te.payload))
			for j in 0 ..< len(te.payload) {
				payload[j] = deep_clone_type(store, te.payload[j], span, subst)
			}
			tag_entries[i] = Type_Tag_Entry {
				name    = te.name,
				payload = payload,
			}
		}
		tag_rest := deep_clone_type(store, f.tag_rest, span, subst)
		fresh := fresh_tag_row(store, span)
		link_var(
			store,
			fresh,
			Inferred_Tag_Union_Row{tag_entries = tag_entries, tag_rest = tag_rest},
		)
		subst[resolved] = fresh
		return fresh

	case Inferred_Tuple:
		element_types := store_alloc(store, base.Type_Var_ID, len(f.element_types))
		for i in 0 ..< len(f.element_types) {
			element_types[i] = deep_clone_type(store, f.element_types[i], span, subst)
		}
		fresh := fresh_value_var(store, span)
		link_var(
			store,
			fresh,
			Inferred_Tuple {
				element_types = element_types,
				element_count = f.element_count,
				closed = f.closed,
			},
		)
		subst[resolved] = fresh
		return fresh

	case Inferred_Handle:
		inner_id := deep_clone_type(store, f.inner_id, span, subst)
		effect_id := deep_clone_type(store, f.effect_id, span, subst)
		fresh := fresh_value_var(store, span)
		link_var(store, fresh, Inferred_Handle{inner_id = inner_id, effect_id = effect_id})
		subst[resolved] = fresh
		return fresh
	}

	return resolved
}

subtract_effect_from_row :: proc(
	store: ^Type_Store,
	row: base.Type_Var_ID,
	effect: base.Intern_ID,
	span: base.Source_Span,
) -> base.Type_Var_ID {
	rid := resolve_var(store, row)
	rv := store.vars[int(rid)]

	inf, is_inf := rv.link.(Inferred_Type)
	inf_effect, inf_is_effect := inf.(Inferred_Effect_Row)
	if is_inf && inf_is_effect {
		found := false
		for entry in inf_effect.effects {
			if entry.name == effect {
				found = true
				break
			}
		}
		if found {
			if len(inf_effect.effects) == 1 {
				return inf_effect.rest_id
			}
			new_entries := store_alloc(store, Effect_Row_Entry, len(inf_effect.effects) - 1)
			j := 0
			for entry in inf_effect.effects {
				if entry.name != effect {
					new_entries[j] = entry
					j += 1
				}
			}
			new_row := fresh_effect_row(store, span)
			link_var(
				store,
				new_row,
				Inferred_Effect_Row{effects = new_entries, rest_id = inf_effect.rest_id},
			)
			return new_row
		}
		return rid
	}

	_, is_unlinked := rv.link.(Type_Unlinked)
	if is_unlinked {
		handled_rest := fresh_effect_row(store, span)
		effect_entries := store_alloc(store, Effect_Row_Entry, 1)
		effect_entries[0] = Effect_Row_Entry {
			name      = effect,
			type_args = {},
		}
		handled_row := fresh_effect_row(store, span)
		link_var(
			store,
			handled_row,
			Inferred_Effect_Row{effects = effect_entries, rest_id = handled_rest},
		)
		unify(store, rid, handled_row)
		return handled_rest
	}

	return rid
}

effect_row_nonempty :: proc(store: ^Type_Store, effect_var: base.Type_Var_ID) -> bool {
	resolved := resolve_var(store, effect_var)
	v := store.vars[int(resolved)]

	inf, is_inf := v.link.(Inferred_Type)
	inf_effect, inf_is_effect := inf.(Inferred_Effect_Row)
	if !is_inf || !inf_is_effect {
		return false
	}

	if len(inf_effect.effects) > 0 {
		return true
	}

	rest_resolved := resolve_var(store, inf_effect.rest_id)
	rest_v := store.vars[int(rest_resolved)]
	_, rest_unlinked := rest_v.link.(Type_Unlinked)
	if rest_unlinked && !is_generic(store, rest_resolved) {
		return true
	}

	rest_inf, rest_is_inf := rest_v.link.(Inferred_Type)
	rest_effect, rest_is_effect := rest_inf.(Inferred_Effect_Row)
	if rest_is_inf && rest_is_effect {
		return effect_row_nonempty(store, inf_effect.rest_id)
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

is_prelude_effect_by_entry :: proc(
	entry_name: base.Intern_ID,
	interner: ^base.Intern_Table,
) -> bool {
	// Effect row entries store names with '!' suffix (e.g. "Console!"),
	// but is_prelude_effect checks against bare names (e.g. "Console").
	if is_prelude_effect(entry_name, interner) {
		return true
	}
	name_str := base.intern_get(interner, entry_name)
	if strings.has_suffix(name_str, "!") {
		bare_name := name_str[:len(name_str) - 1]
		bare_id := base.intern(interner, bare_name)
		return is_prelude_effect(bare_id, interner)
	}
	return false
}

check_effect_safety :: proc(tfile: TFile, store: ^Type_Store) {
	main_name := base.intern(store.interner, "main!")

	for decl in tfile.decls {
		td, is_const := decl.(^TDecl_Const)
		if !is_const {
			continue
		}
		if td.name.name != main_name {
			continue
		}

		// Find main!'s type var from store bindings
		var_id, has_var := store.bindings[main_name]
		if !has_var {
			continue
		}

		resolved := resolve_var(store, var_id)
		v := store.vars[int(resolved)]
		inf, is_inf := v.link.(Inferred_Type)
		inf_fn, is_fn := inf.(Inferred_Function)
		if !is_inf || !is_fn {
			continue
		}

		// Check if effect row has non-prelude effects
		effect_var := inf_fn.effect_id
		rid := resolve_var(store, effect_var)
		rv := store.vars[int(rid)]
		it, is_inferred := rv.link.(Inferred_Type)
		it_effect, is_effect := it.(Inferred_Effect_Row)
		if !is_inferred || !is_effect {
			return
		}

		for entry in it_effect.effects {
			if !is_prelude_effect_by_entry(entry.name, store.interner) {
				effect_str := base.intern_get(store.interner, entry.name)
				effects_str := format_effect_row(store, effect_var)
				diagnostics.collector_add_diag(
					store.collector,
					diagnostics.diag_unhandled_effect_entry(effect_str, effects_str, td.span),
				)
			}
		}

		return // Found main!, done
	}
}

typecheck_newtype_construct :: proc(
	e: ^CExpr_Tag,
	env: ^Type_Env,
	store: ^Type_Store,
) -> Synth_Result {
	eff := fresh_effect_row(store, e.span)

	nt_info, ok := store.newtype_decls[e.name.name]
	if !ok {
		var_id := fresh_value_var(store, e.span)
		payload_t := make([dynamic]TExpr, 0)
		t := new(TExpr_Tag)
		type_ir, eff_ir := type_eff_pair(store, var_id, eff)
		t^ = TExpr_Tag {
			name    = e.name,
			payload = payload_t,
			type_   = type_ir,
			eff_    = eff_ir,
			span    = e.span,
		}
		return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
	}

	if !is_same_module(env, nt_info.module) {
		nt_str := base.intern_get(store.interner, e.name.name)
		diagnostics.collector_add_diag(
			store.collector,
			diagnostics.diag_newtype_opaque_violation(nt_str, "construct", e.span),
		)
	}

	nt_binding, has_binding := env_lookup(env, e.name.name)
	if !has_binding {
		nt_binding = store.bindings[e.name.name]
	}
	inst_binding := instantiate(store, nt_binding)

	nt_resolved := store.vars[int(resolve_var(store, inst_binding))]
	nt_inf, is_nt := nt_resolved.link.(Inferred_Type)
	nt_newtype, nt_is_newtype := nt_inf.(Inferred_Newtype)

	arg_var: base.Type_Var_ID
	arg_texpr: TExpr
	arg_typed := false
	if is_nt && nt_is_newtype && is_numeric_primitive(store, nt_newtype.inner_id) {
		is_int_lit := false
		is_float_lit := false
		#partial switch arg in e.payload[0] {
		case ^CExpr_Int:
			is_int_lit = true
		case ^CExpr_Float:
			is_float_lit = true
		}

		inner_resolved := store.vars[int(resolve_var(store, nt_newtype.inner_id))]
		if inner_inf, inner_ok := inner_resolved.link.(Inferred_Type); inner_ok {
			inner_prim, inner_is_prim := inner_inf.(Inferred_Primitive)
			if inner_is_prim {
				if is_int_lit || is_float_lit {
					arg_var = make_primitive_type(store, inner_prim.primitive_name, e.span)
					arg_typed = true
					arg_synth := typecheck_synth(e.payload[0], env, store)
					arg_texpr = arg_synth.texpr
				}
			}
		}
	}

	if !arg_typed {
		arg_result := typecheck_synth(e.payload[0], env, store)
		unify(store, eff, arg_result.effects)
		arg_var = arg_result.var_id
		arg_texpr = arg_result.texpr
	}

	if is_nt && nt_is_newtype {
		unify(store, arg_var, nt_newtype.inner_id)
	}

	payload_t := make([dynamic]TExpr, 1)
	payload_t[0] = arg_texpr
	t := new(TExpr_Tag)
	type_ir, eff_ir := type_eff_pair(store, inst_binding, eff)
	t^ = TExpr_Tag {
		name    = e.name,
		payload = payload_t,
		type_   = type_ir,
		eff_    = eff_ir,
		span    = e.span,
	}
	return Synth_Result{var_id = inst_binding, effects = eff, texpr = TExpr(t)}
}

newtype_owning_tag :: proc(
	store: ^Type_Store,
	tag_name: base.Intern_ID,
) -> (
	base.Intern_ID,
	bool,
) {
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


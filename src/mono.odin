package camp

import "core:fmt"

Mono_Env :: struct {
	store:           ^Type_Store,
	interner:        ^Intern_Table,
	specializations: map[string]Canonical_Name,
	worklist:        [dynamic]Mono_Item,
	output_decls:    [dynamic]TDecl,
}

Mono_Item :: struct {
	original:  Canonical_Name,
	type_args:  map[Intern_ID]Type_Var_ID,
	span:      Source_Span,
}

mono :: proc(tfile: TFile, store: ^Type_Store, interner: ^Intern_Table) -> TFile {
	env: Mono_Env
	env.store = store
	env.interner = interner
	env.specializations = make(map[string]Canonical_Name, 32)
	env.worklist = make([dynamic]Mono_Item, 0, 16)
	env.output_decls = make([dynamic]TDecl, 0, len(tfile.decls))

	for decl in tfile.decls {
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
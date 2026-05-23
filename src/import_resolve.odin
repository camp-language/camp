package camp

import "core:fmt"

Import_Scope :: struct {
	qualified:   map[Intern_ID]Canonical_Name,
	unqualified: map[Intern_ID]Canonical_Name,
	module_aliased: map[Intern_ID]Intern_ID,
}

import_scope_init :: proc(scope: ^Import_Scope) {
	scope.qualified = make(map[Intern_ID]Canonical_Name, 32)
	scope.unqualified = make(map[Intern_ID]Canonical_Name, 64)
	scope.module_aliased = make(map[Intern_ID]Intern_ID, 8)
}

import_scope_destroy :: proc(scope: ^Import_Scope) {
	delete(scope.qualified)
	delete(scope.unqualified)
	delete(scope.module_aliased)
}

resolve_imports :: proc(
	module_name: Intern_ID,
	cfile: ^CFile,
	export_tables: ^map[Intern_ID]Export_Table,
	project: ^Project_Discovery,
	interner: ^Intern_Table,
	collector: ^Diagnostic_Collector,
) -> Import_Scope {
	scope: Import_Scope
	import_scope_init(&scope)

	for decl in cfile.decls {
		#partial switch d in decl {
		case ^CDecl_Const:
			scope.unqualified[d.name.name] = Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^CDecl_Effect:
			scope.unqualified[d.name.name] = Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^CDecl_Trait:
			scope.unqualified[d.name.name] = Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^CDecl_Alias:
			scope.unqualified[d.name.name] = Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^CDecl_Newtype:
			scope.unqualified[d.name.name] = Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case:
		}
	}

	for imp in cfile.imports {
		resolve_single_import(imp, module_name, &scope, export_tables, project, interner, collector)
	}

	return scope
}

resolve_single_import :: proc(
	imp: Deferred_Import,
	current_module: Intern_ID,
	scope: ^Import_Scope,
	export_tables: ^map[Intern_ID]Export_Table,
	project: ^Project_Discovery,
	interner: ^Intern_Table,
	collector: ^Diagnostic_Collector,
) {
	mod_info, mod_found := project.modules[imp.module]
	if !mod_found {
		mod_str := intern_get(interner, imp.module)
		collector_add_diag(collector, diag_module_not_found(mod_str, imp.span))
		return
	}

	et, et_found := export_tables^[imp.module]
	if !et_found {
		return
	}

	qualifier := imp.module
	if imp.alias != NO_NAME && imp.alias != imp.module {
		qualifier = imp.alias
	}
	scope.module_aliased[qualifier] = imp.module

	for name_id, ei in et.exports {
		qualified_name := Canonical_Name{
			module = imp.module,
			name = name_id,
			is_local = false,
		}

		scope.qualified[name_id] = qualified_name
	}

	if len(imp.exposing) > 0 {
		for exposed_name in imp.exposing {
			ei, found := export_lookup(&et, exposed_name)
			if !found || !ei.is_pub {
				name_str := intern_get(interner, exposed_name)
				mod_str := intern_get(interner, imp.module)
				collector_add_diag(collector, diag_import_not_exported(name_str, mod_str, imp.span))
				continue
			}

			imported := Canonical_Name{
				module = imp.module,
				name = exposed_name,
				is_local = false,
			}

			if existing, ok := scope.unqualified[exposed_name]; ok {
				if existing.is_local {
					name_str := intern_get(interner, exposed_name)
					mod_str := intern_get(interner, imp.module)
					collector_add_diag(collector, diag_import_conflicts_binding(name_str, mod_str, imp.span))
					continue
				}

				existing_mod := intern_get(interner, existing.module)
				new_mod := intern_get(interner, imp.module)
				name_str := intern_get(interner, exposed_name)
				collector_add_diag(collector, diag_import_ambiguous(name_str, existing_mod, new_mod, imp.span))
				continue
			}

			scope.unqualified[exposed_name] = imported
		}
	}
}

resolve_name :: proc(name: Intern_ID, scope: ^Import_Scope, interner: ^Intern_Table) -> (Canonical_Name, bool) {
	if existing, ok := scope.unqualified[name]; ok {
		return existing, true
	}
	return Canonical_Name{}, false
}

resolve_qualified_access :: proc(
	qualifier: Intern_ID,
	field: Intern_ID,
	scope: ^Import_Scope,
	export_tables: ^map[Intern_ID]Export_Table,
	interner: ^Intern_Table,
	collector: ^Diagnostic_Collector,
	span: Source_Span,
) -> (Canonical_Name, bool) {
	actual_module, is_alias := scope.module_aliased[qualifier]
	if !is_alias {
		actual_module = qualifier
	}

	et, et_ok := export_tables^[actual_module]
	if !et_ok {
		return Canonical_Name{}, false
	}

	ei, ei_ok := export_lookup(&et, field)
	if !ei_ok || !ei.is_pub {
		field_str := intern_get(interner, field)
		mod_str := intern_get(interner, actual_module)
		collector_add_diag(collector, diag_import_not_exported(field_str, mod_str, span))
		return Canonical_Name{}, false
	}

	return Canonical_Name{
		module = actual_module,
		name = field,
		is_local = false,
	}, true
}

apply_import_resolution :: proc(cfile: ^CFile, scope: ^Import_Scope, export_tables: ^map[Intern_ID]Export_Table, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
	for &decl in cfile.decls {
		resolve_decl_names(decl, scope, export_tables, interner, collector)
	}
}

resolve_decl_names :: proc(decl: CDecl, scope: ^Import_Scope, export_tables: ^map[Intern_ID]Export_Table, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
	#partial switch d in decl {
	case ^CDecl_Const:
		resolve_expr_names(d.body, scope, export_tables, interner, collector)
	case ^CDecl_Test:
		resolve_expr_names(d.body, scope, export_tables, interner, collector)
	case ^CDecl_Expect:
		resolve_expr_names(d.condition, scope, export_tables, interner, collector)
	case:
	}
}

resolve_expr_names :: proc(expr: CExpr, scope: ^Import_Scope, export_tables: ^map[Intern_ID]Export_Table, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
	switch e in expr {
	case ^CExpr_Name:
		if e.name.module == NO_NAME {
			if resolved, ok := resolve_name(e.name.name, scope, interner); ok {
				e.name = resolved
			}
		}

	case ^CExpr_Field_Access:
		resolve_expr_names(e.record, scope, export_tables, interner, collector)
		#partial switch r in e.record {
		case ^CExpr_Name:
			if r.name.is_local && r.name.module == NO_NAME {
				if _, is_module := scope.module_aliased[r.name.name]; is_module {
					resolved, ok := resolve_qualified_access(r.name.name, e.field, scope, export_tables, interner, collector, e.span)
					if ok {
						r.name = resolved
					}
				}
			}
		case:
		}

	case ^CExpr_Call:
		resolve_expr_names(e.callee, scope, export_tables, interner, collector)
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^CExpr_Method_Call:
		resolve_expr_names(e.receiver, scope, export_tables, interner, collector)
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^CExpr_Lambda:
		resolve_expr_names(e.body, scope, export_tables, interner, collector)

	case ^CExpr_Block:
		for &stmt in e.statements {
			resolve_expr_names(stmt, scope, export_tables, interner, collector)
		}

	case ^CExpr_If:
		resolve_expr_names(e.condition, scope, export_tables, interner, collector)
		resolve_expr_names(e.then_branch, scope, export_tables, interner, collector)
		resolve_expr_names(e.else_branch, scope, export_tables, interner, collector)

	case ^CExpr_Match:
		resolve_expr_names(e.scrutinee, scope, export_tables, interner, collector)
		for &arm in e.arms {
			resolve_expr_names(arm.body, scope, export_tables, interner, collector)
		}

	case ^CExpr_BinOp:
		resolve_expr_names(e.left, scope, export_tables, interner, collector)
		resolve_expr_names(e.right, scope, export_tables, interner, collector)

	case ^CExpr_PrefixOp:
		resolve_expr_names(e.operand, scope, export_tables, interner, collector)

	case ^CExpr_Tag:
		if e.name.module == NO_NAME {
			if resolved, ok := resolve_name(e.name.name, scope, interner); ok {
				e.name = resolved
			}
		}
		for &p in e.payload {
			resolve_expr_names(p, scope, export_tables, interner, collector)
		}

	case ^CExpr_Record:
		for &f in e.fields {
			resolve_expr_names(f.value, scope, export_tables, interner, collector)
		}

	case ^CExpr_List:
		for &el in e.elements {
			resolve_expr_names(el, scope, export_tables, interner, collector)
		}

	case ^CExpr_Record_Update:
		resolve_expr_names(e.rest, scope, export_tables, interner, collector)
		for &u in e.updates {
			resolve_expr_names(u.value, scope, export_tables, interner, collector)
		}

	case ^CExpr_Assign:
		resolve_expr_names(e.target, scope, export_tables, interner, collector)
		resolve_expr_names(e.value, scope, export_tables, interner, collector)

	case ^CExpr_Return:
		resolve_expr_names(e.value, scope, export_tables, interner, collector)

	case ^CExpr_Crash:
		resolve_expr_names(e.message, scope, export_tables, interner, collector)

	case ^CExpr_Interpolated_String:
		for &part in e.parts {
			switch p in part {
			case ^CExpr_String_Literal:
			case CExpr:
				resolve_expr_names(p, scope, export_tables, interner, collector)
			}
		}

	case ^CExpr_Handle:
		if e.effect.module == NO_NAME {
			if resolved, ok := resolve_name(e.effect.name, scope, interner); ok {
				e.effect = resolved
			}
		}
		resolve_expr_names(e.body, scope, export_tables, interner, collector)
		for &arm in e.arms {
			resolve_expr_names(arm.body, scope, export_tables, interner, collector)
		}

	case ^CExpr_Int, ^CExpr_Float, ^CExpr_String, ^CExpr_Bool:

	case ^CExpr_Perform:
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^CExpr_Par:
		if e.for_var != 0 {
			resolve_expr_names(e.for_iter, scope, export_tables, interner, collector)
			resolve_expr_names(e.for_body, scope, export_tables, interner, collector)
		} else {
			for &expr in e.expressions {
				resolve_expr_names(expr, scope, export_tables, interner, collector)
			}
		}

	case ^CExpr_For:
		resolve_expr_names(e.iterable, scope, export_tables, interner, collector)
		resolve_expr_names(e.body, scope, export_tables, interner, collector)

	case:
	}
}

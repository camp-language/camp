package build

import "camp:base"
import "camp:semantics"
import "camp:diagnostics"
import "core:fmt"

Import_Scope :: struct {
	qualified:   map[base.Intern_ID]base.Canonical_Name,
	unqualified: map[base.Intern_ID]base.Canonical_Name,
	module_aliased: map[base.Intern_ID]base.Intern_ID,
}

import_scope_init :: proc(scope: ^Import_Scope) {
	scope.qualified = make(map[base.Intern_ID]base.Canonical_Name, 32)
	scope.unqualified = make(map[base.Intern_ID]base.Canonical_Name, 64)
	scope.module_aliased = make(map[base.Intern_ID]base.Intern_ID, 8)
}

import_scope_destroy :: proc(scope: ^Import_Scope) {
	delete(scope.qualified)
	delete(scope.unqualified)
	delete(scope.module_aliased)
}

resolve_imports :: proc(
	module_name: base.Intern_ID,
	cfile: ^semantics.CFile,
	export_tables: ^map[base.Intern_ID]Export_Table,
	project: ^Project_Discovery,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
) -> Import_Scope {
	scope: Import_Scope
	import_scope_init(&scope)

	for decl in cfile.decls {
		#partial switch d in decl {
		case ^semantics.CDecl_Const:
			scope.unqualified[d.name.name] = base.Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^semantics.CDecl_Effect:
			scope.unqualified[d.name.name] = base.Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^semantics.CDecl_Trait:
			scope.unqualified[d.name.name] = base.Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^semantics.CDecl_Alias:
			scope.unqualified[d.name.name] = base.Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^semantics.CDecl_Newtype:
			scope.unqualified[d.name.name] = base.Canonical_Name{
				module = module_name,
				name = d.name.name,
				is_local = true,
			}
		case ^semantics.CDecl_Import, ^semantics.CDecl_Test, ^semantics.CDecl_Expect:
		}
	}

	for imp in cfile.imports {
		resolve_single_import(imp, module_name, &scope, export_tables, project, interner, collector)
	}

	return scope
}

resolve_single_import :: proc(
	imp: base.Deferred_Import,
	current_module: base.Intern_ID,
	scope: ^Import_Scope,
	export_tables: ^map[base.Intern_ID]Export_Table,
	project: ^Project_Discovery,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
) {
	mod_info, mod_found := project.modules[imp.module]
	if !mod_found {
		mod_str := base.intern_get(interner, imp.module)
		diagnostics.collector_add_diag(collector, diagnostics.diag_module_not_found(mod_str, imp.span))
		return
	}

	et, et_found := export_tables^[imp.module]
	if !et_found {
		return
	}

	qualifier := imp.module
	if imp.alias != base.NO_NAME && imp.alias != imp.module {
		qualifier = imp.alias
	}
	scope.module_aliased[qualifier] = imp.module

	for name_id, ei in et.exports {
		qualified_name := base.Canonical_Name{
			module = imp.module,
			name = name_id,
			is_local = false,
		}

		scope.qualified[name_id] = qualified_name
	}

	if len(imp.names) > 0 {
		for exposed_name in imp.names {
			ei, found := export_lookup(&et, exposed_name)
			if !found || !ei.is_pub {
				name_str := base.intern_get(interner, exposed_name)
				mod_str := base.intern_get(interner, imp.module)
				diagnostics.collector_add_diag(collector, diagnostics.diag_import_not_exported(name_str, mod_str, imp.span))
				continue
			}

			imported := base.Canonical_Name{
				module = imp.module,
				name = exposed_name,
				is_local = false,
			}

			if existing, ok := scope.unqualified[exposed_name]; ok {
				if existing.is_local {
					name_str := base.intern_get(interner, exposed_name)
					mod_str := base.intern_get(interner, imp.module)
					diagnostics.collector_add_diag(collector, diagnostics.diag_import_conflicts_binding(name_str, mod_str, imp.span))
					continue
				}

				existing_mod := base.intern_get(interner, existing.module)
				new_mod := base.intern_get(interner, imp.module)
				name_str := base.intern_get(interner, exposed_name)
				diagnostics.collector_add_diag(collector, diagnostics.diag_import_ambiguous(name_str, existing_mod, new_mod, imp.span))
				continue
			}

			scope.unqualified[exposed_name] = imported
		}
	}
}

resolve_name :: proc(name: base.Intern_ID, scope: ^Import_Scope, interner: ^base.Intern_Table) -> (base.Canonical_Name, bool) {
	if existing, ok := scope.unqualified[name]; ok {
		return existing, true
	}
	return base.Canonical_Name{}, false
}

resolve_qualified_access :: proc(
	qualifier: base.Intern_ID,
	field: base.Intern_ID,
	scope: ^Import_Scope,
	export_tables: ^map[base.Intern_ID]Export_Table,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
	span: base.Source_Span,
) -> (base.Canonical_Name, bool) {
	actual_module, is_alias := scope.module_aliased[qualifier]
	if !is_alias {
		actual_module = qualifier
	}

	et, et_ok := export_tables^[actual_module]
	if !et_ok {
		return base.Canonical_Name{}, false
	}

	ei, ei_ok := export_lookup(&et, field)
	if !ei_ok || !ei.is_pub {
		field_str := base.intern_get(interner, field)
		mod_str := base.intern_get(interner, actual_module)
		diagnostics.collector_add_diag(collector, diagnostics.diag_import_not_exported(field_str, mod_str, span))
		return base.Canonical_Name{}, false
	}

	return base.Canonical_Name{
		module = actual_module,
		name = field,
		is_local = false,
	}, true
}

apply_import_resolution :: proc(cfile: ^semantics.CFile, scope: ^Import_Scope, export_tables: ^map[base.Intern_ID]Export_Table, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) {
	for &decl in cfile.decls {
		resolve_decl_names(decl, scope, export_tables, interner, collector)
	}
}

	resolve_decl_names :: proc(decl: semantics.CDecl, scope: ^Import_Scope, export_tables: ^map[base.Intern_ID]Export_Table, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) {
	#partial switch d in decl {
	case ^semantics.CDecl_Const:
		resolve_expr_names(d.body, scope, export_tables, interner, collector)
	case ^semantics.CDecl_Test:
		resolve_expr_names(d.body, scope, export_tables, interner, collector)
	case ^semantics.CDecl_Expect:
		resolve_expr_names(d.condition, scope, export_tables, interner, collector)
	case ^semantics.CDecl_Effect, ^semantics.CDecl_Trait, ^semantics.CDecl_Alias, ^semantics.CDecl_Newtype, ^semantics.CDecl_Import:
	}
}

resolve_expr_names :: proc(expr: semantics.CExpr, scope: ^Import_Scope, export_tables: ^map[base.Intern_ID]Export_Table, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) {
	switch e in expr {
	case ^semantics.CExpr_Name:
		if e.name.module == base.NO_NAME {
			if resolved, ok := resolve_name(e.name.name, scope, interner); ok {
				e.name = resolved
			}
		}

		case ^semantics.CExpr_Field_Access:
			resolve_expr_names(e.record, scope, export_tables, interner, collector)
			#partial switch r in e.record {
			case ^semantics.CExpr_Name:
				if r.name.is_local && r.name.module == base.NO_NAME {
					if _, is_module := scope.module_aliased[r.name.name]; is_module {
						resolved, ok := resolve_qualified_access(r.name.name, e.field, scope, export_tables, interner, collector, e.span)
						if ok {
							r.name = resolved
						}
					}
				}
			case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
			     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_Record, ^semantics.CExpr_List,
			     ^semantics.CExpr_Call, ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block,
			     ^semantics.CExpr_If, ^semantics.CExpr_Match, ^semantics.CExpr_BinOp, ^semantics.CExpr_PrefixOp,
			     ^semantics.CExpr_Field_Access, ^semantics.CExpr_Record_Update, ^semantics.CExpr_Assign,
			     ^semantics.CExpr_Return, ^semantics.CExpr_Crash, ^semantics.CExpr_Interpolated_String,
			     ^semantics.CExpr_Handle, ^semantics.CExpr_Perform, ^semantics.CExpr_For, ^semantics.CExpr_Par:
			}

	case ^semantics.CExpr_Call:
		resolve_expr_names(e.callee, scope, export_tables, interner, collector)
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Method_Call:
		resolve_expr_names(e.receiver, scope, export_tables, interner, collector)
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Lambda:
		resolve_expr_names(e.body, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Block:
		for &stmt in e.statements {
			resolve_expr_names(stmt, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_If:
		resolve_expr_names(e.condition, scope, export_tables, interner, collector)
		resolve_expr_names(e.then_branch, scope, export_tables, interner, collector)
		resolve_expr_names(e.else_branch, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Match:
		resolve_expr_names(e.scrutinee, scope, export_tables, interner, collector)
		for &arm in e.arms {
			resolve_expr_names(arm.body, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_BinOp:
		resolve_expr_names(e.left, scope, export_tables, interner, collector)
		resolve_expr_names(e.right, scope, export_tables, interner, collector)

	case ^semantics.CExpr_PrefixOp:
		resolve_expr_names(e.operand, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Tag:
		if e.name.module == base.NO_NAME {
			if resolved, ok := resolve_name(e.name.name, scope, interner); ok {
				e.name = resolved
			}
		}
		for &p in e.payload {
			resolve_expr_names(p, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Nominal_Construct:
		if e.type_name.module == base.NO_NAME {
			if resolved, ok := resolve_name(e.type_name.name, scope, interner); ok {
				e.type_name = resolved
			}
		}
		for &p in e.payload {
			resolve_expr_names(p, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Record:
		for &f in e.fields {
			resolve_expr_names(f.value, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_List:
		for &el in e.elements {
			resolve_expr_names(el, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Record_Update:
		resolve_expr_names(e.rest, scope, export_tables, interner, collector)
		for &u in e.updates {
			resolve_expr_names(u.value, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Assign:
		resolve_expr_names(e.target, scope, export_tables, interner, collector)
		resolve_expr_names(e.value, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Return:
		resolve_expr_names(e.value, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Crash:
		resolve_expr_names(e.message, scope, export_tables, interner, collector)

	case ^semantics.CExpr_Interpolated_String:
		for &part in e.parts {
			switch p in part {
			case ^semantics.CExpr_String_Literal:
			case semantics.CExpr:
				resolve_expr_names(p, scope, export_tables, interner, collector)
			}
		}

	case ^semantics.CExpr_Handle:
		if e.effect.module == base.NO_NAME {
			if resolved, ok := resolve_name(e.effect.name, scope, interner); ok {
				e.effect = resolved
			}
		}
		resolve_expr_names(e.body, scope, export_tables, interner, collector)
		for &arm in e.arms {
			resolve_expr_names(arm.body, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool:

	case ^semantics.CExpr_Perform:
		for &arg in e.args {
			resolve_expr_names(arg, scope, export_tables, interner, collector)
		}

	case ^semantics.CExpr_Par:
		if e.for_var != 0 {
			resolve_expr_names(e.for_iter, scope, export_tables, interner, collector)
			resolve_expr_names(e.for_body, scope, export_tables, interner, collector)
		} else {
			for &expr in e.expressions {
				resolve_expr_names(expr, scope, export_tables, interner, collector)
			}
		}

	case ^semantics.CExpr_For:
		resolve_expr_names(e.iterable, scope, export_tables, interner, collector)
		resolve_expr_names(e.body, scope, export_tables, interner, collector)

	case: // all other CExpr variants: no names to resolve
	}
}

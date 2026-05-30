package build

import "camp:analysis"
import "camp:base"
import "camp:diagnostics"
import "camp:semantics"
import "core:fmt"
import "core:os"

run_check_project :: proc(thread_count: int = 1) -> Build_Result {
	ctx: Compilation_Context
	context_init(&ctx)
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator
	ctx.thread_count = thread_count
	defer context_destroy(&ctx)

	cwd := os.getwd(context.allocator) or_else "."

	project := discover_project(cwd, &ctx.interner, &ctx.collector, ctx.allocator)
	ctx.project = project

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "discovery errors", code = 1})
	}

	if len(project.modules) == 0 {
		diagnostics.collector_add_diag(&ctx.collector, diagnostics.diag_project_no_source())
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "no source modules found", code = 1})
	}

	if project.entry_point == base.NO_NAME {
		diagnostics.collector_add_diag(&ctx.collector, diagnostics.diag_entry_point_not_found())
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "entry point not found", code = 1})
	}

	fmt.printfln("discovered {} module(s)", len(project.modules))

	for name, &mi in project.modules {
		result := parse_and_canonicalize(&mi, &ctx)
		switch _ in result {
		case Build_Error:
			return result
		case Build_Output:
		}
	}

	graph := build_module_graph(&project, &ctx.interner, &ctx.collector)
	defer module_graph_destroy(&graph)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "module graph errors", code = 1})
	}

	sorted, ok := topological_sort(&graph, &ctx.interner, &ctx.collector)
	if !ok {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "circular dependency detected", code = 1})
	}

	for mod_id in sorted {
		mi_ptr, mi_ok := &project.modules[mod_id]
		if !mi_ok do continue
		if mi_ptr.cfile == nil {
			result := parse_and_canonicalize(mi_ptr, &ctx)
			switch _ in result {
			case Build_Error:
				return result
			case Build_Output:
			}
		}
		if mi_ptr.cfile == nil do continue

		mi := mi_ptr^
		store: semantics.Type_Store
		semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
		semantics.inject_prelude(&store)

		for dep_id in sorted {
			if dep_id == mod_id do break
			dep_store, dep_ok := ctx.module_stores[dep_id]
			if !dep_ok do continue
			dep_et, dep_et_ok := ctx.export_tables[dep_id]
			if !dep_et_ok do continue

			for name_id, type_var in dep_store.bindings {
				ei, ei_ok := export_lookup(&dep_et, name_id)
				if ei_ok && ei.is_pub {
					store.bindings[name_id] = type_var
				}
			}
		}

		semantics.typecheck_file(mi.cfile^, &store, mod_id)

		if diagnostics.diag_collector_has_errors(&ctx.collector) {
			diagnostics.render_all(&ctx.collector, mi.path, mi.source)
			return Build_Result(
				Build_Error {
					message = fmt.tprintf("typecheck errors in module {}", mod_id),
					code = 1,
				},
			)
		}

		ctx.module_stores[mod_id] = store
		et := collect_exports(mi.cfile^, &store)
		ctx.export_tables[mod_id] = et
	}

	for mod_id in sorted {
		mi2_ptr, mi2_ok := &project.modules[mod_id]
		if !mi2_ok do continue
		if mi2_ptr.cfile == nil do continue

		scope := resolve_imports(
			mod_id,
			mi2_ptr.cfile,
			&ctx.export_tables,
			&project,
			&ctx.interner,
			&ctx.collector,
		)
		apply_import_resolution(
			mi2_ptr.cfile,
			&scope,
			&ctx.export_tables,
			&ctx.interner,
			&ctx.collector,
		)
		import_scope_destroy(&scope)
	}

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "import resolution errors", code = 1})
	}

	entry_mi := project.modules[project.entry_point]
	if entry_mi.cfile != nil {
		main_id := base.intern(&ctx.interner, "main!")
		if _, ok := ctx.module_stores[project.entry_point].bindings[main_id]; !ok {
			diagnostics.collector_add_diag(&ctx.collector, diagnostics.diag_entry_point_no_main())
			diagnostics.render_all(&ctx.collector, "", "")
			return Build_Result(Build_Error{message = "no main! in entry point", code = 1})
		}
	}

	fmt.printfln("typecheck passed for all modules")

	// Run unused binding analysis on each module
	for mod_id in sorted {
		mi_ua, mi_ua_ok := project.modules[mod_id]
		if !mi_ua_ok do continue
		if mi_ua.cfile == nil do continue
		analysis.run_unused_analysis(mi_ua.cfile^, &ctx.interner, &ctx.collector)
	}

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "analysis errors", code = 1})
	}

	fmt.printfln("check passed for all modules")
	return Build_Result(Build_Output{wasm_path = "", has_errors = false})
}

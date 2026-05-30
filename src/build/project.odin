package build

import "camp:analysis"
import "camp:base"
import "camp:codegen"
import "camp:diagnostics"
import "camp:frontend"
import "camp:ir"
import "camp:mono"
import "camp:semantics"
import "core:fmt"
import "core:os"

run_build_project :: proc(thread_count: int = 1, output_path: string = "") -> Build_Result {
	ctx: Compilation_Context
	context_init(&ctx)
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator
	ctx.thread_count = thread_count
	defer context_destroy(&ctx)

	cwd := os.get_env("PWD", ctx.allocator)
	if len(cwd) == 0 {
		cwd = "."
	}

	project := discover_project(cwd, &ctx.interner, &ctx.collector, ctx.allocator)
	register_stdlib_modules(&project, &ctx.interner)
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

	cached_count := 0

	for name, &mi in project.modules {
		manifest, cache_ok := cache_read_manifest(mi.content_hash, ctx.allocator)
		if cache_ok && len(manifest.imports) > 0 {
			cached_count += 1
			mi.imports = make([dynamic]base.Deferred_Import, 0, len(manifest.imports))
			for m_imp in manifest.imports {
				di: base.Deferred_Import
				di.module = base.intern(&ctx.interner, m_imp.module)
				di.names = make([dynamic]base.Intern_ID, 0, len(m_imp.names))
				for name in m_imp.names {
					append(&di.names, base.intern(&ctx.interner, name))
				}
				if len(m_imp.alias) > 0 {
					di.alias = base.intern(&ctx.interner, m_imp.alias)
				}
				append(&mi.imports, di)
			}
			mi.exports = make([dynamic]Export_Info, 0, len(manifest.exports))
			for m_exp in manifest.exports {
				append(
					&mi.exports,
					Export_Info {
						name = base.intern(&ctx.interner, m_exp.name),
						kind = m_exp.kind,
						is_pub = m_exp.is_pub,
						pub_variants = m_exp.pub_variants,
						type_var = base.Type_Var_ID(-1),
					},
				)
			}
			manifest_destroy(&manifest)
			continue
		}
		if cache_ok {
			manifest_destroy(&manifest)
		}

		result := parse_and_canonicalize(&mi, &ctx)
		switch _ in result {
		case Build_Error:
			return result
		case Build_Output:
		}
	}

	if cached_count > 0 {
		fmt.printfln("loaded {} module(s) from cache", cached_count)
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

	ctx.type_store = &ctx.module_stores[project.entry_point]
	combined_ir := combine_module_irs(sorted[:], &project, &ctx)
	combined_ir = ir.effect_lower(&combined_ir, &ctx.interner, &ctx.collector, ctx.type_store)
	errors_before_cc := ctx.collector.error_count
	combined_ir = ir.closure_convert(&combined_ir, &ctx.interner, &ctx.collector)

	if ctx.collector.error_count > errors_before_cc {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(Build_Error{message = "closure conversion errors", code = 1})
	}

	combined_ir = ir.cps_transform(&combined_ir, &ctx.interner)
	ir.rc_insert(&combined_ir, &ctx.interner)
	ir.reuse_analyze(&combined_ir)

	wasm_mod := codegen.codegen(combined_ir, &ctx.interner, ctx.thread_count)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)
	defer delete(wasm_bytes)
	local_output := output_path
	if local_output == "" {
		local_output = "a.wasm"
	}
	write_err := os.write_entire_file_from_bytes(local_output, wasm_bytes[:])
	if write_err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_write_failed(local_output, fmt.tprintf("{}", write_err)),
		)
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Result(
			Build_Error{message = fmt.tprintf("write failed: {}", local_output), code = 1},
		)
	}
	fmt.printfln("compiled project -> {}", local_output)
	return Build_Result(Build_Output{wasm_path = local_output, has_errors = false})
}

parse_and_canonicalize :: proc(mi: ^Module_Info, ctx: ^Compilation_Context) -> Build_Result {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator

	source_file := base.Source_File {
		path     = mi.path,
		contents = mi.source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, source_file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := frontend.parser_parse_file(&parser)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, mi.path, mi.source)
		return Build_Result(
			Build_Error{message = fmt.tprintf("parse errors in {}", mi.path), code = 1},
		)
	}

	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)

	cfile_ptr := new(semantics.CFile)
	cfile_ptr^ = canon
	mi.cfile = cfile_ptr
	mi.imports = canon.imports

	cache_write_manifest(mi, &ctx.interner)
	return Build_Result(Build_Output{wasm_path = "", has_errors = false})
}

combine_module_irs :: proc(
	sorted: []base.Intern_ID,
	project: ^Project_Discovery,
	ctx: ^Compilation_Context,
) -> ir.IR_Module {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator

	combined: ir.IR_Module
	combined.decls = make([dynamic]ir.IR_Decl, 0, 64)
	combined.effect_defs = make([dynamic]ir.IR_Effect_Def, 0, 16)
	combined.string_table = make([dynamic]ir.String_Table_Entry, 0, 32)

	for mod_id in sorted {
		mi := project.modules[mod_id]
		if mi.cfile == nil do continue

		store, ok := ctx.module_stores[mod_id]
		if !ok do continue

		tfile := semantics.typecheck_file(mi.cfile^, &store)
		mono_tfile := mono.mono(tfile, &store, &ctx.interner)
		ir_mod := ir.lower_tfile(mono_tfile, &store)

		for &decl in ir_mod.decls {
			#partial switch d in decl {
			case ^ir.IR_Decl_Fn:
				d.name.module = mod_id
			case ^ir.IR_Decl_Const:
				d.name.module = mod_id
			case ^ir.IR_Decl_Effect:
			}
			append(&combined.decls, decl)
		}

		for &eff in ir_mod.effect_defs {
			append(&combined.effect_defs, eff)
		}

		for &entry in ir_mod.string_table {
			append(&combined.string_table, entry)
		}

		delete(ir_mod.decls)
		delete(ir_mod.effect_defs)
		delete(ir_mod.string_table)
	}

	return combined
}


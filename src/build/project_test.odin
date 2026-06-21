package build

import "camp:base"
import "camp:diagnostics"
import "camp:semantics"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"

run_test_project :: proc(filter: string = "", verbose: bool = false) -> Build_Result {
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator
	defer context_destroy(&ctx)

	cwd := os.getwd(context.allocator) or_else "."

	project := discover_project(cwd, &ctx.interner, &ctx.collector, ctx.allocator)
	register_stdlib_modules(&project, &ctx.interner)
	ctx.project = project

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Error{message = "discovery errors", code = 1}
	}

	if len(project.modules) == 0 {
		diagnostics.collector_add_diag(&ctx.collector, diagnostics.diag_project_no_source())
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Error{message = "no source modules found", code = 1}
	}

	fmt.printfln("discovered {} module(s)", len(project.modules))

	// Phase 1: parse+canonicalize user modules (stdlib registered transitively below)
	for name, &mi in project.modules {
		result := parse_and_canonicalize(&mi, &ctx)
		switch _ in result {
		case Build_Error:
			return result
		case Build_Output:
		}
	}

	// BFS-register transitively-imported stdlib modules with tolerance.
	// No always-compile — test mode has no codegen.
	seed_imports: [dynamic]base.Deferred_Import
	defer delete(seed_imports)
	for mod_id in project.module_names {
		mi, ok := project.modules[mod_id]
		if !ok do continue
		for imp in mi.imports {
			append(&seed_imports, imp)
		}
	}
	register_stdlib_transitive(&project, seed_imports[:], &ctx, always_compile = {})

	// Phase 2: build module graph, typecheck in dependency order
	graph := build_module_graph(&project, &ctx.interner, &ctx.collector)
	defer module_graph_destroy(&graph)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Error{message = "module graph errors", code = 1}
	}

	sorted, ok := topological_sort(&graph, &ctx.interner, &ctx.collector)
	if !ok {
		diagnostics.render_all(&ctx.collector, "", "")
		return Build_Error{message = "circular dependency detected", code = 1}
	}

	for mod_id in sorted {
		mi_ptr, mi_ok := &project.modules[mod_id]
		if !mi_ok do continue
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
			return Build_Error {
				message = fmt.tprintf("typecheck errors in module {}", mod_id),
				code = 1,
			}
		}

		ctx.module_stores[mod_id] = store
		et := collect_exports(mi.cfile^, &store)
		ctx.export_tables[mod_id] = et
	}

	// Phase 3: import resolution
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
		return Build_Error{message = "import resolution errors", code = 1}
	}

	// Phase 4: collect test declarations from all modules
	Test_Entry :: struct {
		mod_name:  string,
		test_name: string,
		cfile:     ^semantics.CFile,
		cbody:     semantics.CExpr,
	}

	test_entries: [dynamic]Test_Entry
	defer delete(test_entries)

	total_expect_count := 0

	for mod_id in sorted {
		mi, mi_ok := project.modules[mod_id]
		if !mi_ok do continue
		if mi.cfile == nil do continue
		mod_name := base.intern_get(&ctx.interner, mod_id)

		for decl in mi.cfile.decls {
			#partial switch d in decl {
			case ^semantics.CDecl_Test:
				if filter == "" || strings.contains(d.name, filter) {
					append(
						&test_entries,
						Test_Entry {
							mod_name = mod_name,
							test_name = d.name,
							cfile = mi.cfile,
							cbody = d.body,
						},
					)
				}
			case ^semantics.CDecl_Expect:
				total_expect_count += 1
			}
		}
	}

	if total_expect_count > 0 && verbose {
		fmt.printfln("  {} expect assertion(s)", total_expect_count)
	}

	if len(test_entries) == 0 {
		fmt.printfln("no tests found")
		return Build_Output{wasm_path = "", has_errors = false}
	}

	fmt.printfln("running {} test(s) across {} module(s)", len(test_entries), len(project.modules))

	// Phase 5: compile and run each test
	pass_count := 0
	fail_count := 0
	pid := os.get_pid()

	for entry in test_entries {
		safe_name := sanitize_test_name(fmt.tprintf("{}-{}", entry.mod_name, entry.test_name))
		tmp_dir := fmt.tprintf("/tmp/camp-test-{}-{}", pid, safe_name)
		os.make_directory_all(tmp_dir)
		tmp_wasm_path := fmt.tprintf("{}/main.wasm", tmp_dir)

		sub_arena: virtual.Arena
		arena_err := virtual.arena_init_growing(&sub_arena)
		if arena_err != nil {
			fmt.printfln("  FAIL  {}::{} (could not init arena)", entry.mod_name, entry.test_name)
			fail_count += 1
			os.remove_all(tmp_dir)
			continue
		}

		compile_ok := compile_test_canon(
			entry.cfile^,
			entry.cbody,
			tmp_wasm_path,
			&ctx.interner,
			&sub_arena,
		)
		virtual.arena_destroy(&sub_arena)

		if !compile_ok {
			fmt.printfln("  FAIL  {}::{} (compilation failed)", entry.mod_name, entry.test_name)
			fail_count += 1
			os.remove_all(tmp_dir)
			continue
		}

		wasm_stdout, wasm_stderr, exit_code := run_wasmtime_proc(tmp_wasm_path)
		os.remove_all(tmp_dir)

		if exit_code == 0 {
			pass_count += 1
			if verbose {
				fmt.printfln("  PASS  {}::{}", entry.mod_name, entry.test_name)
				if len(wasm_stdout) > 0 {
					fmt.printfln("    stdout: {}", wasm_stdout)
				}
				if len(wasm_stderr) > 0 {
					fmt.printfln("    stderr: {}", wasm_stderr)
				}
			} else {
				fmt.printfln("  PASS  {}::{}", entry.mod_name, entry.test_name)
			}
		} else {
			fail_count += 1
			fmt.printfln(
				"  FAIL  {}::{} (exit code: {})",
				entry.mod_name,
				entry.test_name,
				exit_code,
			)
			if len(wasm_stdout) > 0 {
				fmt.printfln("    stdout: {}", wasm_stdout)
			}
			if len(wasm_stderr) > 0 {
				fmt.printfln("    stderr: {}", wasm_stderr)
			}
		}
	}

	fmt.printfln("\n{} passed, {} failed", pass_count, fail_count)

	if fail_count > 0 {
		return Build_Error{message = fmt.tprintf("{} test(s) failed", fail_count), code = 1}
	}

	return Build_Output{wasm_path = "", has_errors = false}
}


package camp

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
	Lsp,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build": return .Build, true
	case "test":  return .Test, true
	case "fmt":   return .Fmt, true
	case "check": return .Check, true
	case "lsp":   return .Lsp, true
	case:         return .Build, false
	}
}

run_build :: proc(args: []string) {
	thread_count := 1
	filtered := make([dynamic]string, 0, len(args))
	i := 0
	for i < len(args) {
		if args[i] == "--threads" && i + 1 < len(args) {
			i += 1
			val := args[i]
			n: int = 0
			for c in val {
				if c >= '0' && c <= '9' {
					n = n * 10 + int(c - '0')
				} else {
					break
				}
			}
			if n > 0 {
				thread_count = n
			}
			i += 1
		} else {
			append(&filtered, args[i])
			i += 1
		}
	}
	defer delete(filtered)
	CAMP_THREADS = thread_count

	single_file := len(filtered) > 0

	if single_file {
		run_build_single(filtered[0])
		return
	}

	run_build_project(thread_count)
}

run_build_single :: proc(file_path: string, thread_count: int = 1) {
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = thread_count
	defer context_destroy(&ctx)

	if filepath.ext(file_path) != ".camp" {
		ext := filepath.ext(file_path)
		collector_add_diag(&ctx.collector, diag_invalid_extension(file_path, ext))
		render_all(&ctx.collector, file_path, "")
		os.exit(1)
	}

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil {
		collector_add_diag(&ctx.collector, diag_file_not_found(file_path, fmt.tprintf("{}", err)))
		render_all(&ctx.collector, file_path, "")
		os.exit(1)
	}
	source := string(data)

	file_rec := Source_File{path = file_path, contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := parser_parse_file(&parser)
	context.allocator = old_allocator

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, file_path, source)
		os.exit(1)
	}

	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, &ctx)
	context.allocator = old_allocator

	fmt.printfln("canonicalized {}: {} declaration(s), {} import(s)", file_path, len(canon.decls), len(canon.imports))

	context.allocator = ctx.allocator
	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	typecheck_file(canon, &store)
	context.allocator = old_allocator

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, file_path, source)
		os.exit(1)
	}
	defer type_store_destroy(&store)

	fmt.printfln("typecheck passed for {}", file_path)

	context.allocator = ctx.allocator
	annot_tfile := annotate_file(canon, &store)
	mono_tfile := mono(annot_tfile, &store, &ctx.interner)
	context.allocator = old_allocator

	context.allocator = ctx.allocator
	ctx.type_store = &store
	ir_mod := lower_tfile(mono_tfile, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	ir_mod = closure_convert(&ir_mod, &ctx)
	ir_mod = cps_transform(&ir_mod, &ctx)
	rc_insert(&ir_mod, &ctx)
	context.allocator = old_allocator

	context.allocator = ctx.allocator
	wasm_mod := codegen(ir_mod, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod)
	context.allocator = old_allocator

	dir := filepath.dir(file_path)
	stem := filepath.stem(file_path)
	output_path := fmt.tprintf("{}/{}.wasm", dir, stem)

	_ = os.write_entire_file_from_bytes(output_path, wasm_bytes)
	fmt.printfln("compiled {} -> {}", file_path, output_path)
}

run_build_project :: proc(thread_count: int = 1) {
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = thread_count
	defer context_destroy(&ctx)

	cwd := os.get_env("PWD", ctx.allocator)
	if len(cwd) == 0 {
		cwd = "."
	}

	project := discover_project(cwd, &ctx.interner, &ctx.collector, ctx.allocator)
	register_stdlib_modules(&project, &ctx.interner)
	ctx.project = project

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	if len(project.modules) == 0 {
		collector_add_diag(&ctx.collector, diag_project_no_source())
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	if project.entry_point == NO_NAME {
		collector_add_diag(&ctx.collector, diag_entry_point_not_found())
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	fmt.printfln("discovered {} module(s)", len(project.modules))

	cached_count := 0

	for name, &mi in project.modules {
		manifest, cache_ok := cache_read_manifest(mi.content_hash, ctx.allocator)
		if cache_ok && len(manifest.imports) > 0 {
			cached_count += 1
			mi.imports = make([dynamic]Deferred_Import, 0, len(manifest.imports))
			for m_imp in manifest.imports {
				di: Deferred_Import
				di.module = intern(&ctx.interner, m_imp.module)
				di.exposing = make([dynamic]Intern_ID, 0, len(m_imp.exposing))
				for exp in m_imp.exposing {
					append(&di.exposing, intern(&ctx.interner, exp))
				}
				if len(m_imp.alias) > 0 {
					di.alias = intern(&ctx.interner, m_imp.alias)
				}
				di.is_unsafe = m_imp.is_unsafe
				append(&mi.imports, di)
			}
			mi.exports = make([dynamic]Export_Info, 0, len(manifest.exports))
			for m_exp in manifest.exports {
				append(&mi.exports, Export_Info{
					name = intern(&ctx.interner, m_exp.name),
					kind = m_exp.kind,
					is_pub = m_exp.is_pub,
					pub_variants = m_exp.pub_variants,
					type_var = Type_Var_ID(-1),
				})
			}
			manifest_destroy(&manifest)
			continue
		}
		if cache_ok {
			manifest_destroy(&manifest)
		}

		parse_and_canonicalize(&mi, &ctx)
	}

	if cached_count > 0 {
		fmt.printfln("loaded {} module(s) from cache", cached_count)
	}

	graph := build_module_graph(&project, &ctx.interner, &ctx.collector)
	defer module_graph_destroy(&graph)

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	sorted, ok := topological_sort(&graph, &ctx.interner, &ctx.collector)
	if !ok {
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	for mod_id in sorted {
		mi_ptr, mi_ok := &project.modules[mod_id]
		if !mi_ok do continue
		if mi_ptr.cfile == nil {
			parse_and_canonicalize(mi_ptr, &ctx)
		}
		if mi_ptr.cfile == nil do continue

		mi := mi_ptr^
		store: Type_Store
		type_store_init(&store, &ctx.interner, &ctx.collector)
		inject_prelude(&store)

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

		context.allocator = ctx.allocator
		typecheck_file(mi.cfile^, &store, mod_id)
		context.allocator = old_allocator_save()

		if diag_collector_has_errors(&ctx.collector) {
			render_all(&ctx.collector, mi.path, mi.source)
			os.exit(1)
		}

		ctx.module_stores[mod_id] = store
		et := collect_exports(mi.cfile^, &store)
		ctx.export_tables[mod_id] = et
	}

	for mod_id in sorted {
		mi2_ptr, mi2_ok := &project.modules[mod_id]
		if !mi2_ok do continue
		if mi2_ptr.cfile == nil do continue

		scope := resolve_imports(mod_id, mi2_ptr.cfile, &ctx.export_tables, &project, &ctx.interner, &ctx.collector)
		apply_import_resolution(mi2_ptr.cfile, &scope, &ctx.export_tables, &ctx.interner, &ctx.collector)
		import_scope_destroy(&scope)
	}

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, "", "")
		os.exit(1)
	}

	entry_mi := project.modules[project.entry_point]
	if entry_mi.cfile != nil {
		main_id := intern(&ctx.interner, "main!")
		if _, ok := ctx.module_stores[project.entry_point].bindings[main_id]; !ok {
			collector_add_diag(&ctx.collector, diag_entry_point_no_main())
			render_all(&ctx.collector, "", "")
			os.exit(1)
		}
	}

	fmt.printfln("typecheck passed for all modules")

	context.allocator = ctx.allocator
	ctx.type_store = &ctx.module_stores[project.entry_point]
	combined_ir := combine_module_irs(sorted, &project, &ctx)
	combined_ir = effect_lower(&combined_ir, &ctx)
	combined_ir = closure_convert(&combined_ir, &ctx)
	combined_ir = cps_transform(&combined_ir, &ctx)
	rc_insert(&combined_ir, &ctx)
	context.allocator = old_allocator_save()

	context.allocator = ctx.allocator
	wasm_mod := codegen(combined_ir, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod)
	context.allocator = old_allocator_save()

	output_path := "a.wasm"
	_ = os.write_entire_file_from_bytes(output_path, wasm_bytes)
	fmt.printfln("compiled project -> {}", output_path)
}

run_check :: proc(args: []string) {
	file_path: string
	if len(args) > 0 {
		file_path = args[0]
	}

	if file_path == "" {
		fmt.eprintln("usage: camp check <file.camp>")
		os.exit(1)
	}

	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	defer context_destroy(&ctx)

	if filepath.ext(file_path) != ".camp" {
		ext := filepath.ext(file_path)
		collector_add_diag(&ctx.collector, diag_invalid_extension(file_path, ext))
		render_all(&ctx.collector, file_path, "")
		os.exit(1)
	}

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil {
		collector_add_diag(&ctx.collector, diag_file_not_found(file_path, fmt.tprintf("{}", err)))
		render_all(&ctx.collector, file_path, "")
		os.exit(1)
	}
	source := string(data)

	file_rec := Source_File{path = file_path, contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := parser_parse_file(&parser)
	context.allocator = old_allocator

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, file_path, source)
		os.exit(1)
	}

	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, &ctx)
	context.allocator = old_allocator

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, file_path, source)
		os.exit(1)
	}

	context.allocator = ctx.allocator
	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	inject_prelude(&store)
	typecheck_file(canon, &store)
	context.allocator = old_allocator
	defer type_store_destroy(&store)

	has_errors := diag_collector_has_errors(&ctx.collector)
	has_warnings := ctx.collector.warning_count > 0
	if has_errors || has_warnings {
		render_all(&ctx.collector, file_path, source)
	}

	if has_errors {
		os.exit(1)
	}

	fmt.printfln("check passed for {}", file_path)
}

run_test :: proc(args: []string) {
	filter := ""
	verbose := false
	file_args: [dynamic]string
	defer delete(file_args)

	i := 0
	for i < len(args) {
		if args[i] == "--filter" && i + 1 < len(args) {
			i += 1
			filter = args[i]
		} else if args[i] == "--verbose" {
			verbose = true
		} else if len(args[i]) > 0 && args[i][0] == '-' {
			fmt.eprintfln("unknown flag: %s", args[i])
			os.exit(2)
		} else {
			append(&file_args, args[i])
		}
		i += 1
	}

	if len(file_args) == 0 {
		fmt.eprintln("usage: camp test [--filter <pattern>] [--verbose] <file.camp>")
		os.exit(1)
	}

	file_path := file_args[0]

	source_bytes, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.eprintfln("error reading %s: %v", file_path, err)
		os.exit(1)
	}
	defer delete(source_bytes, context.allocator)
	source := string(source_bytes)

	// Parse to find test and expect declarations
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	defer context_destroy(&ctx)

	file_rec := Source_File{path = file_path, contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_alloc := context.allocator
	context.allocator = ctx.allocator
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := parser_parse_file(&parser)
	context.allocator = old_alloc

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, file_path, source)
		os.exit(1)
	}

	test_decls: [dynamic]^Decl_Test
	defer delete(test_decls)
	expect_count := 0

	for decl in ast_file.decls {
		#partial switch d in decl {
		case ^Decl_Test:
			if filter == "" || strings.contains(d.name, filter) {
				append(&test_decls, d)
			}
		case ^Decl_Expect:
			expect_count += 1
		}
	}

	if len(test_decls) == 0 && expect_count == 0 {
		fmt.printfln("no tests found")
		return
	}

	if expect_count > 0 && verbose {
		fmt.printfln("  {} expect assertion(s)", expect_count)
	}

	if len(test_decls) == 0 {
		fmt.printfln("no matching tests found")
		return
	}

	fmt.printfln("running {} test(s)", len(test_decls))

	pass_count := 0
	fail_count := 0
	pid := os.get_pid()

	// Canonicalize the already-parsed AST
	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, &ctx)
	context.allocator = old_alloc

	// Build a map from test name to its CDecl_Test body
	test_body_map: map[string]CExpr
	defer delete(test_body_map)
	for decl in canon.decls {
		#partial switch d in decl {
		case ^CDecl_Test:
			if filter == "" || strings.contains(d.name, filter) {
				test_body_map[d.name] = d.body
			}
		}
	}

	for test in test_decls {
		cbody, has_body := test_body_map[test.name]
		if !has_body {
			fmt.printfln("  FAIL  {} (test body not found in canonical AST)", test.name)
			fail_count += 1
			continue
		}

		// Create a temp directory for this test
		safe_name := sanitize_test_name(test.name)
		tmp_dir := fmt.tprintf("/tmp/camp-test-{}-{}", pid, safe_name)
		os.make_directory_all(tmp_dir)
		tmp_wasm_path := fmt.tprintf("{}/main.wasm", tmp_dir)

		// Compile the test body as main! using a fresh sub-arena
		sub_arena: virtual.Arena
		arena_err := virtual.arena_init_growing(&sub_arena)
		if arena_err != nil {
			fmt.printfln("  FAIL  {} (could not init arena)", test.name)
			fail_count += 1
			os.remove_all(tmp_dir)
			continue
		}

		compile_ok := compile_test_canon(canon, cbody, tmp_wasm_path, &ctx.interner, &sub_arena)

		virtual.arena_destroy(&sub_arena)

		if !compile_ok {
			fmt.printfln("  FAIL  {} (compilation failed)", test.name)
			fail_count += 1
			os.remove_all(tmp_dir)
			continue
		}

		// Run with wasmtime
		wasm_stdout, wasm_stderr, exit_code := run_wasmtime_proc(tmp_wasm_path)

		os.remove_all(tmp_dir)

		if exit_code == 0 {
			pass_count += 1
			if verbose {
				fmt.printfln("  PASS  {}", test.name)
				if len(wasm_stdout) > 0 {
					fmt.printfln("    stdout: {}", wasm_stdout)
				}
				if len(wasm_stderr) > 0 {
					fmt.printfln("    stderr: {}", wasm_stderr)
				}
			} else {
				fmt.printfln("  PASS  {}", test.name)
			}
		} else {
			fail_count += 1
			fmt.printfln("  FAIL  {} (exit code: {})", test.name, exit_code)
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
		os.exit(1)
	}
}

compile_test_canon :: proc(orig_canon: CFile, test_body: CExpr, output_path: string, interner: ^Intern_Table, arena: ^virtual.Arena) -> bool {
	alloc := virtual.arena_allocator(arena)

	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	old_alloc := context.allocator
	defer context.allocator = old_alloc
	context.allocator = alloc

	// Build a new CFile: copy all declarations + add main! = test_body
	main_name_id := intern(interner, "main!")
	main_cn := Canonical_Name{module = NO_NAME, name = main_name_id, is_local = false}

	main_decl := new(CDecl_Const)
	main_decl^ = CDecl_Const{
		name   = main_cn,
		is_pub = false,
		is_effectful = true,
		body   = test_body,
		where_clauses = make([dynamic]Where_Clause, 0),
		derive_targets = make([dynamic]Intern_ID, 0),
		span   = Source_Span_ZERO,
	}

	// Copy declarations from original, replacing CDecl_Test/Expect with main!
	new_decls := make([dynamic]CDecl, 0, len(orig_canon.decls) + 1)
	has_main := false

	for decl in orig_canon.decls {
		#partial switch d in decl {
		case ^CDecl_Test:
			// Skip test declarations (we're compiling the test body as main!)
		case ^CDecl_Expect:
			// Skip expect declarations (compile-time assertions)
		case:
			append(&new_decls, decl)
		}
	}

	append(&new_decls, CDecl(main_decl))

	cf := CFile{
		path    = orig_canon.path,
		decls   = new_decls,
		imports = orig_canon.imports,
		span    = orig_canon.span,
	}

	// Typecheck
	store: Type_Store
	type_store_init(&store, interner, &collector)
	defer type_store_destroy(&store)
	inject_prelude(&store)
	typecheck_file(cf, &store)

	if diag_collector_has_errors(&collector) {
		return false
	}

	// Annotate + Mono
	annot_tfile := annotate_file(cf, &store)
	mono_tfile := mono(annot_tfile, &store, interner)

	// Lower + transforms
	ctx_for_lower: Compilation_Context
	ctx_for_lower.allocator = alloc
	ctx_for_lower.interner = interner^
	ctx_for_lower.collector = collector
	ctx_for_lower.type_store = &store

	ir_mod := lower_tfile(mono_tfile, &store)
	ir_mod = effect_lower(&ir_mod, &ctx_for_lower)
	ir_mod = closure_convert(&ir_mod, &ctx_for_lower)
	ir_mod = cps_transform(&ir_mod, &ctx_for_lower)
	rc_insert(&ir_mod, &ctx_for_lower)

	interner.next_id = ctx_for_lower.interner.next_id

	// Codegen + serialize
	wasm_mod := codegen(ir_mod, &ctx_for_lower)
	wasm_bytes := wasm_serialize(wasm_mod)

	// Write to output path
	err := os.write_entire_file_from_bytes(output_path, wasm_bytes)
	return err == nil
}

run_wasmtime_proc :: proc(wasm_path: string) -> (stdout: string, stderr: string, exit_code: int) {
	wasmtime_bin := "wasmtime"
	env_val := os.get_env("WASMTIME", context.allocator)
	if len(env_val) > 0 {
		wasmtime_bin = env_val
	}
	return run_command({wasmtime_bin, "run", wasm_path})
}

run_command :: proc(command: []string) -> (stdout: string, stderr: string, exit_code: int) {
	pid := os.get_pid()
	stdout_path := fmt.tprintf("/tmp/camp-cmd-stdout-{}", pid)
	stderr_path := fmt.tprintf("/tmp/camp-cmd-stderr-{}", pid)

	stdout_f, open_err := os.open(stdout_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	if open_err != nil {
		return "", fmt.tprintf("open stdout file: {}", open_err), 1
	}
	defer os.close(stdout_f)

	stderr_f, open_err2 := os.open(stderr_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	if open_err2 != nil {
		os.remove(stdout_path)
		return "", fmt.tprintf("open stderr file: {}", open_err2), 1
	}
	defer os.close(stderr_f)

	start_proc, start_err := os.process_start(os.Process_Desc{
		command = command,
		stdout = stdout_f,
		stderr = stderr_f,
	})
	if start_err != nil {
		os.remove(stdout_path)
		os.remove(stderr_path)
		return "", fmt.tprintf("process start error: {}", start_err), 1
	}

	PROCESS_TIMEOUT :: 10 * time.Second
	state, wait_err := os.process_wait(start_proc, timeout = PROCESS_TIMEOUT)
	if wait_err != nil || !state.exited {
		kill_err := os.process_kill(start_proc)
		if kill_err == nil {
			_, _ = os.process_wait(start_proc)
		}
		os.remove(stdout_path)
		os.remove(stderr_path)
		return "", "process timed out after 10s", -1
	}

	exit_code = state.exit_code

	stdout_data, stdout_err := os.read_entire_file(stdout_path, context.allocator)
	if stdout_err == nil {
		stdout = string(stdout_data[:])
	}

	stderr_data, stderr_err := os.read_entire_file(stderr_path, context.allocator)
	if stderr_err == nil {
		stderr = string(stderr_data[:])
	}

	os.remove(stdout_path)
	os.remove(stderr_path)
	return
}

sanitize_test_name :: proc(name: string) -> string {
	b := make([]u8, len(name), context.allocator)
	for c, i in name {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
			b[i] = u8(c)
		} else {
			b[i] = '_'
		}
	}
	return string(b)
}

old_allocator_save :: proc() -> mem.Allocator {
	return context.allocator
}

parse_and_canonicalize :: proc(mi: ^Module_Info, ctx: ^Compilation_Context) {
	source_file := Source_File{path = mi.path, contents = mi.source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, source_file, &ctx.collector, &ctx.interner)

	context.allocator = ctx.allocator
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := parser_parse_file(&parser)
	context.allocator = old_allocator_save()

	if diag_collector_has_errors(&ctx.collector) {
		render_all(&ctx.collector, mi.path, mi.source)
		os.exit(1)
	}

	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, ctx)
	context.allocator = old_allocator_save()

	cfile_ptr := new(CFile)
	cfile_ptr^ = canon
	mi.cfile = cfile_ptr
	mi.imports = canon.imports

	context.allocator = ctx.allocator
	cache_write_manifest(mi, &ctx.interner)
	context.allocator = old_allocator_save()
}

combine_module_irs :: proc(sorted: []Intern_ID, project: ^Project_Discovery, ctx: ^Compilation_Context) -> IR_Module {
	combined: IR_Module
	combined.decls = make([dynamic]IR_Decl, 0, 64)
	combined.effect_defs = make([dynamic]IR_Effect_Def, 0, 16)
	combined.string_table = make([dynamic]String_Table_Entry, 0, 32)

	for mod_id in sorted {
		mi := project.modules[mod_id]
		if mi.cfile == nil do continue

		store, ok := ctx.module_stores[mod_id]
		if !ok do continue

		context.allocator = ctx.allocator
		annot_tfile := annotate_file(mi.cfile^, &store)
		mono_tfile := mono(annot_tfile, &store, &ctx.interner)
		ir_mod := lower_tfile(mono_tfile, &store)

		for &decl in ir_mod.decls {
			#partial switch d in decl {
			case ^IR_Decl_Fn:
				d.name.module = mod_id
			case ^IR_Decl_Const:
				d.name.module = mod_id
			case:
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

package build

import "camp:analysis"
import "camp:base"
import "camp:codegen"
import "camp:diagnostics"
import "camp:doc"
import "camp:frontend"
import "camp:ir"
import "camp:mono"
import "camp:semantics"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

Build_Output :: struct {
	wasm_path:  string,
	has_errors: bool,
}

Build_Error :: struct {
	message: string,
	code:    int,
}

Build_Result :: union {
	Build_Output,
	Build_Error,
}

run_command_counter: int

run_build_single :: proc(file_path: string, thread_count: int = 1) -> Build_Result {
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = thread_count
	defer context_destroy(&ctx)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	defer context.allocator = old_allocator

	if filepath.ext(file_path) != ".camp" {
		ext := filepath.ext(file_path)
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_invalid_extension(file_path, ext),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("invalid file extension: {}", ext), code = 1}
	}

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_not_found(file_path, fmt.tprintf("{}", err)),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("file not found: {}", file_path), code = 1}
	}
	source := string(data)

	file_rec := base.Source_File {
		path     = file_path,
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := frontend.parser_parse_file(&parser)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "parse errors", code = 1}
	}

	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)

	if !diagnostics.is_json_mode() {
		fmt.printfln(
			"canonicalized {}: {} declaration(s), {} import(s)",
			file_path,
			len(canon.decls),
			len(canon.imports),
		)
	}

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)
	semantics.check_effect_safety(tfile, &store)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "typecheck errors", code = 1}
	}

	if !diagnostics.is_json_mode() {
		fmt.printfln("typecheck passed for {}", file_path)
	}

	// Run unused binding analysis after typecheck, before lowering
	analysis.run_unused_analysis(canon, &ctx.interner, &ctx.collector)

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "analysis errors", code = 1}
	}

	mono_tfile := mono.mono(tfile, &store, &ctx.interner)

	ctx.type_store = &store
	ir_mod := ir.lower_tfile(mono_tfile, &store)
	ir_mod = ir.effect_lower(&ir_mod, &ctx.interner, &ctx.collector, &store)
	errors_before_cc := ctx.collector.error_count
	ir_mod = ir.closure_convert(&ir_mod, &ctx.interner, &ctx.collector)

	if ctx.collector.error_count > errors_before_cc {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "closure conversion errors", code = 1}
	}

	ir_mod = ir.cps_transform(&ir_mod, &ctx.interner)
	ir.rc_insert(&ir_mod, &ctx.interner)
	ir.reuse_analyze(&ir_mod)

	wasm_mod := codegen.codegen(ir_mod, &ctx.interner, ctx.thread_count)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)
	defer delete(wasm_bytes)

	dir := filepath.dir(file_path)
	stem := filepath.stem(file_path)
	output_path := fmt.tprintf("{}/{}.wasm", dir, stem)

	write_err := os.write_entire_file_from_bytes(output_path, wasm_bytes[:])
	if write_err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_write_failed(output_path, fmt.tprintf("{}", write_err)),
		)
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = fmt.tprintf("write failed: {}", output_path), code = 1}
	}
	if diagnostics.is_json_mode() {
		diagnostics.render_all(&ctx.collector, file_path, source)
	} else {
		fmt.printfln("compiled {} -> {}", file_path, output_path)
	}
	return Build_Output{wasm_path = output_path, has_errors = false}
}

run_check :: proc(args: []string) -> Build_Result {
	file_path: string
	if len(args) > 0 {
		file_path = args[0]
	}

	if file_path == "" {
		fmt.eprintln("usage: camp check <file.camp>")
		return Build_Error{message = "usage: camp check <file.camp>", code = 1}
	}

	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	defer context_destroy(&ctx)

	if filepath.ext(file_path) != ".camp" {
		ext := filepath.ext(file_path)
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_invalid_extension(file_path, ext),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("invalid file extension: {}", ext), code = 1}
	}

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_not_found(file_path, fmt.tprintf("{}", err)),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("file not found: {}", file_path), code = 1}
	}
	source := string(data)

	file_rec := base.Source_File {
		path     = file_path,
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := frontend.parser_parse_file(&parser)
	context.allocator = old_allocator

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "parse errors", code = 1}
	}

	context.allocator = ctx.allocator
	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)
	context.allocator = old_allocator

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "canonicalize errors", code = 1}
	}

	context.allocator = ctx.allocator
	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)
	context.allocator = old_allocator
	defer semantics.type_store_destroy(&store)

	// Run unused binding analysis after typecheck
	analysis.run_unused_analysis(canon, &ctx.interner, &ctx.collector)

	has_errors := diagnostics.diag_collector_has_errors(&ctx.collector)
	has_warnings := ctx.collector.warning_count > 0

	if diagnostics.is_json_mode() {
		diagnostics.render_all(&ctx.collector, file_path, source)
	} else {
		if has_errors || has_warnings {
			diagnostics.render_all(&ctx.collector, file_path, source)
		}
		if !has_errors {
			fmt.printfln("check passed for {}", file_path)
		}
	}

	if has_errors {
		return Build_Error{message = "typecheck errors", code = 1}
	}
	return Build_Output{wasm_path = "", has_errors = false}
}

run_doc :: proc(args: []string) -> Build_Result {
	file_path: string
	if len(args) > 0 {
		file_path = args[0]
	}

	if file_path == "" {
		fmt.eprintln("usage: camp doc <file.camp>")
		return Build_Error{message = "usage: camp doc <file.camp>", code = 1}
	}

	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	defer context_destroy(&ctx)

	if filepath.ext(file_path) != ".camp" {
		ext := filepath.ext(file_path)
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_invalid_extension(file_path, ext),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("invalid file extension: {}", ext), code = 1}
	}

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_not_found(file_path, fmt.tprintf("{}", err)),
		)
		diagnostics.render_all(&ctx.collector, file_path, "")
		return Build_Error{message = fmt.tprintf("file not found: {}", file_path), code = 1}
	}
	source := string(data)

	file_rec := base.Source_File {
		path     = file_path,
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := frontend.parser_parse_file(&parser)
	context.allocator = old_allocator

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "parse errors", code = 1}
	}

	context.allocator = ctx.allocator
	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)
	context.allocator = old_allocator

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "canonicalize errors", code = 1}
	}

	context.allocator = ctx.allocator
	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	semantics.typecheck_file(canon, &store)
	context.allocator = old_allocator
	defer semantics.type_store_destroy(&store)

	has_errors := diagnostics.diag_collector_has_errors(&ctx.collector)

	if has_errors {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "typecheck errors", code = 1}
	}

	context.allocator = ctx.allocator
	doc.generate(canon, &store, &ctx.interner)
	context.allocator = old_allocator

	return Build_Output{wasm_path = "", has_errors = false}
}

run_test :: proc(args: []string) -> Build_Result {
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
			return Build_Error{message = fmt.tprintf("unknown flag: %s", args[i]), code = 2}
		} else {
			append(&file_args, args[i])
		}
		i += 1
	}

	if len(file_args) == 0 {
		fmt.eprintln("usage: camp test [--filter <pattern>] [--verbose] <file.camp>")
		return Build_Error {
			message = "usage: camp test [--filter <pattern>] [--verbose] <file.camp>",
			code = 1,
		}
	}

	file_path := file_args[0]

	source_bytes, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.eprintfln("error reading %s: %v", file_path, err)
		return Build_Error{message = fmt.tprintf("error reading %s: %v", file_path, err), code = 1}
	}
	defer delete(source_bytes, context.allocator)
	source := string(source_bytes)

	// Parse to find test and expect declarations
	ctx: Compilation_Context
	context_init(&ctx)
	ctx.thread_count = 1
	defer context_destroy(&ctx)

	file_rec := base.Source_File {
		path     = file_path,
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_alloc := context.allocator
	context.allocator = ctx.allocator
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := frontend.parser_parse_file(&parser)
	context.allocator = old_alloc

	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "parse errors", code = 1}
	}

	test_decls: [dynamic]^frontend.Decl_Test
	defer delete(test_decls)
	expect_count := 0

	for decl in ast_file.decls {
		#partial switch d in decl {
		case ^frontend.Decl_Test:
			if filter == "" || strings.contains(d.name, filter) {
				append(&test_decls, d)
			}
		case ^frontend.Decl_Expect:
			expect_count += 1
		}
	}

	if len(test_decls) == 0 && expect_count == 0 {
		fmt.printfln("no tests found")
		return Build_Output{wasm_path = "", has_errors = false}
	}

	if expect_count > 0 && verbose {
		fmt.printfln("  {} expect assertion(s)", expect_count)
	}

	if len(test_decls) == 0 {
		fmt.printfln("no matching tests found")
		return Build_Output{wasm_path = "", has_errors = false}
	}

	fmt.printfln("running {} test(s)", len(test_decls))

	pass_count := 0
	fail_count := 0
	pid := os.get_pid()

	// Canonicalize the already-parsed AST
	context.allocator = ctx.allocator
	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)
	context.allocator = old_alloc

	// Build a map from test name to its semantics.CDecl_Test body
	test_body_map: map[string]semantics.CExpr
	defer delete(test_body_map)
	for decl in canon.decls {
		#partial switch d in decl {
		case ^semantics.CDecl_Test:
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
		return Build_Error{message = fmt.tprintf("{} test(s) failed", fail_count), code = 1}
	}

	return Build_Output{wasm_path = "", has_errors = false}
}

compile_test_canon :: proc(
	orig_canon: semantics.CFile,
	test_body: semantics.CExpr,
	output_path: string,
	interner: ^base.Intern_Table,
	arena: ^virtual.Arena,
) -> bool {
	alloc := virtual.arena_allocator(arena)

	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	old_alloc := context.allocator
	defer context.allocator = old_alloc
	context.allocator = alloc

	// Build a new CFile: copy all declarations + add main! = test_body
	main_name_id := base.intern(interner, "main!")
	main_cn := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = main_name_id,
		is_local = false,
	}

	main_decl := new(semantics.CDecl_Const)
	main_decl^ = semantics.CDecl_Const {
		name           = main_cn,
		is_pub         = false,
		is_effectful   = true,
		body           = test_body,
		where_clauses  = make([dynamic]frontend.Where_Clause, 0),
		derive_targets = make([dynamic]base.Intern_ID, 0),
		span           = base.Source_Span_ZERO,
	}

	// Copy declarations from original, replacing semantics.CDecl_Test/Expect with main!
	new_decls := make([dynamic]semantics.CDecl, 0, len(orig_canon.decls) + 1)
	has_main := false

	for decl in orig_canon.decls {
		#partial switch d in decl {
		case ^semantics.CDecl_Test:
		// Skip test declarations (we're compiling the test body as main!)
		case ^semantics.CDecl_Expect:
		// Skip expect declarations (compile-time assertions)
		case ^semantics.CDecl_Const,
		     ^semantics.CDecl_Effect,
		     ^semantics.CDecl_Trait,
		     ^semantics.CDecl_Alias,
		     ^semantics.CDecl_Newtype,
		     ^semantics.CDecl_Import:
			append(&new_decls, decl)
		}
	}

	append(&new_decls, semantics.CDecl(main_decl))

	cf := semantics.CFile {
		path    = orig_canon.path,
		decls   = new_decls,
		imports = orig_canon.imports,
		span    = orig_canon.span,
	}

	// Typecheck (typecheck_file returns TFile directly)
	store: semantics.Type_Store
	semantics.type_store_init(&store, interner, &collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(cf, &store)

	if diagnostics.diag_collector_has_errors(&collector) {
		return false
	}

	// Run unused binding analysis after typecheck
	analysis.run_unused_analysis(cf, interner, &collector)

	if diagnostics.diag_collector_has_errors(&collector) {
		return false
	}

	// Mono
	mono_tfile := mono.mono(tfile, &store, interner)

	// Lower + transforms
	ir_mod := ir.lower_tfile(mono_tfile, &store)

	ir_mod = ir.effect_lower(&ir_mod, interner, &collector, &store)
	errors_before_cc := collector.error_count
	ir_mod = ir.closure_convert(&ir_mod, interner, &collector)

	if collector.error_count > errors_before_cc {
		return false
	}

	ir_mod = ir.cps_transform(&ir_mod, interner)
	ir.rc_insert(&ir_mod, interner)
	ir.reuse_analyze(&ir_mod)

	// Codegen + serialize
	wasm_mod := codegen.codegen(ir_mod, interner, 1)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)
	defer delete(wasm_bytes)

	// Write to output path
	err := os.write_entire_file_from_bytes(output_path, wasm_bytes[:])
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
	run_command_counter += 1
	unique := run_command_counter
	pid := os.get_pid()
	stdout_path := fmt.tprintf("/tmp/camp-cmd-stdout-{}-{}", pid, unique)
	stderr_path := fmt.tprintf("/tmp/camp-cmd-stderr-{}-{}", pid, unique)

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

	start_proc, start_err := os.process_start(
		os.Process_Desc{command = command, stdout = stdout_f, stderr = stderr_f},
	)
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
		if (c >= 'a' && c <= 'z') ||
		   (c >= 'A' && c <= 'Z') ||
		   (c >= '0' && c <= '9') ||
		   c == '-' ||
		   c == '_' {
			b[i] = u8(c)
		} else {
			b[i] = '_'
		}
	}
	return string(b)
}


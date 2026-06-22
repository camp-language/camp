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

run_build_single :: proc(
	file_path: string,
	thread_count: int = 1,
	output_path: string = "",
	release: bool = false,
) -> Build_Result {
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

	// Parse + canonicalize the user file up front so we can read its imports
	// (to register only the transitively-imported stdlib modules) and emit the
	// same "canonicalized" progress line the single-file path always printed.
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

	// Synthesize a Project_Discovery: the user file is the entry-point "Main"
	// module, plus only the stdlib modules it transitively imports. This routes
	// single-file builds through the same dependency-compiling pipeline as
	// `run_build_project` so module-qualified calls (List.length, etc.) resolve
	// to the pure-Camp stdlib implementations.
	main_id := base.intern(&ctx.interner, "Main")
	project: Project_Discovery
	project.modules = make(map[base.Intern_ID]Module_Info, 32)
	project.module_names = make([dynamic]base.Intern_ID, 0, 32)
	project.dependencies = make([dynamic]Dependency_Info, 0, 8)
	project.dev_deps = make([dynamic]Dependency_Info, 0, 4)
	project.entry_point = main_id

	main_cfile := new(semantics.CFile)
	main_cfile^ = canon
	main_mi := Module_Info {
		name         = main_id,
		path         = file_path,
		content_hash = simple_hash(source),
		source       = source,
		cfile        = main_cfile,
		imports      = make([dynamic]base.Deferred_Import, 0, len(canon.imports)),
		exports      = make([dynamic]Export_Info, 0, 16),
	}
	for imp in canon.imports {
		append(&main_mi.imports, imp)
	}
	project.modules[main_id] = main_mi
	append(&project.module_names, main_id)

	// Register transitively-imported stdlib modules. The worklist starts with
	// the user's imports; each newly-registered stdlib module's own imports
	// are appended so the full transitive closure is compiled.
	worklist: [dynamic]base.Intern_ID
	defer delete(worklist)
	for imp in canon.imports {
		append(&worklist, imp.module)
	}

	// Always compile primitive trait-impl modules (Decision A, camp-24mj).
	// These contain `is` impls (Ord, Hash, Debug, Eq, etc.) that the container
	// runtime dispatch (List.compare, Result.eq, etc.) needs as real WASM
	// functions. They must be compiled regardless of user imports.
	// NOTE: Str and Bytes are excluded for now — their trait impls generate
	// wasm-invalid code (type mismatch in block). Tracked as a follow-up.
	ALWAYS_COMPILE :: []string{"Char"}
	for mod_name in ALWAYS_COMPILE {
		append(&worklist, base.intern(&ctx.interner, mod_name))
	}
	for len(worklist) > 0 {
		mod_id := worklist[len(worklist) - 1]
		pop(&worklist)
		if _, exists := project.modules[mod_id]; exists {continue}
		mod_name := base.intern_get(&ctx.interner, mod_id)
		mod, ok := stdlib_lookup(mod_name)
		if !ok {continue} 	// non-stdlib import → reported later as module-not-found
		stdlib_mi := Module_Info {
			name         = mod_id,
			path         = mod.path,
			content_hash = simple_hash(mod.source),
			source       = mod.source,
			imports      = make([dynamic]base.Deferred_Import, 0, 8),
			exports      = make([dynamic]Export_Info, 0, 16),
		}
		project.modules[mod_id] = stdlib_mi
		append(&project.module_names, mod_id)
		errs_before := ctx.collector.error_count
		ok_parse := parse_stdlib_module(&project.modules[mod_id], &ctx)
		if !ok_parse {
			// The embedded stdlib sources are stale (camp-24mj tracks the
			// full sync). A stdlib module that fails to parse/canonicalize
			// must not abort the user's build, and its (often voluminous)
			// diagnostics should not be rendered as errors mid-build. Demote
			// them to warnings and drop the module so its names fall through
			// to codegen runtime intercepts — matching the historical
			// single-file path, which ignored imports entirely.
			demote_recent_errors(&ctx, errs_before)
			delete_key(&project.modules, mod_id)
			for i in 0 ..< len(project.module_names) {
				if project.module_names[i] == mod_id {
					ordered_remove(&project.module_names, i)
					break
				}
			}
		} else {
			for imp in project.modules[mod_id].imports {
				append(&worklist, imp.module)
			}
		}
	}
	ctx.project = project

	graph := build_module_graph(&project, &ctx.interner, &ctx.collector)
	defer module_graph_destroy(&graph)
	demote_unresolved_import_errors(&ctx)
	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "module graph errors", code = 1}
	}

	sorted, ok := topological_sort(&graph, &ctx.interner, &ctx.collector)
	defer delete(sorted)
	if !ok {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "circular dependency detected", code = 1}
	}

	// Typecheck each module with dependency injection (pub bindings from
	// earlier modules in topo order). Mirrors run_build_project.
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

		errs_before_tc := ctx.collector.error_count
		semantics.typecheck_file(mi_ptr.cfile^, &store, mod_id)
		// Always-compiled stdlib modules (not explicitly imported) may have
		// pre-existing semantic errors (e.g. ParseError not in scope, From/
		// TryFrom not registered). Demote their errors to warnings so the
		// user's build isn't blocked by stdlib internals. Successfully-
		// typechecked impls still register in trait_impls for dispatch.
		is_user_import := false
		for imp in canon.imports {
			if imp.module == mod_id {
				is_user_import = true
				break
			}
		}
		if !is_user_import && mod_id != main_id {
			demote_recent_errors(&ctx, errs_before_tc)
		}
		if diagnostics.diag_collector_has_errors(&ctx.collector) {
			diagnostics.render_all(&ctx.collector, mi_ptr.path, mi_ptr.source)
			return Build_Error {
				message = fmt.tprintf("typecheck errors in module {}", mod_id),
				code = 1,
			}
		}
		ctx.module_stores[mod_id] = store
		et := collect_exports(mi_ptr.cfile^, &store)
		ctx.export_tables[mod_id] = et
	}

	for mod_id in sorted {
		mi_ptr, mi_ok := &project.modules[mod_id]
		if !mi_ok do continue
		if mi_ptr.cfile == nil do continue
		scope := resolve_imports(
			mod_id,
			mi_ptr.cfile,
			&ctx.export_tables,
			&project,
			&ctx.interner,
			&ctx.collector,
		)
		apply_import_resolution(
			mi_ptr.cfile,
			&scope,
			&ctx.export_tables,
			&ctx.interner,
			&ctx.collector,
		)
		import_scope_destroy(&scope)
	}

	demote_unresolved_import_errors(&ctx)
	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "import resolution errors", code = 1}
	}

	// Entry-point effect safety: single-file builds, unlike project builds, gate
	// on `check_effect_safety` so unhandled effects in `main!` are reported
	// (project builds rely on each module's own typecheck). main! is NOT required
	// here — single-file builds accept library-style files with no entry point.
	entry_store := ctx.module_stores[project.entry_point]
	entry_tfile := semantics.typecheck_file(canon, &entry_store, project.entry_point)
	semantics.check_effect_safety(entry_tfile, &entry_store)
	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "typecheck errors", code = 1}
	}

	if !diagnostics.is_json_mode() {
		fmt.printfln("typecheck passed for {}", file_path)
	}

	// Unused analysis runs on the entry module only: stdlib modules are trusted
	// (their standalone diagnostics are tracked separately and would distract
	// from the user's program).
	analysis.run_unused_analysis(canon, &ctx.interner, &ctx.collector)
	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "analysis errors", code = 1}
	}

	ctx.type_store = &ctx.module_stores[project.entry_point]
	combined_ir := combine_module_irs(sorted[:], &project, &ctx)
	combined_ir = ir.effect_lower(&combined_ir, &ctx.interner, &ctx.collector, ctx.type_store)
	errors_before_cc := ctx.collector.error_count
	combined_ir = ir.closure_convert(&combined_ir, &ctx.interner, &ctx.collector)
	if ctx.collector.error_count > errors_before_cc {
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = "closure conversion errors", code = 1}
	}
	combined_ir = ir.cps_transform(&combined_ir, &ctx.interner)
	ir.rc_insert(&combined_ir, &ctx.interner)
	ir.reuse_analyze(&combined_ir)
	ir.tree_shake_module(&combined_ir, &ctx.interner)

	wasm_mod := codegen.codegen(combined_ir, &ctx.interner, ctx.thread_count, release)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)
	defer delete(wasm_bytes)
	local_output := output_path
	if local_output == "" {
		local_output = fmt.tprintf("{}/{}.wasm", filepath.dir(file_path), filepath.stem(file_path))
	}
	write_err := os.write_entire_file_from_bytes(local_output, wasm_bytes[:])
	if write_err != nil {
		diagnostics.collector_add_diag(
			&ctx.collector,
			diagnostics.diag_file_write_failed(local_output, fmt.tprintf("{}", write_err)),
		)
		diagnostics.render_all(&ctx.collector, file_path, source)
		return Build_Error{message = fmt.tprintf("write failed: {}", local_output), code = 1}
	}
	if diagnostics.is_json_mode() {
		diagnostics.render_all(&ctx.collector, file_path, source)
	} else {
		fmt.printfln("compiled {} -> {}", file_path, local_output)
	}
	return Build_Output{wasm_path = local_output, has_errors = false}
}

// demote_unresolved_import_errors converts module-not-found ("C0800") and
// import-not-exported ("C0802") errors to warnings. Single-file builds
// register only the stdlib modules the user transitively imports; a name not
// exported from such a module may still be provided by a codegen runtime
// intercept (e.g. List.compare → List_Compare intrinsic), and a module not
// found may be a non-stdlib import the historical single-file path silently
// ignored. Demotion lets those resolve (or report at use-site) instead of
// aborting the build.
demote_unresolved_import_errors :: proc(ctx: ^Compilation_Context) {
	for &d in ctx.collector.diagnostics {
		if d.code == "C0800" || d.code == "C0802" {
			if d.category == .Error {
				d.category = .Warning
				ctx.collector.error_count -= 1
				ctx.collector.warning_count += 1
			}
		}
	}
}

// demote_recent_errors demotes all Error-category diagnostics added to the
// collector since the given error_count snapshot, downgrading them to
// warnings. Used to tolerate parse/canonicalize failures in stale embedded
// stdlib modules so they don't abort a single-file build.
demote_recent_errors :: proc(ctx: ^Compilation_Context, _errs_before: int) {
	diags := ctx.collector.diagnostics
	remaining := ctx.collector.error_count - _errs_before
	if remaining <= 0 do return
	for i := len(diags) - 1; i >= 0 && remaining > 0; i -= 1 {
		if diags[i].category == .Error {
			diags[i].category = .Warning
			ctx.collector.error_count -= 1
			ctx.collector.warning_count += 1
			remaining -= 1
		}
	}
}

// parse_stdlib_module parses and canonicalizes an embedded stdlib module
// WITHOUT rendering diagnostics on failure (unlike parse_and_canonicalize).
// Returns false on parse/canonicalize error; the caller demotes the
// diagnostics and drops the module so its names fall through to runtime
// intercepts. This keeps stale embedded stdlib (camp-24mj sync) from
// aborting single-file builds.
parse_stdlib_module :: proc(mi: ^Module_Info, ctx: ^Compilation_Context) -> bool {
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
		return false
	}
	canon := semantics.canonicalize(ast_file, &ctx.interner, &ctx.collector)
	if diagnostics.diag_collector_has_errors(&ctx.collector) {
		return false
	}
	cfile_ptr := new(semantics.CFile)
	cfile_ptr^ = canon
	mi.cfile = cfile_ptr
	mi.imports = canon.imports
	return true
}

// register_stdlib_transitive performs a BFS over stdlib modules reachable
// from `seed_imports` plus `always_compile` (primitive trait-impl modules
// the container runtime needs as real WASM functions — empty for check
// mode which has no codegen). Parses each with tolerance (demote + drop on
// parse failure — stale embedded sources must not abort a project build)
// and registers the survivors into `project`. Mirrors the single-file path
// (build.odin:130-189). Called by run_build_project and run_check_project
// after user modules have been parsed (so their imports are known).
register_stdlib_transitive :: proc(
	project: ^Project_Discovery,
	seed_imports: []base.Deferred_Import,
	ctx: ^Compilation_Context,
	always_compile: []string = {"Char"},
) {
	worklist: [dynamic]base.Intern_ID
	defer delete(worklist)
	for imp in seed_imports {
		append(&worklist, imp.module)
	}
	for mod_name in always_compile {
		append(&worklist, base.intern(&ctx.interner, mod_name))
	}

	for len(worklist) > 0 {
		mod_id := worklist[len(worklist) - 1]
		pop(&worklist)
		if _, exists := project.modules[mod_id]; exists {continue}
		mod_name := base.intern_get(&ctx.interner, mod_id)
		mod, ok := stdlib_lookup(mod_name)
		if !ok {continue} 	// non-stdlib import → reported later as module-not-found
		stdlib_mi := Module_Info {
			name         = mod_id,
			path         = mod.path,
			content_hash = simple_hash(mod.source),
			source       = mod.source,
			imports      = make([dynamic]base.Deferred_Import, 0, 8),
			exports      = make([dynamic]Export_Info, 0, 16),
		}
		project.modules[mod_id] = stdlib_mi
		append(&project.module_names, mod_id)
		errs_before := ctx.collector.error_count
		ok_parse := parse_stdlib_module(&project.modules[mod_id], ctx)
		if !ok_parse {
			// Stale embedded stdlib (camp-24mj tracks sync). Demote and drop
			// so names fall through to codegen runtime intercepts.
			demote_recent_errors(ctx, errs_before)
			delete_key(&project.modules, mod_id)
			for i in 0 ..< len(project.module_names) {
				if project.module_names[i] == mod_id {
					ordered_remove(&project.module_names, i)
					break
				}
			}
		} else {
			for imp in project.modules[mod_id].imports {
				append(&worklist, imp.module)
			}
		}
	}
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

	// Collect doc tests
	doc_test_codes := doc.extract_all_doc_tests(&ast_file, &ctx.interner, source, file_path)

	// Run regular tests
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

	// Run doc tests
	for dt in doc_test_codes {
		safe_name := sanitize_test_name(fmt.tprintf("%s-%s", dt.decl_name, dt.name))
		tmp_dir := fmt.tprintf("/tmp/camp-test-{}-{}", pid, safe_name)
		os.make_directory_all(tmp_dir)
		defer os.remove_all(tmp_dir)
		tmp_wasm_path := fmt.tprintf("{}/main.wasm", tmp_dir)

		sub_arena: virtual.Arena
		arena_err := virtual.arena_init_growing(&sub_arena)
		if arena_err != nil {
			fmt.printfln("  FAIL  [doc] {} (could not init arena)", dt.name)
			fail_count += 1
			continue
		}

		// Parse the doc test code as an expression
		dt_expr := parse_doc_test_expr(dt.code, &ctx.collector, &ctx.interner)
		if dt_expr == nil {
			fmt.printfln("  FAIL  [doc] {} (parse error in doc test code)", dt.name)
			virtual.arena_destroy(&sub_arena)
			fail_count += 1
			continue
		}

		compile_ok := compile_doc_test_canon(
			canon,
			dt_expr,
			tmp_wasm_path,
			&ctx.interner,
			&sub_arena,
		)
		virtual.arena_destroy(&sub_arena)

		if !compile_ok {
			fmt.printfln("  FAIL  [doc] {} (compilation failed)", dt.name)
			fail_count += 1
			continue
		}

		wasm_stdout, wasm_stderr, exit_code := run_wasmtime_proc(tmp_wasm_path)

		if exit_code == 0 {
			pass_count += 1
			if verbose {
				fmt.printfln("  PASS  [doc] {}: {}", dt.decl_name, dt.name)
				if len(wasm_stdout) > 0 {
					fmt.printfln("    stdout: {}", wasm_stdout)
				}
				if len(wasm_stderr) > 0 {
					fmt.printfln("    stderr: {}", wasm_stderr)
				}
			} else {
				fmt.printfln("  PASS  [doc] {}: {}", dt.decl_name, dt.name)
			}
		} else {
			fail_count += 1
			fmt.printfln("  FAIL  [doc] {}: {} (exit code: {})", dt.decl_name, dt.name, exit_code)
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

run_run :: proc(args: []string) -> Build_Result {
	output_path: string
	file_args: [dynamic]string
	defer delete(file_args)

	i := 0
	for i < len(args) {
		if args[i] == "-o" || args[i] == "--output" {
			if i + 1 < len(args) {
				i += 1
				output_path = args[i]
			} else {
				return Build_Error{message = "-o requires a path argument", code = 2}
			}
		} else {
			append(&file_args, args[i])
		}
		i += 1
	}

	has_file := len(file_args) > 0

	result: Build_Result
	if has_file {
		result = run_build_single(file_args[0], 1, output_path)
	} else {
		result = run_build_project(1, output_path)
	}

	output, is_output := result.(Build_Output)
	if !is_output {
		return result
	}

	if output.wasm_path == "" {
		return Build_Error{message = "no wasm output to run", code = 1}
	}

	fmt.printfln("running {}", output.wasm_path)
	wasm_stdout, wasm_stderr, exit_code := run_wasmtime_proc(output.wasm_path)

	if len(wasm_stdout) > 0 {
		fmt.print(wasm_stdout)
	}
	if len(wasm_stderr) > 0 {
		fmt.eprint(wasm_stderr)
	}

	if exit_code != 0 {
		return Build_Error{message = fmt.tprintf("exit code: {}", exit_code), code = exit_code}
	}

	return Build_Output{wasm_path = output.wasm_path, has_errors = false}
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

	// Init DOT_RECEIVER_INTERN_ID for canonicalization
	semantics.DOT_RECEIVER_INTERN_ID = base.intern(interner, semantics.DOT_RECEIVER_NAME)

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
		case ^semantics.CDecl_Const:
			// Skip the original main! declaration - we'll add our own
			if d.name.name == main_name_id {
				continue
			}
			append(&new_decls, decl)
		case ^semantics.CDecl_Effect,
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

parse_doc_test_expr :: proc(
	code: string,
	collector: ^diagnostics.Diagnostic_Collector,
	interner: ^base.Intern_Table,
) -> frontend.Expr {
	file := base.Source_File {
		path     = "<doctest>",
		contents = code,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, collector, interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, collector, interner)

	return frontend.parser_parse_expr(&parser)
}

compile_doc_test_canon :: proc(
	orig_canon: semantics.CFile,
	test_body: frontend.Expr,
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

	// Init DOT_RECEIVER_INTERN_ID for canonicalization
	semantics.DOT_RECEIVER_INTERN_ID = base.intern(interner, semantics.DOT_RECEIVER_NAME)

	// Create scope for canonicalization
	scope: semantics.Canonicalize_Scope
	scope.local_names = make(map[base.Intern_ID]base.Canonical_Name, 16)
	scope.local_kinds = make(map[base.Intern_ID]semantics.Decl_Kind, 16)
	defer delete(scope.local_names)
	defer delete(scope.local_kinds)

	cbody := semantics.canonicalize_expr(test_body, &scope, interner, &collector)

	// Build a new CFile: copy all declarations + add main! = cbody
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
		body           = cbody,
		where_clauses  = make([dynamic]frontend.Where_Clause, 0),
		derive_targets = make([dynamic]base.Intern_ID, 0),
		span           = base.Source_Span_ZERO,
	}

	new_decls := make([dynamic]semantics.CDecl, 0, len(orig_canon.decls) + 1)
	for decl in orig_canon.decls {
		#partial switch d in decl {
		case ^semantics.CDecl_Test, ^semantics.CDecl_Expect:
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

	store: semantics.Type_Store
	semantics.type_store_init(&store, interner, &collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(cf, &store)

	if diagnostics.diag_collector_has_errors(&collector) {
		return false
	}

	analysis.run_unused_analysis(cf, interner, &collector)
	if diagnostics.diag_collector_has_errors(&collector) {
		return false
	}

	mono_tfile := mono.mono(tfile, &store, interner)
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

	wasm_mod := codegen.codegen(ir_mod, interner, 1)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)
	defer delete(wasm_bytes)

	err := os.write_entire_file_from_bytes(output_path, wasm_bytes[:])
	return err == nil
}


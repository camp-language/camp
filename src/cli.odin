package camp

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"

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
	single_file := len(args) > 0

	if single_file {
		run_build_single(args[0])
		return
	}

	run_build_project()
}

run_build_single :: proc(file_path: string) {
	ctx: Compilation_Context
	context_init(&ctx)
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
	ir_mod := lower_file(canon, &store)
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

run_build_project :: proc() {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	cwd := os.get_env("PWD", ctx.allocator)
	if len(cwd) == 0 {
		cwd = "."
	}

	project := discover_project(cwd, &ctx.interner, &ctx.collector, ctx.allocator)
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

	for name, &mi in project.modules {
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
		canon := canonicalize(ast_file, &ctx)
		context.allocator = old_allocator_save()

		cfile_ptr := new(CFile)
		cfile_ptr^ = canon
		mi.cfile = cfile_ptr
		mi.imports = canon.imports
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
		mi := project.modules[mod_id]
		if mi.cfile == nil do continue

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
		typecheck_file(mi.cfile^, &store)
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
		mi := project.modules[mod_id]
		if mi.cfile == nil do continue

		scope := resolve_imports(mod_id, mi.cfile, &ctx.export_tables, &project, &ctx.interner, &ctx.collector)
		apply_import_resolution(mi.cfile, &scope, &ctx.export_tables, &ctx.interner, &ctx.collector)
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

old_allocator_save :: proc() -> mem.Allocator {
	return context.allocator
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
		ir_mod := lower_file(mi.cfile^, &store)

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

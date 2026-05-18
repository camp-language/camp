package camp

import "core:fmt"
import "core:os"
import "core:path/filepath"

CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build": return .Build, true
	case "test":  return .Test, true
	case "fmt":   return .Fmt, true
	case "check": return .Check, true
	case:         return .Build, false
	}
}

run_build :: proc(args: []string) {
	file_path := "main.camp"
	if len(args) > 0 {
		file_path = args[0]
	}

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

	wasm_mod := codegen(ir_mod, &ctx)
	context.allocator = ctx.allocator
	wasm_bytes := wasm_serialize(wasm_mod)
	context.allocator = old_allocator

	dir := filepath.dir(file_path)
	stem := filepath.stem(file_path)
	output_path := fmt.tprintf("{}/{}.wasm", dir, stem)

	_ = os.write_entire_file_from_bytes(output_path, wasm_bytes)
	fmt.printfln("compiled {} -> {}", file_path, output_path)
}

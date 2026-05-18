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

	if filepath.ext(file_path) != ".camp" {
		fmt.printfln("error: expected .camp file, got {}", file_path)
		os.exit(1)
	}

	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	data, err := os.read_entire_file(file_path, ctx.allocator)
	if err != nil do fmt.printfln("error: could not read file {}", file_path)
	if err != nil do os.exit(1)
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

	if collector_has_errors(&ctx.collector) {
		for e in ctx.collector.errors {
			report_error(&ctx.collector, file_path, source, e)
		}
		fmt.printfln("compilation failed with {} error(s)", ctx.collector.error_count)
		os.exit(1)
	}

	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, &ctx)
	context.allocator = old_allocator

	fmt.printfln("canonicalized {}: {} declaration(s), {} import(s)", file_path, len(canon.decls), len(canon.imports))
	fmt.println("TODO: implement type checking and code generation")
}

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

	collector: Error_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	data, err := os.read_entire_file(file_path, context.allocator)
	if err != nil do fmt.printfln("error: could not read file {}", file_path)
	if err != nil do os.exit(1)
	source := string(data)

	file_rec := Source_File{path = file_path, contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file_rec, &collector, &table)

	parser: Parser
	parser_init(&parser, &lexer, &collector, &table)
	ast_file := parser_parse_file(&parser)

	if collector_has_errors(&collector) {
		for err in collector.errors {
			report_error(&collector, file_path, source, err)
		}
		fmt.printfln("compilation failed with {} error(s)", collector.error_count)
		os.exit(1)
	}

	fmt.printfln("parsed {}: {} declaration(s)", file_path, len(ast_file.decls))
	fmt.println("TODO: implement type checking and code generation")
}

package camp

import "core:testing"

parse_camp_source :: proc(source: string) -> (File, ^Error_Collector) {
	collector: ^Error_Collector = new(Error_Collector)
	collector_init(collector)

	table: Intern_Table
	intern_init(&table)
	defer intern_destroy(&table)

	file := Source_File{path = "<test>", contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file, collector, &table)

	parser: Parser
	parser_init(&parser, &lexer, collector, &table)

	return parser_parse_file(&parser), collector
}

@(test)
test_integration_hello_world :: proc(t: ^testing.T) {
	source := "main! = || ->{ Console } Str { \"Hello, Camp!\" }"
	file, collector := parse_camp_source(source)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_add_function :: proc(t: ^testing.T) {
	source := "add = |x: I64, y: I64| -> I64 { x + y }"
	file, collector := parse_camp_source(source)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_effect_definition :: proc(t: ^testing.T) {
	source := "effect Console { print!: Str }"
	file, collector := parse_camp_source(source)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_multiple_decls :: proc(t: ^testing.T) {
	source := "name = \"Camp\"\nversion = 1\nmain! = || ->{ Console } Str { \"Hello\" }"
	file, collector := parse_camp_source(source)
	defer collector_destroy(collector)
	defer free(collector)

	testing.expect(t, !collector_has_errors(collector))
	testing.expect(t, len(file.decls) == 3)
}

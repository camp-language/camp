package camp

import "core:mem"

Format_Result :: struct {
	output:      string,
	diagnostics: []Diagnostic,
}

format :: proc(source: string, file_path: string, allocator: mem.Allocator) -> Format_Result {
	prev_alloc := context.allocator
	context.allocator = allocator
	defer context.allocator = prev_alloc

	result: Format_Result

	itable: Intern_Table
	intern_init(&itable)
	defer intern_destroy(&itable)

	collector: Diagnostic_Collector
	diag_collector_init(&collector)
	defer diag_collector_destroy(&collector)

	file := Source_File{
		path = file_path,
		contents = source,
		id = 0,
	}

	// Lex all tokens
	tokens: [dynamic]Token
	defer delete(tokens)

	lexer: Lexer
	lexer_init(&lexer, file, &collector, &itable)
	for {
		tok := lexer_next(&lexer)
		append(&tokens, tok)
		if tok.kind == .Eof {
			break
		}
	}

	if diag_collector_has_errors(&collector) {
		result.diagnostics = copy_diagnostics(collector.diagnostics[:])
		return result
	}

	// Parse
	lexer2: Lexer
	lexer_init(&lexer2, file, &collector, &itable)
	parser: Parser
	parser_init(&parser, &lexer2, &collector, &itable)
	ast_file := parser_parse_file(&parser)

	if diag_collector_has_errors(&collector) {
		result.diagnostics = copy_diagnostics(collector.diagnostics[:])
		return result
	}

	// Analyze source
	info := analyze_source(source, tokens[:])
	defer destroy_format_source_info(&info)

	// Format
	doc := format_file(ast_file, &info, &itable)
	result.output = doc_resolve(doc, 0)
	doc_destroy(doc)

	result.diagnostics = copy_diagnostics(collector.diagnostics[:])
	return result
}

copy_diagnostics :: proc(diags: []Diagnostic) -> []Diagnostic {
	if len(diags) == 0 {
		return nil
	}
	result := make([]Diagnostic, len(diags))
	for d, i in diags {
		result[i].category = d.category
		result[i].span = d.span
		result[i].message = d.message
		result[i].title = d.title
		result[i].labels = make([dynamic]Span_Label, len(d.labels))
		copy(result[i].labels[:], d.labels[:])
		result[i].hints = make([dynamic]string, len(d.hints))
		copy(result[i].hints[:], d.hints[:])
	}
	return result
}

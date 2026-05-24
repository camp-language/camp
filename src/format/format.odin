package format

import "core:mem"
import "camp:base"
import "camp:frontend"
import "camp:diagnostics"

Format_Result :: struct {
	output:      string,
	diagnostics: []diagnostics.Diagnostic,
}

format :: proc(source: string, file_path: string, allocator: mem.Allocator) -> Format_Result {
	prev_alloc := context.allocator
	context.allocator = allocator
	defer context.allocator = prev_alloc

	result: Format_Result

	itable: base.Intern_Table
	base.intern_init(&itable)
	defer base.intern_destroy(&itable)

	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	file := base.Source_File{
		path = file_path,
		contents = source,
		id = 0,
	}

	// Lex all tokens
	tokens: [dynamic]base.Token
	defer delete(tokens)

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &collector, &itable)
	for {
		tok := frontend.lexer_next(&lexer)
		append(&tokens, tok)
		if tok.kind == .Eof {
			break
		}
	}

	if diagnostics.diag_collector_has_errors(&collector) {
		result.diagnostics = copy_diagnostics(collector.diagnostics[:])
		return result
	}

	// Parse
	lexer2: frontend.Lexer
	frontend.lexer_init(&lexer2, file, &collector, &itable)
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer2, &collector, &itable)
	ast_file := frontend.parser_parse_file(&parser)

	if diagnostics.diag_collector_has_errors(&collector) {
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

copy_diagnostics :: proc(diags: []diagnostics.Diagnostic) -> []diagnostics.Diagnostic {
	if len(diags) == 0 {
		return nil
	}
	result := make([]diagnostics.Diagnostic, len(diags))
	for d, i in diags {
		result[i].category = d.category
		result[i].span = d.span
		result[i].message = d.message
		result[i].title = d.title
		result[i].labels = make([dynamic]diagnostics.Span_Label, len(d.labels))
		copy(result[i].labels[:], d.labels[:])
		result[i].hints = make([dynamic]string, len(d.hints))
		copy(result[i].hints[:], d.hints[:])
	}
	return result
}

package lsp

import camp ".."

analyze_document :: proc(doc: Open_Document, allocator: mem.Allocator) -> Document_Analysis {
	ctx: camp.Compilation_Context
	camp.context_init(&ctx)
	defer camp.context_destroy(&ctx)

	analysis: Document_Analysis
	analysis.diagnostics = make([dynamic]camp.LSP_Diagnostic, 0, 16)
	symbol_index_init(&analysis.symbol_idx)

	source_file: camp.Source_File
	source_file.path = doc.uri
	source_file.contents = doc.contents
	source_file.id = 0

	lexer: camp.Lexer
	camp.lexer_init(&lexer, source_file, &ctx.collector, &ctx.interner)

	parser: camp.Parser
	camp.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := camp.parser_parse_file(&parser)

	if camp.diag_collector_has_errors(&ctx.collector) {
		for d in ctx.collector.diagnostics {
			lsp_d := camp.lsp_from_diagnostic(d, doc.contents)
			append(&analysis.diagnostics, lsp_d)
		}
		analysis.symbol_idx = build_symbol_index(camp.CFile{path = doc.uri}, doc.contents, &ctx.interner)
		return analysis
	}

	cfile := camp.canonicalize(surface, &ctx)
	analysis.symbol_idx = build_symbol_index(cfile, doc.contents, &ctx.interner)

	store: camp.Type_Store
	camp.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer camp.type_store_destroy(&store)

	camp.typecheck_file(cfile, &store)

	for d in ctx.collector.diagnostics {
		lsp_d := camp.lsp_from_diagnostic(d, doc.contents)
		append(&analysis.diagnostics, lsp_d)
	}

	return analysis
}

package camp

import "core:mem"

analyze_document :: proc(text: string, file_path: string, uri: string, allocator: mem.Allocator) -> Document_Analysis {
	result: Document_Analysis
	result.diagnostics = make([dynamic]LSP_Diagnostic, 0, 16)
	symbol_index_init(&result.symbols)
	result.parse_ok = false
	result.typecheck_ok = false

	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	source := text
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
		for d in ctx.collector.diagnostics {
			lsp_diag := lsp_from_diagnostic(d, source)
			lsp_diag.message = clone_string(lsp_diag.message, allocator)
			for i in 0..<len(lsp_diag.related) {
				lsp_diag.related[i].message = clone_string(lsp_diag.related[i].message, allocator)
			}
			append(&result.diagnostics, lsp_diag)
		}
		return result
	}

	result.parse_ok = true

	context.allocator = ctx.allocator
	canon := canonicalize(ast_file, &ctx)
	context.allocator = old_allocator

	context.allocator = ctx.allocator
	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	typecheck_file(canon, &store)
	context.allocator = old_allocator

	for d in ctx.collector.diagnostics {
		lsp_diag := lsp_from_diagnostic(d, source)
		lsp_diag.message = clone_string(lsp_diag.message, allocator)
		for i in 0..<len(lsp_diag.related) {
			lsp_diag.related[i].message = clone_string(lsp_diag.related[i].message, allocator)
		}
		append(&result.diagnostics, lsp_diag)
	}

	if diag_collector_has_errors(&ctx.collector) {
		type_store_destroy(&store)
		return result
	}

	result.typecheck_ok = true

	build_symbol_index(&result.symbols, canon, uri, source, &store)

	type_store_destroy(&store)

	return result
}

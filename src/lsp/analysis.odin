package lsp

import "camp:base"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:mem"
import "core:mem/virtual"

analyze_document :: proc(
	text: string,
	file_path: string,
	uri: string,
	allocator: mem.Allocator,
) -> Document_Analysis {
	result: Document_Analysis
	result.diagnostics = make([dynamic]diagnostics.LSP_Diagnostic, 0, 16)
	symbol_index_init(&result.symbols)
	result.parse_ok = false
	result.typecheck_ok = false

	// Create individual components instead of Compilation_Context
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if err != nil {
		return result
	}
	alloc := virtual.arena_allocator(&arena)
	defer virtual.arena_destroy(&arena)

	itable: base.Intern_Table
	base.intern_init(&itable)
	defer base.intern_destroy(&itable)

	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	source := text
	file_rec := base.Source_File {
		path     = file_path,
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &collector, &itable)

	old_allocator := context.allocator
	context.allocator = alloc
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &collector, &itable)
	ast_file := frontend.parser_parse_file(&parser)
	context.allocator = old_allocator

	if diagnostics.diag_collector_has_errors(&collector) {
		for d in collector.diagnostics {
			lsp_diag := diagnostics.lsp_from_diagnostic(d, source, uri)
			lsp_diag.message = clone_string(lsp_diag.message, allocator)
			for i in 0 ..< len(lsp_diag.related) {
				lsp_diag.related[i].message = clone_string(lsp_diag.related[i].message, allocator)
			}
			append(&result.diagnostics, lsp_diag)
		}
		return result
	}

	result.parse_ok = true

	context.allocator = alloc
	canon := semantics.canonicalize(ast_file, &itable, &collector)
	context.allocator = old_allocator

	context.allocator = alloc
	store: semantics.Type_Store
	semantics.type_store_init(&store, &itable, &collector)
	defer semantics.type_store_destroy(&store)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)
	semantics.check_effect_safety(tfile, &store)
	context.allocator = old_allocator

	for d in collector.diagnostics {
		lsp_diag := diagnostics.lsp_from_diagnostic(d, source, uri)
		lsp_diag.message = clone_string(lsp_diag.message, allocator)
		for i in 0 ..< len(lsp_diag.related) {
			lsp_diag.related[i].message = clone_string(lsp_diag.related[i].message, allocator)
		}
		append(&result.diagnostics, lsp_diag)
	}

	if diagnostics.diag_collector_has_errors(&collector) {
		return result
	}

	result.typecheck_ok = true

	build_symbol_index(&result.symbols, canon, uri, source, &store)

	return result
}


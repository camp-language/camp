package camp

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:frontend"
import "camp:semantics"
import "core:testing"

parse_camp_source :: proc(source: string, ctx: ^build.Compilation_Context) -> frontend.File {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := base.Source_File {
		path     = "<test>",
		contents = source,
		id       = 0,
	}

	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := frontend.parser_parse_file(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_integration_hello_world :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := parse_camp_source("main! = || -> -[Console]-> Str { \"Hello, Camp!\" }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
	#partial switch d in file.decls[0] {
	case ^frontend.Decl_Const:
		testing.expect(t, d.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_integration_effectful_name :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := parse_camp_source("print! = 42", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
	#partial switch d in file.decls[0] {
	case ^frontend.Decl_Const:
		testing.expect(t, d.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_integration_add_function :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := parse_camp_source("add = |x: I64| -> I64 { x + 1 }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_effect_definition :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := parse_camp_source("Console! : { print!: || -> Str }", &ctx)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_multiple_decls :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	file := parse_camp_source(
		"name = \"Camp\"\nversion = 1\nmain! = || -> -[Console]-> Str { \"Hello\" }",
		&ctx,
	)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 3)
}

@(test)
test_integration_typecheck_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	alloc := build.context_init(&ctx)
	context.allocator = alloc
	defer build.context_destroy(&ctx)

	source := "x = 42\ny = x + 1"
	file_rec := base.Source_File {
		path     = "<integration>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))

	context.allocator = alloc
	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	semantics.typecheck_file(canon, &store)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_integration_typecheck_effectful :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	alloc := build.context_init(&ctx)
	context.allocator = alloc
	defer build.context_destroy(&ctx)

	source := "main! = || { 42 }"
	file_rec := base.Source_File {
		path     = "<integration>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	context.allocator = alloc
	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	semantics.typecheck_file(canon, &store)
	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_integration_typecheck_import :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	alloc := build.context_init(&ctx)
	context.allocator = alloc
	defer build.context_destroy(&ctx)

	source := "import List { map }\nx = 42"
	file_rec := base.Source_File {
		path     = "<integration>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	context.allocator = alloc
	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)
	testing.expect(t, len(canon.imports) == 1)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	semantics.typecheck_file(canon, &store)
}


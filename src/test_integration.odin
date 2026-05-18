package camp

import "core:testing"

parse_camp_source :: proc(source: string, ctx: ^Compilation_Context) -> File {
	old_allocator := context.allocator
	context.allocator = ctx.allocator
	file := Source_File{path = "<test>", contents = source, id = 0}

	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)

	result := parser_parse_file(&parser)
	context.allocator = old_allocator
	return result
}

@(test)
test_integration_hello_world :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := parse_camp_source("main! = || ->{ Console } Str { \"Hello, Camp!\" }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
	#partial switch d in file.decls[0] {
	case ^Decl_Const:
		testing.expect(t, d.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_integration_effectful_name :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := parse_camp_source("print! = 42", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
	#partial switch d in file.decls[0] {
	case ^Decl_Const:
		testing.expect(t, d.is_effectful == true)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_integration_add_function :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := parse_camp_source("add = |x: I64, y: I64| -> I64 { x + y }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_effect_definition :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := parse_camp_source("effect Console { print!: Str }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_multiple_decls :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	file := parse_camp_source("name = \"Camp\"\nversion = 1\nmain! = || ->{ Console } Str { \"Hello\" }", &ctx)
	testing.expect(t, !collector_has_errors(&ctx.collector))
	testing.expect(t, len(file.decls) == 3)
}

@(test)
test_integration_typecheck_simple :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "x = 42\ny = x + 1"
	file_rec := Source_File{path = "<integration>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	testing.expect(t, !collector_has_errors(&ctx.collector))

	context.allocator = alloc
	canon := canonicalize(surface, &ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	defer type_store_destroy(&store)

	typecheck_file(canon, &store)
	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_integration_typecheck_effectful :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "main! = || { 42 }"
	file_rec := Source_File{path = "<integration>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	context.allocator = alloc
	canon := canonicalize(surface, &ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	defer type_store_destroy(&store)

	typecheck_file(canon, &store)
	testing.expect(t, !collector_has_errors(&ctx.collector))
}

@(test)
test_integration_typecheck_import :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "import List exposing [map]\nx = 42"
	file_rec := Source_File{path = "<integration>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	context.allocator = alloc
	canon := canonicalize(surface, &ctx)
	testing.expect(t, len(canon.imports) == 1)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	defer type_store_destroy(&store)

	typecheck_file(canon, &store)
}

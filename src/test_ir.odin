package camp

import "core:testing"

lower_source :: proc(source: string) -> (IR_Module, ^Compilation_Context, Type_Store) {
	ctx: ^Compilation_Context = new(Compilation_Context)
	alloc := context_init(ctx)
	context.allocator = alloc

	file := Source_File{path = "<ir-test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)

	canon := canonicalize(surface, ctx)

	store: Type_Store
	type_store_init(&store, &ctx.interner, &ctx.collector)
	typecheck_file(canon, &store)

	mod := lower_file(canon, &store)
	return mod, ctx, store
}

teardown_lower :: proc(ctx: ^Compilation_Context, store: ^Type_Store) {
	type_store_destroy(store)
	context_destroy(ctx)
	free(ctx)
}

find_decl_fn :: proc(mod: IR_Module, is_effectful: bool) -> ^IR_Decl_Fn {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			if d.is_effectful == is_effectful {
				return d
			}
		case:
		}
	}
	return nil
}

@(test)
test_lower_int_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 42")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Literal_Int:
			testing.expect(t, expr.value == 42)
			testing.expect(t, expr.type.wasm_type == .I64)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_bool_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = true")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Literal_Bool:
			testing.expect(t, expr.value == true)
			testing.expect(t, expr.type.wasm_type == .I32)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_float_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 3.14")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Literal_Float:
			testing.expect(t, expr.type.wasm_type == .F64)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_string_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = \"hello\"")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Literal_String:
			testing.expect(t, expr.type.wasm_type == .I32)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_binop :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 1 + 2")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_BinOp:
			testing.expect(t, expr.op == .Plus)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_if :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = if true 1 else 2")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_If:
			testing.expect(t, expr.else_branch != nil)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_record :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("r = { name: \"Camp\", age: 1 }")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Construct_Record:
			testing.expect(t, len(expr.fields) == 2)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_effect_decl :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("effect IO { println: Str }")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.effect_defs) == 1)
	testing.expect(t, len(mod.effect_defs[0].operations) == 1)
}

@(test)
test_lower_effectful_const :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	fn_decl := find_decl_fn(mod, true)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, fn_decl.is_effectful == true)
	testing.expect(t, len(fn_decl.params) == 0)
}

@(test)
test_lower_lambda_as_fn :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("add = |x, y| x")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) >= 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Fn:
		testing.expect(t, len(decl.params) == 2)
		testing.expect(t, decl.is_effectful == false)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_handle :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source(
		"effect IO { println: Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found_handle := false
	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			#partial switch expr in d.body {
			case ^IR_Handle:
				found_handle = true
				testing.expect(t, len(expr.arms) == 1)
			case:
			}
		case:
		}
	}
	testing.expect(t, found_handle)
}

@(test)
test_lower_tag :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = Some(42)")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) >= 1)
	#partial switch decl in mod.decls[0] {
	case ^IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^IR_Construct_Tag:
			testing.expect(t, len(expr.payload) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_string_table :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = \"hello\"")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.string_table) >= 1)
}

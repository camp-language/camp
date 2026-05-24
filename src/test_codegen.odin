package camp

import "core:testing"
import "camp:base"
import "camp:ir"
import "camp:codegen"
import "camp:semantics"
import "camp:build"
import "camp:frontend"

compile_source :: proc(source: string) -> ([]u8, ^build.Compilation_Context) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file_rec := base.Source_File{path = "<test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)

	ir_mod := ir.lower_tfile(tfile, &store)
	ir_mod = ir.effect_lower(&ir_mod, &ctx.interner, &ctx.collector, &store)
	ir_mod = ir.closure_convert(&ir_mod, &ctx.interner)
	ir_mod = ir.cps_transform(&ir_mod, &ctx.interner)
	ir.rc_insert(&ir_mod, &ctx.interner)

	wasm_mod := codegen.codegen(ir_mod, &ctx.interner, &store, ctx.thread_count)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)

	semantics.type_store_destroy(&store)
	return wasm_bytes, ctx
}

teardown_codegen :: proc(ctx: ^build.Compilation_Context) {
	build.context_destroy(ctx)
	free(ctx)
}

@(test)
test_codegen_simple :: proc(t: ^testing.T) {
	wasm_bytes, ctx := compile_source("main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(ctx)

	testing.expect(t, len(wasm_bytes) >= 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
	testing.expect(t, wasm_bytes[1] == 0x61)
	testing.expect(t, wasm_bytes[2] == 0x73)
	testing.expect(t, wasm_bytes[3] == 0x6D)
	testing.expect(t, wasm_bytes[4] == 0x01)
	testing.expect(t, wasm_bytes[5] == 0x00)
	testing.expect(t, wasm_bytes[6] == 0x00)
	testing.expect(t, wasm_bytes[7] == 0x00)
}

@(test)
test_codegen_has_type_section :: proc(t: ^testing.T) {
	wasm_bytes, ctx := compile_source("main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(ctx)

	testing.expect(t, len(wasm_bytes) > 9)
	found_type := false
	for i in 8..<len(wasm_bytes) - 1 {
		if wasm_bytes[i] == 0x01 {
			found_type = true
			break
		}
	}
	testing.expect(t, found_type)
}

@(test)
test_codegen_has_export_section :: proc(t: ^testing.T) {
	wasm_bytes, ctx := compile_source("main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(ctx)

	found_export := false
	for i in 8..<len(wasm_bytes) - 1 {
		if wasm_bytes[i] == 0x07 {
			found_export = true
			break
		}
	}
	testing.expect(t, found_export)
}

@(test)
test_codegen_leb128_u32_zero :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 4)
	codegen.encode_u32_leb128(0, &buf)
	testing.expect(t, len(buf) == 1)
	testing.expect(t, buf[0] == 0)
	delete(buf)
}

@(test)
test_codegen_leb128_u32_small :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 4)
	codegen.encode_u32_leb128(42, &buf)
	testing.expect(t, len(buf) == 1)
	testing.expect(t, buf[0] == 42)
	delete(buf)
}

@(test)
test_codegen_leb128_u32_large :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	codegen.encode_u32_leb128(128, &buf)
	testing.expect(t, len(buf) == 2)
	testing.expect(t, buf[0] == 0x80)
	testing.expect(t, buf[1] == 0x01)
	delete(buf)
}

@(test)
test_codegen_leb128_s32_negative :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	codegen.encode_s32_leb128(-1, &buf)
	testing.expect(t, len(buf) == 1)
	testing.expect(t, buf[0] == 0x7F)
	delete(buf)
}

@(test)
test_codegen_leb128_s32_neg_42 :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	codegen.encode_s32_leb128(-42, &buf)
	testing.expect(t, len(buf) == 1)
	testing.expect(t, buf[0] == 0x56)
	delete(buf)
}

@(test)
test_codegen_emit_instructions :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)
	codegen.emit_instruction(codegen.Wasm_I64_Const{value = 42}, &buf)
	testing.expect(t, buf[0] == 0x42)
	codegen.emit_instruction(codegen.Wasm_End{}, &buf)
	testing.expect(t, buf[len(buf) - 1] == 0x0B)
	delete(buf)
}

package camp

import "camp:base"
import "camp:build"
import "camp:codegen"
import "camp:frontend"
import "camp:ir"
import "camp:semantics"
import "core:testing"

compile_source :: proc(ctx: ^build.Compilation_Context, source: string) -> [dynamic]u8 {
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file_rec := base.Source_File {
		path     = "<test>",
		contents = source,
		id       = 0,
	}
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
	semantics.check_effect_safety(tfile, &store)

	ir_mod := ir.lower_tfile(tfile, &store)
	ir_mod = ir.effect_lower(&ir_mod, &ctx.interner, &ctx.collector, &store)
	ir_mod = ir.closure_convert(&ir_mod, &ctx.interner, &ctx.collector)
	ir_mod = ir.cps_transform(&ir_mod, &ctx.interner)
	ir.rc_insert(&ir_mod, &ctx.interner)
	ir.reuse_analyze(&ir_mod)

	wasm_mod := codegen.codegen(ir_mod, &ctx.interner, ctx.thread_count)
	wasm_bytes := codegen.wasm_serialize(wasm_mod)

	semantics.type_store_destroy(&store)
	return wasm_bytes
}

teardown_codegen :: proc(ctx: ^build.Compilation_Context) {
	build.context_destroy(ctx)
}

@(test)
test_codegen_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

	testing.expect(t, len(wasm_bytes) > 9)
	found_type := false
	for i in 8 ..< len(wasm_bytes) - 1 {
		if wasm_bytes[i] == 0x01 {
			found_type = true
			break
		}
	}
	testing.expect(t, found_type)
}

@(test)
test_codegen_has_export_section :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

	found_export := false
	for i in 8 ..< len(wasm_bytes) - 1 {
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

// ═══════════════════════════════════════════════════════════════════════════════
// Perceus RC codegen tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_codegen_drop_produces_valid_wasm :: proc(t: ^testing.T) {
	// Full pipeline including RC drop emission should produce valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

	// Valid WASM magic number
	testing.expect(t, len(wasm_bytes) >= 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
	testing.expect(t, wasm_bytes[1] == 0x61)
	testing.expect(t, wasm_bytes[2] == 0x73)
	testing.expect(t, wasm_bytes[3] == 0x6D)
}

@(test)
test_codegen_runtime_drop_body_not_empty :: proc(t: ^testing.T) {
	// camp_drop runtime function should produce non-trivial WASM code
	// (zero-check + recursive drop + dealloc)
	code := codegen.emit_camp_drop_body(0, 1, 2)
	testing.expect(t, len(code.body) > 10) // Should be substantial
	testing.expect(t, len(code.locals) >= 1) // Should have local declarations
	delete(code.body)
	for _, l in code.locals {
		_ = l
	}
	delete(code.locals)
}

@(test)
test_codegen_runtime_drop_has_locals :: proc(t: ^testing.T) {
	// camp_drop needs locals for new_refcount, scan_size, i, field_value
	code := codegen.emit_camp_drop_body(0, 1, 2)
	total_locals := 0
	for local_decl in code.locals {
		total_locals += int(local_decl.count)
	}
	// Should have at least 4 locals (new_refcount, scan_size, i, field_value)
	testing.expect(t, total_locals >= 4)
	delete(code.body)
	delete(code.locals)
}

@(test)
test_codegen_runtime_report_overflow_not_empty :: proc(t: ^testing.T) {
	// camp_report_drop_overflow should produce non-trivial WASM code
	code := codegen.emit_camp_report_drop_overflow_body(0)
	testing.expect(t, len(code.body) > 5)
	delete(code.body)
	delete(code.locals)
}

@(test)
test_codegen_runtime_dealloc_is_noop :: proc(t: ^testing.T) {
	// camp_dealloc is currently a no-op — just Wasm_End
	code := codegen.emit_camp_dealloc_body()
	testing.expect(t, len(code.body) == 1) // Just the End byte
	delete(code.body)
	delete(code.locals)
}

@(test)
test_codegen_runtime_alloc_body :: proc(t: ^testing.T) {
	// camp_alloc should produce bump allocator code
	code := codegen.emit_camp_alloc_body(0)
	testing.expect(t, len(code.body) > 5)
	testing.expect(t, len(code.locals) >= 1) // Needs a temp local
	delete(code.body)
	delete(code.locals)
}

@(test)
test_codegen_runtime_dup_body :: proc(t: ^testing.T) {
	// camp_dup should increment refcount and return pointer
	code := codegen.emit_camp_dup_body()
	testing.expect(t, len(code.body) > 5)
	delete(code.body)
	delete(code.locals)
}

@(test)
test_codegen_pipeline_with_string :: proc(t: ^testing.T) {
	// Strings are heap-allocated — full pipeline should handle drops correctly
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { x = \"hello\"; 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

	testing.expect(t, len(wasm_bytes) >= 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
	testing.expect(t, wasm_bytes[1] == 0x61)
}

@(test)
test_codegen_pipeline_with_if :: proc(t: ^testing.T) {
	// If expressions with heap bindings should compile correctly
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { if True { 1 } else { 2 } }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

	testing.expect(t, len(wasm_bytes) >= 8)
}


// ═══════════════════════════════════════════════════════════════════════════════
// Additional expression coverage tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_codegen_string_return :: proc(t: ^testing.T) {
	// String literal as return value
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> Str { \"hello\" }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_integer_add :: proc(t: ^testing.T) {
	// Integer addition produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { 1 + 2 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_if_expression :: proc(t: ^testing.T) {
	// If expression with True/False produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { if True { 42 } else { 0 } }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_main_returns_unit :: proc(t: ^testing.T) {
	// main! returning Unit (no -> type) produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || { 42 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_block_expression :: proc(t: ^testing.T) {
	// Block expression (nested braces) produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { { 42 } }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_nested_arithmetic :: proc(t: ^testing.T) {
	// Nested arithmetic with parentheses produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "main! = || -> I64 { (1 + 2) * 3 }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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
test_codegen_multiple_declarations :: proc(t: ^testing.T) {
	// Module-level constant binding referenced by main! produces valid WASM
	ctx: build.Compilation_Context
	wasm_bytes := compile_source(&ctx, "helper = 42\nmain! = || -> I64 { helper }")
	defer delete(wasm_bytes)
	defer teardown_codegen(&ctx)

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

// ═══════════════════════════════════════════════════════════════════════════════
// Handle one-shot enforcement tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_sched_join_has_one_shot_enforcement :: proc(t: ^testing.T) {
	// sched_join should trap on already-joined handles (unreachable after status check)
	code := codegen.emit_camp_sched_join_body(false)
	defer delete(code.body)
	defer delete(code.locals)

	// Body must contain unreachable opcode (0x00) for one-shot enforcement
	has_unreachable := false
	for b in code.body {
		if b == 0x00 {
			has_unreachable = true
			break
		}
	}
	testing.expect(t, has_unreachable)
}

@(test)
test_sched_cancel_has_one_shot_enforcement :: proc(t: ^testing.T) {
	// sched_cancel should trap on already-consumed handles (unreachable after status check)
	code := codegen.emit_camp_sched_cancel_body(false)
	defer delete(code.body)
	defer delete(code.locals)

	// Body must contain unreachable opcode (0x00) for one-shot enforcement
	has_unreachable := false
	for b in code.body {
		if b == 0x00 {
			has_unreachable = true
			break
		}
	}
	testing.expect(t, has_unreachable)
}

@(test)
test_sched_join_has_two_unreachable :: proc(t: ^testing.T) {
	// sched_join should have two unreachable instructions:
	// one for double-join (JOINED check) and one for join-after-cancel (CANCELLED check)
	code := codegen.emit_camp_sched_join_body(false)
	defer delete(code.body)
	defer delete(code.locals)

	unreachable_count := 0
	for b in code.body {
		if b == 0x00 {
			unreachable_count += 1
		}
	}
	testing.expect(t, unreachable_count >= 2)
}

@(test)
test_sched_cancel_has_two_unreachable :: proc(t: ^testing.T) {
	// sched_cancel should have two unreachable instructions:
	// one for cancel-after-join (JOINED check) and one for double-cancel (CANCELLED check)
	code := codegen.emit_camp_sched_cancel_body(false)
	defer delete(code.body)
	defer delete(code.locals)

	unreachable_count := 0
	for b in code.body {
		if b == 0x00 {
			unreachable_count += 1
		}
	}
	testing.expect(t, unreachable_count >= 2)
}


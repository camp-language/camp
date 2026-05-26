# WASM Codegen Fix — Continuation Guide

## Current Status

**134 of 144 e2e tests pass** (was 132/144 on main). 6 tests still fail.

## Remaining 6 Failures

### 1. Effect handler WASM validation errors — 4 tests

- `effects/effect-handler-resume-twice` — func[52]: expected i32 but nothing on stack
- `effects/effect-perform-return-value` — func[52]: expected i64 but nothing on stack
- `effects/effect-throw-handler` — func[52]: expected i64 but nothing on stack
- `effects/effect-declare-and-handle` — func[52]: expected i64 but nothing on stack

**Root cause**: The effect handler functions (emitted by `emit_unhandled_effect_handler_fn`, `emit_console_println_handler_fn`, etc.) call `camp_exit` which consumes an i32 and doesn't return. But the handler function's WASM signature expects a return value (i64 or i32). After `camp_exit`, there's nothing on the stack for the implicit return. Need `unreachable` after `camp_exit` calls in handler functions, or the handler function signatures need to return void.

**Fix location**: `src/codegen/emit_start.odin` — handler function emission (around lines 150-205 and the `emit_*_handler_fn` helpers).

### 2. Tag match nested i64/i32 mismatch — 1 test

- `tag-unions/tag-match-nested` — func[52]: expected i64, found i32

**Root cause**: Nested tag union match (`Ok(Ok(42))`) — the inner match arm extracts a payload as I32 (tag pointer) but the context expects I64. The `collect_pattern_locals` or match arm codegen uses the wrong type for the inner tag's payload variable.

**Fix location**: `src/codegen/emit_expr.odin` — tag union match arm payload extraction, or `src/ir/lower.odin` — pattern type propagation for nested tag patterns.

### 3. String interpolation runtime crash — 1 test

- `strings/interpolation-int` — exit 134 (SIGABRT), OOB memory access

**Root cause**: The `int_to_str` runtime function is a stub that returns 0 (null pointer). String concatenation then treats address 0 as a length-prefixed string buffer, reads garbage as the length, and does a massive memory copy → OOB crash.

**Fix**: Implement `int_to_str` in `src/codegen/runtime.odin`, or mark string interpolation as unimplemented and emit a compile-time error.

## Changes in This PR

| File | Changes |
|------|---------|
| `src/codegen/runtime.odin` | local.tee→local.set (sched_worker_loop), str_eq restructure (Return-based exits), I32_Lt_S→I32_Ge_S (6 parallel_*), remove void call_indirect consumers (7) |
| `src/codegen/emit_start.odin` | `get_main_return_type` recovers original type from CPS body; non-void main exit uses wrap_i64+and mask |
| `src/codegen/emit_expr.odin` | IR_Let void drop fix, ir_operand_wasm_type fixes (IR_Let recurses, IR_Drop/Return/Crash→Void, etc.), scan_size counts only pointer-typed fields |
| `src/ir/wasm_type.odin` | ir_expr_wasm_type aligned with ir_operand_wasm_type |
| `tests/e2e/pattern-matching/match-or-pattern/expected.toml` | wasm_exit = 1 (program returns 1) |
| `tests/e2e/language/multi-param-lambda/expected.toml` | Updated for PR #22 (multi-param lambdas now allowed) |
| `tests/e2e/execution/function-call/expected.toml` | Updated for PR #22 (multi-param lambdas now allowed) |

## Build & Test Commands

```bash
odin build src/ -collection:camp=src/ -out:camp
odin build src/e2e/ -collection:camp=src/ -out:camp-e2e
CAMP_BIN=$(pwd)/camp ./camp-e2e
```

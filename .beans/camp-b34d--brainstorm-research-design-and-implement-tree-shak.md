---
# camp-b34d
title: Brainstorm, research, design, and implement tree shaking for WASM compilation
status: in-progress
type: feature
priority: high
created_at: 2026-06-08T04:15:52Z
updated_at: 2026-06-27T23:21:00Z
---

## Summary

Tree shaking (dead code elimination at the module/function level) removes unreachable IR declarations from compiled WASM output, reducing binary size. Camp compiles all source into WASM including stdlib; without tree shaking, every imported/referenced function emits code even when unused by the program.

## Current State

The pipeline is now:
```
Parse → Canonicalize → Typecheck → UnusedAnalysis → Mono → IR Lower → Effect Lower → Closure Convert → CPS → RC Insert → Reuse → **Tree Shake** → Codegen → WASM
```

## Implementation Status

### Completed: Phases 1-3 (IR-level tree shaking)

**New files:**
- `src/ir/call_graph.odin` — Call graph builder + `Decl_Key` type + edge walker
- `src/ir/tree_shake.odin` — Reachability (BFS), pruning, `tree_shake_module` entry point
- `src/test_tree_shake.odin` — 7 unit tests covering call graph, reachability, pruning, self-recursion, no-root skip

**Modified files:**
- `src/build/build.odin` — `ir.tree_shake_module(&combined_ir, &ctx.interner)` after `reuse_analyze`
- `src/build/project.odin` — same
- `tests/e2e/effects/effect-handler-resume-twice/expected.toml` — stack trace addresses shifted

### Design Decisions Made

1. **Pipeline insertion**: After `reuse_analyze`, before `codegen`. All IR passes run first so the call graph sees the complete program.
2. **Granularity**: Function-level. Basic-block-level is future work.
3. **Always-on**: No flag — tree shaking runs on every build. Library mode (no main!) gracefully skips.
4. **Root set**: `main!` / `main` by default. `tree_shake_module_with_tests` variant accepts test function names.
5. **pub visibility**: Not tracked in IR — not used for reachability. Only transitively reachable functions from `main!` survive.
6. **Conservative edges**: Collects IR_Call, IR_Tail_Call, IR_Closure, IR_Perform, IR_Handle, IR_Var (for closure fn_idx), and trait dispatch callback fields (ord_compare_func, eq_func, etc.).

### Key Design: `Decl_Key`

`Canonical_Name` includes `is_local` which causes spurious mismatches between `IR_Call.callee` (set during lowering) and `IR_Decl_Fn.name` (set during `combine_module_irs`). `Decl_Key` strips `is_local` for stable identity comparison.

`resolve_callee` handles `module == NO_NAME` (local calls before module assignment) by falling back to bare-name lookup.

### Completed: Phase 4 (WASM-level runtime pruning)

**New files:**
- `src/codegen/wasm_scan.odin` — WASM bytecode scanner: walks instruction stream to find `call` (0x10) opcodes and extract function indices. Handles all standard WASM opcodes including LEB128 immediates, memory ops, block types, br_table, ref.null/func, and 0xFC/0xFD prefixes.
- `src/codegen/prune_runtime.odin` — Runtime pruning: dependency graph (`Runtime_Dep_Graph`), transitive closure, always-keep set (core RC/I/O + call_indirect targets), `prune_unused_runtime_funcs` entry point.
- `src/test_wasm_scan.odin` — 10 unit tests for bytecode scanner: empty body, single call, large index, mixed instructions, false positive prevention (i32.const 16 != call 16), multiple calls, memory ops, f32 const, call_indirect.

**Modified files:**
- `src/codegen/codegen.odin` — calls `prune_unused_runtime_funcs(&mod, env.import_count)` after all code emission, before function table construction.
- All e2e snapshots updated (stack trace addresses shifted due to smaller WASM binaries).

**Approach:**
- After ALL WASM code is emitted (runtime bodies, IR bodies, _start, deferred handlers), scan every `mod.codes` entry for `call` opcodes targeting runtime function indices.
- Transitively close the dependency graph (e.g., Drop→Dealloc, List_Push→List_Grow→Alloc→Dealloc).
- Replace unused runtime function bodies with 2-byte stubs (`unreachable` + `end`).
- Functions called via `call_indirect` (compare/trampoline/debug callbacks) are conservatively kept in the always-keep set.

**Test results:** 492 unit tests pass, 178 e2e tests pass.

### Completed: WASI import pruning

**Removed dead imports:** `args_get`, `args_sizes_get`, `fd_close` — imported but never referenced by any runtime body or emit code.

**Conditional imports:** Scheduler/IO imports (`poll_oneoff`, `fd_read`, `clock_time_get`, `sched_yield`) are only emitted for effectful programs. Pure programs get 2 WASI imports (proc_exit, fd_write). Effectful programs get 6.

**Implementation:**
- Added `wasi_{poll_oneoff, fd_read, clock_time_get, sched_yield}` fields to `Codegen_Env`
- `emit_wasi_imports` takes `has_effects: bool` parameter
- Pre-scan of IR declarations determines `has_effects`
- Updated 6 runtime.odin scheduler function signatures to accept WASI import indices
- Updated `emit_console_readln_handler_fn` in emit_expr.odin to use `env.wasi_fd_read`

### Completed: Size regression tests

Added `test_size_pure_minimal` (binary < 5KB) and `test_size_import_pruning_pure` (2 WASI imports for pure programs) to `src/test_codegen.odin`.

### Not done: Function table filtering

The function table uses identity mapping (table[i] = i) with call_indirect targets stored as function indices in closures/evidence records.

After thorough analysis, conditional table population is not feasible without architectural changes:

1. The "always keep" callback functions (I64_Trampoline, Bool_Compare, I64_Debug_Trampoline) contain `call_indirect` in their bodies — they are closure callbacks that dispatch through the function table.
2. The container dispatch functions (List_Compare, Map_Eq, etc.) also contain `call_indirect` — they invoke compare/debug/hash callbacks stored in container headers.
3. Both groups must be emitted for correctness, which means `call_indirect` always exists in the emitted code, making conditional table population impossible.

A compact table (only including actual call_indirect targets with re-indexed table positions) would require changing every place that stores function indices for indirect calls (closures, evidence records, container headers, trampoline cache) to use table indices instead — ~20+ changes across emit_expr.odin, emit_start.odin, and container dispatch code. The savings would be ~300 bytes for the element section. Not worth the risk and complexity.

## Edge Cases Found During Implementation

1. **module=NO_NAME in IR_Call.callee**: Local calls have `module = NO_NAME` in the callee, but `combine_module_irs` sets `module` on declarations. `resolve_callee` handles this by falling back to bare-name lookup.
2. **Zero-valued Canonical_Name fields**: Trait dispatch fields (ord_compare_func etc.) are zero-initialized when unused. `is_no_key` checks both `NO_KEY` and zero-value.
3. **Top-level constants referenced via IR_Var**: `name_to_decl` includes both functions AND constants to catch edges like `x + y` where `x` and `y` are top-level constants.
4. **IR_Decl_Expect**: Always kept (no name, hard to attribute to a scope).

## Related Work
- `src/analysis/unused.odin` — existing unused-binding lint (operates on single CFile, no inter-module call graph)
- `src/ir/reuse.odin` — IR optimization pass pattern
- `src/ir/walk.odin` — IR walker (not used by call graph — the call graph needs edge extraction, not just child visitation)

---
# camp-b34d
title: Brainstorm, research, design, and implement tree shaking for WASM compilation
status: todo
type: feature
priority: normal
created_at: 2026-06-08T04:15:52Z
updated_at: 2026-06-08T04:15:52Z
---

## Summary

Tree shaking (dead code elimination at the module/function level) removes unreachable IR declarations from compiled WASM output, reducing binary size. Camp compiles all source into WASM including stdlib; without tree shaking, every imported/referenced function emits code even when unused by the program.

## Current State

The pipeline is:
```
Parse → Canonicalize → Typecheck → UnusedAnalysis → Mono → IR Lower → Effect Lower → Closure Convert → CPS → RC Insert → Reuse → Codegen → WASM
```

The existing `src/analysis/unused.odin` pass is a **lint-only diagnostic pass** — it emits warnings (C0900–C1099) about dead bindings, but does not influence codegen. All IR decls flow through to WASM regardless of reachability.

## Brainstorm: What Tree Shaking Means for Camp

### Entry Points
- `main!` is the obvious root
- Test entry points (`test "..." { }`) are additional roots in test mode
- Preclude: effects construct handler stacks that may reference functions implicitly

### What Can Be Shaken
- **Functions** — private fns never called from any reachable fn
- **Constants** — never referenced by reachable code
- **Types** — indirectly: if no reachable fn uses a type, its runtime metadata (vtables, RC drop fns, tag info) can be stripped
- **Effect definitions** — if no reachable fn mentions the effect, its handler dispatch tables can be stripped
- **Imports (WASM)** — WASI imports unused by reachable code

### Challenges Unique to Camp
1. **Effects create implicit call edges**: `perform Console.Println!(...)` invokes whichever handler is in scope — the compiler must track effect instantiations, not just direct calls
2. **Trait impls / generics**: monomorphization creates concrete instantiations; only reachable instantiations should be kept
3. **Closure conversion**: closures become anonymous functions; the call graph must include them
4. **Perceus RC**: drop functions and copy functions are generated per-type; only needed ones should survive
5. **Structural types**: records/tags generate runtime helpers (hash, eq, ord, debug, clone, drop, scan); unused per-type helpers should be stripped

### Where in the Pipeline
Two candidate insertion points:

**Option A: Post-CPS IR pass (recommended)**
After CPS transform, all functions are first-order (no closures remaining), all calls are direct. This is the cleanest point to build a call graph and mark reachable decls.
- Pro: complete call graph, all syntactic sugar resolved
- Con: must understand CPS calling convention; effect handlers are already lowered

**Option B: During codegen**
Check reachability on-the-fly when emitting WASM functions.
- Pro: simpler to implement incrementally
- Con: harder to get global picture; may emit dead runtime helpers

## Research Tasks

1. **Study CPS IR structure** — understand `IR_Decl_Fn`, `IR_Decl_Const`, `IR_Decl_Effect` shapes post-CPS and how they reference each other
2. **Identify all implicit edges** — RC drop/copy fns, effect handler dispatch, trait vtables, closure conversion wrappers
3. **Survey WASM tree-shaking approaches** — Binaryen `wasm-opt`, Rust/wasm-bindgen, Emscripten — what do they do that we could learn from?
4. **Measure potential savings** — build kitchen-sink and measure: total WASM size vs size of just `main!` reachable subset
5. **Runtime function table** — Camp uses `call_indirect` for some patterns; understand which functions MUST stay in the table

## Design Decisions Needed

1. **Granularity**: function-level? Basic-block-level within functions? (Start with function-level.)
2. **Opt-in or always-on?** Release mode only, or a `--tree-shake` flag?
3. **Conservative vs aggressive**: conservative = keep anything potentially reachable; aggressive = remove anything provably unreachable (harder with effects/reflection)
4. **Interaction with `pub` visibility**: keep all `pub` fns? Only `pub` fns in exported modules? What about library mode?
5. **WASM `export` section**: which functions need to remain exported (start fn, memory, table)?

## Implementation Plan (rough phases)

### Phase 1: Call Graph Builder
- Walk CPS IR, build directed graph of `IR_Decl_Fn` → `IR_Decl_Fn` edges
- Include: direct calls, effect perform→handler edges, closure invocations
- Include: RC edges (drop/copy fns referenced from type metadata)

### Phase 2: Reachability Marking
- Seed with entry points (`main!`, test fns)
- BFS/DFS from seeds to mark reachable decls
- Conservatively mark: all `pub` fns (or configurable), effect defs with any reachable use

### Phase 3: IR Pruning
- Filter `IR_Module.decls` to reachable subset
- Update indices/references
- Validate IR integrity after pruning

### Phase 4: WASM-Level Pruning
- After codegen, prune unreferenced WASM types, imports, function table entries
- Optionally integrate `wasm-opt` as post-pass

### Phase 5: Testing
- E2E tests: verify programs still work after tree shaking
- Size regression tests: assert tree-shaken output ≤ non-shaken output
- Edge cases: recursive fns, mutually recursive fns, effect handler chains

## Related Work
- `src/analysis/unused.odin` — existing unused-binding lint (may share call-graph infra)
- `src/ir/reuse.odin` — already walks IR for optimization purposes
- `src/ir/walk.odin` — IR walker infrastructure

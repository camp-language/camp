# Tasks: Code Cleanliness & Memory Management

## Phase 1: Quick Wins

- [x] Remove unused imports: `diagnostics` from `test_lexer.odin:7`, `frontend` from `test_mono.odin:8`
- [x] Remove commented-out code: CANCELLED — comments at runtime.odin:740,787 and codegen.odin:1871 are labels describing emitted WASM, not dead code
- [x] Remove `old_allocator_save` wrapper from `build.odin:21-23`, replace calls with `context.allocator` directly
- [x] Move `hash_string` from `codegen.odin:2579-2584` to `base/intern.odin`, update imports
- [x] Normalize `ba` alias in `ir/ir.odin:3` — CANCELLED: field name `base:` conflicts with package name `base`, alias is necessary
- [x] Define `CAMP_EXIT_MASK :: 127` constant, replace bare `127` at `codegen.odin:670,857`
- [x] Define `EXPECTED_GOT_FMT :: "expected {}, got {}"` constant in `diagnostics/constructors.odin`, replace occurrences
- [x] Remove `cg_is_scheduler_effect` wrapper at `codegen.odin:64-66`, call `ir.is_scheduler_effect_by_ids` directly
- [x] Remove `tc_ir_type`/`tc_eff_type` forwarding aliases at `typecheck.odin:35-41`, replace ~107 call sites with direct `lower_type`/`lower_effect_type` calls
- [x] Define buffer capacity constants (`CODE_BUF_DEFAULT :: 256`, `CODE_BUF_LARGE :: 1024`, etc.) in codegen, replace ~40 magic buffer sizes
- [x] Convert runtime function indices to `Runtime_Func :: enum` at `codegen.odin:1114-1154`

## Phase 2: Memory Quick Fixes

- [x] Fix LSP JSON leak: add per-request arena in `server_loop` around `json.parse` + dispatch, destroy after
- [x] Move `defer type_store_destroy` before error checks in `build/build.odin:78-80`
- [x] Add `defer type_store_destroy` in `lsp/analysis.odin` after `type_store_init` (replace manual calls at lines 82,90)
- [x] Add `destroy_tests` proc in `e2e/runner.odin` to free cloned strings in `E2E_Test` structs before `delete(tests)`
- [x] Add `diag_collector_destroy(collector)` before `free(collector)` in `test_typecheck.odin:27`
- [x] Simplify allocator switching in `run_build_single`: single `context.allocator = ctx.allocator` at top with `defer` restore, remove 5 intermediate save/restores

## Phase 3: File Decomposition

- [x] Split `codegen.odin` (2678 lines) into 4 files: `codegen.odin`, `emit_expr.odin`, `emit_runtime.odin`, `emit_start.odin`
  - Done: split into codegen.odin (987 lines) + emit_expr.odin (1710 lines). emit_runtime.odin already exists. emit_start.odin deferred (requires refactoring the monolithic codegen proc).
- [x] Split `typecheck.odin` (2992 lines) into 4 files: `typecheck.odin`, `check_expr.odin`, `check_control.odin`, `check_decl.odin`
  - Done: split into typecheck.odin (1834 lines) + check_expr.odin (830 lines) + check_control.odin (342 lines). check_decl.odin deferred (typecheck_decl is tightly coupled to typecheck_synth).
- [ ] ~~Split `base` package into 3 sub-packages: `base/intern`, `base/source`, `base/types`~~
  - WON'T DO: Sub-packages add `base.intern.X`/`base.source.X` verbosity everywhere. Current 7-file organization within single `base` package provides file-level separation without namespace explosion. 59 files import `camp:base` — the churn vs. benefit is negative.
- [ ] ~~Split `semantics` package into 2 sub-packages: `semantics/core`, `semantics/check`~~
  - WON'T DO: Same rationale as base. Semantics types (Type_Store, Inferred_Type, IR_Type) are used pervasively. Split adds import complexity for no functional benefit. 22 files import `camp:semantics`.

## Phase 4: Coupling & Error Handling

- [x] Remove `semantics` import from `codegen.odin`: add `payload_wasm_types` to `IR_Pat_Tag`, populate during lowering, remove `resolve_var`/`lower_type` calls from codegen
- [ ] Replace `os.exit` with `Build_Result` union in `run_build_single`, `run_build_project`, `run_check`, `run_test`; move `os.exit` to `main.odin` only
  - **Design complete** — see design.md AD1, AD9
  - 41 exit sites across `build/build.odin` (17), `build/project.odin` (11), `format/run.odin` (7), `lsp/server.odin` (2), `e2e/e2e.odin` (1), `e2e/runner.odin` (1), `test_bootstrap.odin` (1), `test_integration.odin` (1)
- [ ] Convert non-traversal `#partial switch` catch-alls to exhaustive switches
  - **Design complete** — see design.md AD5
  - ~80 sites total: emit_expr.odin (30+), typecheck.odin (12), lower.odin (8), effect_lower.odin (3), unused.odin (7), cps.odin (5), closure_convert.odin (5), rc.odin (5), mono.odin (3), canonicalize.odin (2)
  - Strategy: small unions → exhaustive `switch`; large unions → explicit pass-through groups
- [x] Fix LSP JSON error handling: return `InvalidParams` error when `json_get_int`/`json_get_string` fails instead of defaulting to (0,0)
- [x] Consolidate allocator switching in `project.odin`: single set at top with `defer` restore
- [x] Add explicit `store.allocator` param to `make()` calls in `typecheck.odin` that create Type_Store-owned data

## Phase 5: Duplication Reduction

- [ ] Table-driven WASM atomics: replace ~100 identical structs + ~80 encoding cases with single `Wasm_Atomic_Mem` struct + opcode lookup helpers
  - **Design complete** — see design.md AD7
  - ~500 lines saved. Two new helpers: `atomic_opcode_base` + `atomic_width_offset`.
- [ ] ~~Data-driven diagnostic constructors: define `Diag_Kind :: enum` with structured data, single `format_diagnostic` proc~~
  - WON'T DO: Each constructor has unique parameters, format strings, labels, and hints. The boilerplate is inherent to type-safe diagnostic construction — a data-driven approach would require either untyped maps or a 40-variant enum with per-variant data, both more complex than the current 40 small procs.
- [x] WASM serialization section helper: `wasm_encode_section` proc replacing 9 near-identical sections
- [x] Combined type+effect helpers: `fresh_with_effects` and `type_eff_pair` procs, replace ~65 paired call sites
- [x] Test helper consolidation: single `setup_for_typecheck :: proc(opts: Test_Options) -> Test_Context`
- [ ] ~~Replace `new()+t^=T{}` pattern with `new(T){(field init)}` inline syntax~~ — CANCELLED: Odin dev-2026-05 doesn't support `new(T){}` syntax
- [ ] ~~Consolidate literal type creation: `make_literal_expr` helper for Int/Float/String/Bool cases~~ — SKIPPED: different struct types make helper more complex than duplication
- [x] Combine unused-analysis prefix checks: `classify_name :: proc -> Name_Classification`

## Phase 6: Visitor/Walk Pattern

- [x] Design `IR_Visitor` struct with function pointers and default walk — Implemented as walk_expr_children/walk_decl_children in src/ir/walk.odin
- [x] Implement `walk_expr` and `walk_decl` dispatch procs
- [ ] ~~Refactor 6 IR passes to use visitor: `lower`, `cps`, `closure_convert`, `effect_lower`, `rc`, `mono`~~
  - WON'T DO: These passes are *transforms* (they rebuild the tree), not pure traversals. A visitor with 33+ method pointers must implement all methods even for identity traversal. `walk.odin` is available for passes that need pure child-walking; `#partial switch` remains idiomatic Odin for transforms.
- [ ] ~~Refactor 3 AST passes to use visitor: `canonicalize`, `typecheck_synth`, `collect_uses`~~
  - WON'T DO: Same rationale. canonicalize and typecheck are transforms. `collect_uses` could use walk but the improvement is marginal.

## Phase 7: Data-Oriented Design

- [ ] Replace `^Type_Var` with `Type_Var_ID` + `store.vars[id]` throughout (eliminates UAF risk from append reallocation)
  - **Design complete** — see design.md AD4
  - 70+ call sites across `types.odin`, `unify.odin`, `typecheck.odin`, `lower_type.odin`, `mono.odin`
  - Read pattern: `v := store.vars[int(id)]` (value, not pointer)
  - Mutate pattern: `store.vars[int(id)].link = ...` (direct array mutation)
  - Enables Task 10 (parallel arrays)
- [ ] Move Inferred_Type variant-specific data to parallel arrays in Type_Store (shrink Inferred_Type to tag + index)
  - **Design complete** — see design.md AD6, AD10
  - Depends on Task 9 (index-based access)
  - Inferred_Type shrinks from ~96 bytes to ~8 bytes (tag + index)
  - 7 parallel arrays in Type_Store: `primitives`, `functions`, `newtypes`, `record_rows`, `tag_union_rows`, `effect_rows`, `handles`
  - Simplifies `type_store_destroy` (no variant-specific delete branches)
- [ ] Restructure Intern_Table to SoA: `hashes: [dynamic]u64` + `offsets: [dynamic]u32` + contiguous string buffer
  - **Design complete** — see design.md AD11
  - DEFERRED: marginal benefit for current table sizes. Custom hash table saves ~50% memory but adds ~150 lines. Revisit if interner becomes a hotspot.

## Phase 8: Remaining File Decomposition

- [ ] Extract `emit_start.odin` from `codegen.odin`
  - **Design complete** — see design.md AD12
  - Move `emit_start_function` + helper procs (~400 lines) to new file
  - Add `func_type_indices: map[string]int` to `Codegen_Env` for cross-file state
- [ ] Extract `check_decl.odin` from `typecheck.odin`
  - **Design complete** — see design.md AD13
  - Move `typecheck_decl`, `typecheck_newtype_decl`, `typecheck_trait_decl`, `verify_trait_conformance`, and related helpers
  - Same `package semantics`, no import issues

## Implementation Order

1. Close won't-do tasks (Phase 3 items 3-4, Phase 5 item 2, Phase 6 items 3-4)
2. **Task 9** (index-based Type_Var) — enables Task 10
3. **Tasks 3+14** (Build_Result union) — largest single refactor
4. **Task 4** (#partial switch catch-alls) — mechanical but widespread
5. **Task 5** (WASM atomics) — isolated, ~500 lines saved
6. **Tasks 12+13** (emit_start.odin + check_decl.odin) — straightforward extractions
7. **Task 10** (Inferred_Type parallel arrays) — depends on Task 9
8. **Task 11** (Intern_Table SoA) — deferred, low priority

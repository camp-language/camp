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
- [ ] Split `base` package into 3 sub-packages: `base/intern`, `base/source`, `base/types`
  - DEFERRED: 59 files import camp:base, high-risk mechanical change
- [ ] Split `semantics` package into 2 sub-packages: `semantics/core`, `semantics/check`
  - DEFERRED: 22 files import camp:semantics, high-risk mechanical change

## Phase 4: Coupling & Error Handling

- [x] Remove `semantics` import from `codegen.odin`: add `payload_wasm_types` to `IR_Pat_Tag`, populate during lowering, remove `resolve_var`/`lower_type` calls from codegen
- [ ] Replace `os.exit` with `Build_Result` union in `run_build_single`, `run_build_project`, `run_check`, `run_test`; move `os.exit` to `main.odin` only — DEFERRED: significant refactor, 41 exit sites
- [ ] Convert non-traversal `#partial switch` catch-alls to exhaustive switches (~20 sites in error handling, diagnostics) — DEFERRED: pending visitor pattern
- [x] Fix LSP JSON error handling: return `InvalidParams` error when `json_get_int`/`json_get_string` fails instead of defaulting to (0,0)
- [x] Consolidate allocator switching in `project.odin`: single set at top with `defer` restore
- [x] Add explicit `store.allocator` param to `make()` calls in `typecheck.odin` that create Type_Store-owned data

## Phase 5: Duplication Reduction

- [ ] Table-driven WASM atomics: replace ~100 identical structs + ~80 encoding cases with `Atomic_Op_Info` lookup table — DEFERRED: complex, needs careful design
- [ ] Data-driven diagnostic constructors: define `Diag_Kind :: enum` with structured data, single `format_diagnostic` proc — DEFERRED: needs design review
- [x] WASM serialization section helper: `encode_section` proc replacing 9 near-identical sections
- [x] Combined type+effect helpers: `fresh_with_effects` and `type_eff_pair` procs, replace ~65 paired call sites
- [x] Test helper consolidation: single `setup_for_typecheck :: proc(opts: Test_Options) -> Test_Context`
- [ ] Replace `new()+t^=T{}` pattern with `new(T){(field init)}` inline syntax (~100+ sites) — CANCELLED: Odin dev-2026-05 doesn't support `new(T){}` syntax
- [ ] Consolidate literal type creation: `make_literal_expr` helper for Int/Float/String/Bool cases — SKIPPED: different struct types make helper more complex than duplication
- [x] Combine unused-analysis prefix checks: `classify_name :: proc -> Name_Classification`

## Phase 6: Visitor/Walk Pattern

- [x] Design `IR_Visitor` struct with function pointers and default walk — Implemented as walk_expr_children/walk_decl_children in src/ir/walk.odin
- [x] Implement `walk_expr` and `walk_decl` dispatch procs
- [ ] Refactor 6 IR passes to use visitor: `lower`, `cps`, `closure_convert`, `effect_lower`, `rc`, `mono` — DEFERRED: passes are transforms, not pure visitors; walk helpers available for future use
- [ ] Refactor 3 AST passes to use visitor: `canonicalize`, `typecheck_synth`, `collect_uses` — DEFERRED: same reason

## Phase 7: Data-Oriented Design

- [ ] Replace `^Type_Var` with `Type_Var_ID` + `store.vars[id]` throughout (eliminates UAF risk from append reallocation) — DEFERRED: 70+ call sites, needs design review
- [ ] Move Inferred_Type variant-specific data to parallel arrays in Type_Store (shrink Inferred_Type to tag + index) — DEFERRED: complex, needs design review
- [ ] Restructure Intern_Table to SoA: `hashes: [dynamic]u64` + `offsets: [dynamic]u32` + contiguous string buffer — DEFERRED: marginal benefit for small table

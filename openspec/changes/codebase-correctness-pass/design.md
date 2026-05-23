## Context

The Camp compiler has ~68 Odin source files, 7 stdlib modules, ~50 e2e tests, and a tree-sitter grammar. A full correctness audit identified ~100 issues spanning wrong WASM opcodes, broken LSP analysis, logic errors in stdlib, systematic contradictions between design docs and specs, memory leaks, duplicated logic, and misleading test names. The `e2e-test-suite-green` change is handling front-end alignment (lexer `!` absorption, paren→pipe lambda conversion, match guards, or-patterns, generic lambda syntax) but none of the correctness, safety, or doc-alignment issues.

Current state:
- 28 of ~120 e2e tests pass (the rest fail on front-end gaps being fixed by `e2e-test-suite-green`)
- Unit tests pass (`odin test src`)
- The compiler can compile simple programs to WASM
- LSP provides diagnostics but produces false "undefined name" errors for prelude types
- Design docs for language, effects, formatter, compiler, and tree-sitter use syntax that contradicts their authoritative specs

## Goals / Non-Goals

**Goals:**
- Fix all critical bugs that produce wrong output or crash the compiler
- Fix all safety bugs that are latent crash risks or spec violations
- Align all design docs with their authoritative specs (spec is truth)
- Resolve the three open design contradictions (one-type-per-module, Bool primitive, par vs all!)
- Fix stdlib logic errors and add missing `pub`/`$` conventions
- Fix systematic memory leaks (especially for long-running LSP process)
- Deduplicate copied logic to reduce maintenance burden and bug surface
- Improve e2e test quality (runtime verification, remove duplicates, fix names)
- Align tree-sitter grammar with the language spec
- Clean up test smells and dead code

**Non-Goals:**
- No new language features (match guards, or-patterns, generic lambda syntax are handled by `e2e-test-suite-green`)
- No changes to the language spec itself (specs are truth; designs must conform)
- No codegen improvements beyond bug fixes (no new optimization passes)
- No new e2e tests for features that lack them (that's a separate effort)
- No module system or import resolution changes
- No effect lowering, closure conversion, CPS, or RC algorithmic changes
- No changes to Perceus RC semantics

## Decisions

### Decision 1: One nominal type per module (Roc-style)

**Choice**: A module defines exactly one nominal type. The module name IS the type name.

**Rationale**: Camp is explicitly Roc-influenced. The one-type-per-module convention pairs with the `is`/`derives` system: when a module has one type, `derives Eq` is unambiguous, UFCS dispatch `x.eq(y)` has one candidate, and tags are naturally qualified (`@Option.Some`). The language spec already states this (§189-192). The design doc contradicts it — the design must be updated to match the spec.

**Alternative considered**: Multiple types per module (Rust-style). Rejected because it creates ambiguity for `derives` and UFCS, and the spec already chose one-type-per-module. If this decision is ever revisited, the spec must be changed first.

### Decision 2: Bool is a primitive type

**Choice**: `Bool` is a built-in primitive type. `True`/`False` are literal values, not tag constructors.

**Rationale**: The compiler already has `CExpr_Bool` as a separate AST node (not `CExpr_Tag`). The `e2e-test-suite-green` change adds explicit resolution of `True`/`False` to the prelude `Bool` primitive. Making `Bool` a newtype would create bootstrapping circularity (the typechecker uses conditionals to compare types). The spec already lists `Bool` as primitive (§13). The modules design doc contradicts it — the design must be updated.

**Alternative considered**: Bool as newtype `[True | False]`. Rejected due to bootstrapping circularity and because the implementation already chose primitive.

### Decision 3: `par` blocks are syntactic, not a desugaring to `Parallel!.all!`

**Choice**: `par { e1, e2 }` has its own lowering that spawns tasks, joins them, and constructs a tuple. It does NOT desugar to `Parallel!.all!`.

**Rationale**: `par` returns a heterogeneous tuple `(T1, T2)`. `Parallel!.all!` returns a homogeneous `List(a)`. These are fundamentally different type signatures — you cannot produce a tuple from a function that returns a list. The language spec already says `par` returns tuples (§821). The parallelism spec says `all!` returns lists (§51). Both are correct; they are separate, complementary mechanisms. The parallelism design doc must clarify this.

**Alternative considered**: Desugar `par` to `all!` and accept homogeneous-only `par`. Rejected because heterogeneous parallel evaluation is the primary use case for `par` blocks.

### Decision 4: Unused binding diagnostics as Warnings, not Errors

**Choice**: `diag_unused_binding`, `diag_unused_import`, `diag_unused_assignment`, `diag_unused_record_field` all use `.Warning` severity.

**Rationale**: Every mainstream compiler (rustc, gcc, clang, GHC) treats unused code as warnings, not errors. This is especially important during development where bindings are used temporarily or as placeholders. Camp's current `.Error` severity blocks compilation for dead code, which is overly strict and unergonomic.

**Impact**: This is a **breaking change** in behavior — programs with unused bindings will now compile successfully instead of failing. The `diag_collector_has_errors` check in build paths will no longer trigger for unused bindings.

**Alternative considered**: Keep as errors with a `--allow-unused` flag. Rejected because the default should match programmer expectations. A flag could be added later for strict mode.

### Decision 5: Use structured field for shadowed names instead of string parsing

**Choice**: Add a `shadowed_name: Intern_ID` field to the `Diagnostic` struct, set by `diag_shadow`. Unused analysis reads this field instead of parsing the diagnostic message string.

**Rationale**: The current approach in `unused_analysis.odin` extracts shadowed names by parsing the message string with `strings.index(msg, "`")`. If `diag_shadow`'s message format ever changes, this silently breaks. Structured data is robust against format changes.

**Alternative considered**: Add a separate `shadowed_names: map[Intern_ID]bool` parameter to `run_unused_analysis`. Rejected because it couples the analysis API to the collector's diagnostic order — the field approach is self-contained.

### Decision 6: Deduplicate by extracting shared utilities, not by introducing abstractions

**Choice**: Extract `is_scheduler_effect`, `fresh_id`, effect row parser, row unifiers, and span accessors into shared functions. Do NOT introduce generic interfaces, trait systems, or visitor patterns.

**Rationale**: The Odin codebase values simplicity. Shared functions with explicit parameters are more readable than abstract interfaces. The deduplication targets are small (3-4 copies each) with identical logic — a shared function is sufficient.

### Decision 7: Fix WASM opcodes with reference to the official spec

**Choice**: All WASM opcode values are verified against the [WebAssembly Specification](https://webassembly.github.io/spec/core/appendix/index-instructions.html). Missing instructions (`i64.div_s` through `i64.xor`, `i32.rem_u`) are added alongside their existing i32 counterparts.

**Rationale**: The current `i64.and` opcode `0x7B` is actually `i64.popcnt` per the spec. `i64.or` opcode `0x7C` is `i64.add`, duplicating line 430. These produce silently incorrect WASM binaries — the most dangerous kind of bug.

### Decision 8: Coordinate with `e2e-test-suite-green` on e2e test changes

**Choice**: E2E test renames (Phase 7 of the implementation plan) happen AFTER `e2e-test-suite-green` is merged, since that change modifies `.camp` file content in the same test directories.

**Rationale**: Avoid merge conflicts. The `e2e-test-suite-green` change is converting paren-lambdas to pipe-form in ~20 test files and regenerating snapshots. Renaming directories after that merge is clean; doing it before would create needless conflicts.

## Risks / Trade-offs

**[Risk] Diagnostic severity change breaks existing workflows** → Users who rely on the compiler rejecting programs with unused bindings will see different behavior. Mitigation: Document the change clearly. Add a `--strict` flag in a future change if needed.

**[Risk] Spec/design reconciliation is large and error-prone** → The language design doc has dozens of effect row syntax instances to update. Mitigation: Use systematic find-and-replace with human review of each change. The spec is the source of truth — any ambiguity resolves in its favor.

**[Risk] Memory leak fixes may change allocation patterns** → Adding `defer delete` in formatting code could affect performance if the delete triggers during hot paths. Mitigation: Formatting is not a hot path (it runs once per file). LSP is the main beneficiary of leak fixes.

**[Risk] Tree-sitter grammar changes invalidate existing parse trees** → Changing match arrow `->` to `=>` and effect row syntax means any tooling built on the current tree-sitter grammar breaks. Mitigation: The grammar is still pre-1.0. Regenerate all derived files. Coordinate with Neovim/editor plugin authors if any exist.

**[Risk] `par` as syntactic means more implementation work** → `par` needs its own lowering pass instead of desugaring to `all!`. Mitigation: `par` lowering is straightforward (spawn + join + tuple construction). The `all!` function was never a good semantic fit for `par` anyway.

**[Risk] One-type-per-module may feel restrictive** → Small utility types like `Pair(a, b)` need their own files. Mitigation: This is the Roc convention and developers adapt quickly. The module system supports re-exports for grouping.

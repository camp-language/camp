## Why

A full correctness audit revealed ~100 issues across the compiler, specs, stdlib, e2e tests, and tree-sitter grammar. Three are critical WASM codegen bugs producing wrong output, the LSP analysis path is broken (missing `inject_prelude`), the stdlib has logic errors (`Iter.singleton` always returns `None`, `List.head` crashes on non-empty lists), design docs systematically contradict their authoritative specs (wrong effect row syntax, forbidden `effect` keyword, wrong `:=` vs `:` for nominal types), the tree-sitter grammar diverges from the spec on match arrows, effect rows, and handle expressions, and there are widespread memory leaks, duplicated logic, and misleading e2e test names. The `e2e-test-suite-green` change handles front-end alignment (lexer `!`, paren→pipe lambdas, match guards, or-patterns) but does not address any of these. Fixing them now prevents building on a rotten foundation.

## What Changes

**BREAKING** — Unused binding/import/assignment diagnostics change from `.Error` to `.Warning`, meaning programs with unused bindings will now compile successfully instead of failing.

- **WASM codegen**: Fix wrong opcodes for `i64.and`/`i64.or` (currently emit `popcnt`/`add`), remove duplicate `i64.store` emitted by `f64.load`, add missing i64 instructions (`div_s/u`, `rem_s/u`, `shl`, `shr_s/u`, `xor`) and `i32.rem_u`
- **LSP**: Add missing `inject_prelude` call before typecheck in `lsp_analysis.odin`
- **Formatter**: Fix if/else copy-paste bug where both branches produce identical output
- **Build**: Propagate write errors instead of silently discarding them; fix shallow `Diagnostic_Collector` copy sharing backing arrays; replace PID-based temp file paths with unique names
- **Diagnostics**: Change unused binding/import/assignment/record-field from `.Error` to `.Warning`; fix missing closing backtick in `_` prefix hint
- **Lexer**: Add bounds check to `lexer_advance` (latent OOB crash)
- **Parser**: Fix `parser_expect` returning span of wrong token on mismatch
- **LSP protocol**: Fix related info missing URI field (spec violation); add URL-decoding to `uri_to_file_path`
- **Cache**: Make `read_u32_le`/`read_u16_le` propagate errors instead of silently returning 0
- **Stdlib**: Fix `Iter.singleton` (always returns `None`), `List.head` (crashes on non-empty), `Result.or_else` (type error), add missing `pub` on all declarations, add `$` on mutable variables, make `Option`/`Result` nominal types
- **Spec/design reconciliation**: Align all design docs with their authoritative specs — effect row syntax `->{ }` → `-[ | ]->`, remove `effect` keyword, `:=` → `:` for nominal types, `@derive` → `derives`, add `!` to effect names, fix `Self` contradiction, resolve Bool primitive vs newtype, resolve one-type-per-module vs multiple, resolve `par` tuple vs `Parallel!.all!` List
- **Tree-sitter**: Fix match arm arrow `->` → `=>`, effect row syntax `{E}` → `-[E]->`, add effect name + `in` to handle expression, fix handler arm syntax, fix record spread order, add `pub` on const decls, add `@`-prefixed tags, add guard clauses, add row variables, fix integer/float regex, remove dead keyword rules, fix transparent AST nodes, regenerate stale files
- **E2E tests**: Remove duplicate `effect-deep-handler`, add runtime verification (`wasm_exit`/`wasm_stdout`), fix misleading test names, fix tests with no `main!`, fix fragile shadowed-name string parsing in unused analysis, standardize naming conventions
- **Code quality**: Extract shared `is_scheduler_effect`, `fresh_id`, effect row parser, row unifiers; remove dead code in `rc.odin`/`test_ir.odin`; move `Generic_Ambiguous_Type` to `diag_constructors.odin`; replace bubble sorts; fix memory leaks in formatter, LSP JSON, discovery, test runner, test_codegen; fix test smells (wrong format specifiers, no-op assertions, debug prints, unused imports)

## Capabilities

### New Capabilities
- `wasm-i64-instructions`: i64 arithmetic/bitwise WASM instruction support (div, rem, shl, shr, xor) and i32.rem_u

### Modified Capabilities
- `language`: Confirm one nominal type per module, Bool is primitive, `par` blocks are syntactic (not a desugaring to `Parallel!.all!`)
- `diagnostics`: Unused binding/import/assignment/record-field severity changes from Error to Warning
- `effects`: Design doc alignment — effect row syntax, effect name `!` suffix, no `effect` keyword
- `generics-traits`: Design doc alignment — `Self` is a built-in type variable (contradicts current design)
- `compiler`: Propagate file write errors, fix WASM opcodes, fix parser span on mismatch, fix LSP analysis missing prelude
- `tree-sitter`: Grammar alignment with spec (match arrow, effect rows, handle expression, record spread, missing features)

## Impact

- **src/wasm.odin**: Opcode fixes, new instruction variants
- **src/lsp_analysis.odin**: Add `inject_prelude` call
- **src/format_expr.odin**: Fix if/else formatter
- **src/build.odin**, **src/build_project.odin**: Error propagation, allocator safety, unique temp paths
- **src/diag_constructors.odin**: Severity changes, backtick fix
- **src/lexer.odin**: Bounds check
- **src/parser.odin**: `parser_expect` span fix, dedup effect row parsers, dedup span accessors
- **src/diag_renderer_lsp.odin**: URI in related info
- **src/diag_renderer_cli.odin**: `NO_COLOR` leak, `strings_repeat` cleanup
- **src/cache.odin**: Error propagation in readers
- **src/typecheck.odin**: `find_similar_names` leak fix
- **src/unused_analysis.odin**: Replace string parsing with structured shadowed_name field
- **src/diagnostic.odin**: Move `Generic_Ambiguous_Type` out
- **src/lsp.odin**: URI handling, JSON leak
- **src/rc.odin**: Dead code removal
- **src/effect_lower.odin**, **src/codegen.odin**, **src/cps.odin**, **src/closure_convert.odin**: Shared utilities
- **src/unify.odin**: Dedup row unifiers
- **src/canonicalize.odin**: Replace bubble sorts
- **src/prelude.odin**: Dedup effect definitions
- **src/format_decl.odin**, **src/format_expr.odin**, **src/format_type.odin**, **src/format_print.odin**, **src/format_source.odin**: Memory leak fixes
- **src/discovery.odin**: Memory leak fixes
- **src/test_lexer.odin**: Allocator restoration
- **src/test_format.odin**: Format specifier fixes
- **src/test_parser.odin**: No-op assertion fixes
- **src/test_typecheck.odin**: Debug print removal
- **src/test_codegen.odin**: WASM leak fixes
- **src/test_ir.odin**: Dead code removal, fix permissive matching
- **src/test_mono.odin**: Misleading name fixes, unused variable cleanup
- **src/e2e/runner.odin**: Temp file cleanup, error-path leak fixes
- **src/module_graph.odin**: DFS color enum
- **stdlib/*.camp**: `pub`, `$`, logic fixes, nominal types
- **openspec/specs/language/design.md**: Effect row syntax, effect keyword, `:=`, `derives`, `!` on effect names, one-type-per-module, Bool primitive, `par` blocks
- **openspec/specs/formatter/design.md**: Same syntax alignment
- **openspec/specs/compiler/spec.md**: Example syntax fixes
- **openspec/specs/generics-traits/design.md**: `Self` fix
- **openspec/specs/tree-sitter/design.md**: External scanner section
- **openspec/specs/modules/design.md**: Bool newtype removal
- **openspec/specs/parallelism/spec.md**: Clarify `par` vs `all!`
- **tree-sitter/grammar.js**: Match arrow, effect rows, handle expression, handler arms, record spread, `pub`, `@` tags, guards, row variables, regex fixes, keyword cleanup
- **tree-sitter/queries/**: highlights, tags, locals updates
- **tree-sitter/test/corpus/**: Updated test cases
- **tests/e2e/**: Remove duplicate, rename misleading tests, add runtime verification

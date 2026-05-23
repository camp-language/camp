## 1. P0 Critical Bugs — Wrong Output or Crashes

- [ ] 1.1 Fix `Wasm_I64_And` opcode: change `0x7B` to `0x83` in `src/wasm.odin:482`
- [ ] 1.2 Fix `Wasm_I64_Or` opcode: change `0x7C` to `0x84` in `src/wasm.odin:484`
- [ ] 1.3 Add `Wasm_I64_Xor` (0x85), `Wasm_I64_Shl` (0x86), `Wasm_I64_Shr_S` (0x87), `Wasm_I64_Shr_U` (0x88) to `Wasm_Instruction` union and `emit_instruction` in `src/wasm.odin`
- [ ] 1.4 Add `Wasm_I64_Div_S` (0x7F), `Wasm_I64_Div_U` (0x80), `Wasm_I64_Rem_S` (0x81), `Wasm_I64_Rem_U` (0x82) to `Wasm_Instruction` union and `emit_instruction` in `src/wasm.odin`
- [ ] 1.5 Add `Wasm_I32_Rem_U` (0x70) to `Wasm_Instruction` union and `emit_instruction` in `src/wasm.odin`
- [ ] 1.6 Remove duplicate `0x37` (i64.store) emission in `Wasm_F64_Load` case (`src/wasm.odin:550-552`), keeping only the correct `0x2B` opcode
- [ ] 1.7 Add `inject_prelude(&store)` before `typecheck_file(canon, &store)` in `src/lsp_analysis.odin:50`
- [ ] 1.8 Fix formatter if/else copy-paste bug: make the `else` branch format inline (no braces) in `src/format_expr.odin:354-366`
- [ ] 1.9 Fix shallow `Diagnostic_Collector` copy in `compile_test_canon` (`src/build.odin:448`) — use pointer or avoid sharing
- [ ] 1.10 Add `diag_file_write_failed` constructor to `src/diag_constructors.odin` and propagate write errors in `src/build.odin:104` and `src/build_project.odin:195`
- [ ] 1.11 Fix `Iter.singleton` logic bug: move `consumed = True` into the else branch and add `$` prefix to mutable variable in `stdlib/Iter.camp:10-15`
- [ ] 1.12 Fix `List.head` crash on non-empty lists: replace `crash` with match returning `Some(h)` in `stdlib/List.camp:25-27`
- [ ] 1.13 Fix `Result.or_else` type error: change return type from `Result(a, e)` to `Result(a, e | f)` in `stdlib/Result.camp:23`
- [ ] 1.14 Investigate compiler SIGSEGV on `generic-list-map` (exit=11): run under debugger, identify null deref, produce clean error instead of crash
- [ ] 1.15 Verify: `odin test src` passes and `just test-e2e` passes after Phase 1

## 2. P1 Safety Bugs — Latent Crashes & Spec Violations

- [ ] 2.1 Add bounds check to `lexer_advance` in `src/lexer.odin:56-60`: return 0 when `l.pos >= len(l.source)`
- [ ] 2.2 Fix `parser_expect` span: save `p.current.span` before calling `parser_advance` on mismatch in `src/parser.odin:53-60`
- [ ] 2.3 Add `LSP_Location` struct with `uri` and `range` fields; change `LSP_DiagnosticRelatedInfo.location` from `LSP_Range` to `LSP_Location` in `src/diag_renderer_lsp.odin:22-25`
- [ ] 2.4 Update `lsp_from_diagnostic` to populate URI in related info locations
- [ ] 2.5 Change `diag_unused_binding`, `diag_unused_record_field`, `diag_unused_import`, `diag_unused_assignment` from `.Error` to `.Warning` in `src/diag_constructors.odin:329-375`
- [ ] 2.6 Add closing backtick to `_` prefix hint in `diag_unused_binding` (`src/diag_constructors.odin:332`)
- [ ] 2.7 Replace PID-based temp file paths with unique names using atomic counter in `src/build.odin:477-480`
- [ ] 2.8 Change `read_u32_le`/`read_u16_le` return types to `Option(u32)`/`Option(u16)` and update call sites in `src/cache.odin:312-332`
- [ ] 2.9 Add `defer context.allocator = old_allocator` in `lex_all` in `src/test_lexer.odin:5-20`
- [ ] 2.10 Fix memory leak in `discover_tests` error paths: free `expected_path`/`main_camp_path` before `continue` in `src/e2e/runner.odin:66-79`
- [ ] 2.11 Add URL-decoding and Windows path handling to `uri_to_file_path` in `src/lsp.odin:216-221`
- [ ] 2.12 Verify: `odin test src` passes after Phase 2

## 3. P2 Spec/Design Reconciliation

- [ ] 3.1 In `openspec/specs/language/design.md`: replace all `->{ Eff }` effect row syntax with `-[Eff]->` throughout
- [ ] 3.2 In `openspec/specs/language/design.md`: replace all `effect Name { }` with `Name! : { }` throughout
- [ ] 3.3 In `openspec/specs/language/design.md`: replace all `:=` with `:` for nominal types, add `@` prefix
- [ ] 3.4 In `openspec/specs/language/design.md`: replace all `@derive` with `derives`
- [ ] 3.5 In `openspec/specs/language/design.md`: add `!` suffix to all effect names in type signatures and examples
- [ ] 3.6 In `openspec/specs/language/design.md`: remove "multiple types per module" — align with spec's one-type-per-module rule
- [ ] 3.7 In `openspec/specs/generics-traits/design.md:100`: fix `Self` description — `Self` IS a built-in type variable
- [ ] 3.8 In `openspec/specs/formatter/design.md:145-181`: apply same syntax fixes as 3.1-3.4 (effect rows, effect keyword, `:=`, `derives`)
- [ ] 3.9 In `openspec/specs/compiler/spec.md:15,42,51,69`: rewrite examples using spec-compliant Camp syntax
- [ ] 3.10 In `openspec/specs/tree-sitter/design.md:111-117`: update "No External Scanner" section to document existing string interpolation scanner
- [ ] 3.11 In `openspec/specs/modules/design.md:222-227`: remove Bool newtype definition, note Bool is primitive per language spec
- [ ] 3.12 In `openspec/specs/parallelism/spec.md` and `design.md`: clarify that `par` blocks are syntactic (return tuples) and `Parallel!.all!` is a library function (returns lists) — separate, complementary mechanisms
- [ ] 3.13 Verify: no `grep` hits for `->{ ` as effect row syntax in any design doc; no `effect ` keyword; no `:=` for nominal types

## 4. P3 Stdlib Correctness

- [ ] 4.1 Add `pub` to all top-level declarations in `stdlib/Bool.camp` (2 functions)
- [ ] 4.2 Add `pub` to all top-level declarations in `stdlib/Int.camp` (4 functions)
- [ ] 4.3 Add `pub` to all top-level declarations in `stdlib/Iter.camp` (~18 declarations)
- [ ] 4.4 Add `pub` to all top-level declarations in `stdlib/List.camp` (6 functions)
- [ ] 4.5 Add `pub` to all top-level declarations in `stdlib/Option.camp` (1 type + 5 functions)
- [ ] 4.6 Add `pub` to all top-level declarations in `stdlib/Result.camp` (1 type + 7 functions)
- [ ] 4.7 Add `pub` to all top-level declarations in `stdlib/Str.camp` (4 functions)
- [ ] 4.8 Add `$` prefix to all mutable variables in `stdlib/Iter.camp` (consumed, list, acc, cur, remaining, index)
- [ ] 4.9 Change `Option : <a> [Some(a) | None]` to `@Option : <a> [Some(a) | None]` in `stdlib/Option.camp:1`
- [ ] 4.10 Change `Result : <a, e> [Ok(a) | Err(e)]` to `@Result : <a, e> [Ok(a) | Err(e)]` in `stdlib/Result.camp:1`
- [ ] 4.11 Add TODO comments to `stdlib/Int.camp` for missing integer type variants
- [ ] 4.12 Add TODO comments to `stdlib/Str.camp` noting `eq` should derive Eq
- [ ] 4.13 Verify: code review confirms all `pub` and `$` additions are correct

## 5. P4 Memory Leaks

- [ ] 5.1 Add `defer delete(parts)` after every `parts: [dynamic]Doc` in `src/format_decl.odin`
- [ ] 5.2 Add `defer delete(parts)` after every `parts: [dynamic]Doc` in `src/format_expr.odin`
- [ ] 5.3 Add `defer delete(parts)` after every `parts: [dynamic]Doc` in `src/format_type.odin`
- [ ] 5.4 Add `defer strings.builder_destroy(&b)` in `doc_newline_with_indent` in `src/format_print.odin:76-83`
- [ ] 5.5 Fix `format_source.odin:212-216`: use `[dynamic]Comment_Info` with `append` instead of reallocating slices
- [ ] 5.6 Free JSON parse results after dispatching in `src/lsp.odin:34`
- [ ] 5.7 Fix `find_similar_names` leak: change return type to `[dynamic]string`, add `defer delete` at every call site in `src/typecheck.odin:94-107`
- [ ] 5.8 Add `defer delete(expected_path)` and `defer delete(main_camp_path)` with proper scope in `src/e2e/runner.odin:66-79`
- [ ] 5.9 Add temp file/directory cleanup in `src/e2e/runner.odin` (defer `os.remove` for stdout/stderr paths and test tmp dirs)
- [ ] 5.10 Add `defer delete(wasm_bytes)` in `src/test_codegen.odin` tests
- [ ] 5.11 Add `defer delete(path)` for `filepath.join` results in `src/discovery.odin:53-66,148`
- [ ] 5.12 Verify: `odin test src` passes after Phase 5

## 6. P5 Code Deduplication

- [ ] 6.1 Extract `is_scheduler_effect_by_ids` to a shared location; update `effect_lower.odin:31-40` and `codegen.odin:60-69` to call it
- [ ] 6.2 Create `src/fresh.odin` with `Fresh_State` struct and `fresh_id` proc; update `effect_lower.odin`, `cps.odin`, `closure_convert.odin` to use it
- [ ] 6.3 Merge `parser_parse_effect_row_type` and `parser_parse_effect_row_type_brace` in `src/parser.odin:1394-1526` into one function with a `terminator` parameter
- [ ] 6.4 Extract common row unification pattern into a shared helper; refactor `unify_effect_rows`, `unify_record_rows`, `unify_tag_union_rows` in `src/unify.odin:203-485`
- [ ] 6.5 Merge `expr_span_start` and `right_span_end` into a single `expr_span` with a selector parameter in `src/parser.odin:68-132`
- [ ] 6.6 Remove `RC_Var_Info` struct (lines 5-7) and `insert_dups` function (lines 168-278) from `src/rc.odin`
- [ ] 6.7 Remove dead code from `src/test_ir.odin`: `full_pipeline_source` (line 1443), `make_midend_ctx`/`teardown_midend` (lines 276-286), `find_closure_in_expr` (line 925)
- [ ] 6.8 Move `Generic_Ambiguous_Type` from `src/diagnostic.odin:183-187` to `src/diag_constructors.odin` and rename to `diag_ambiguous_type`; update call sites
- [ ] 6.9 Replace bubble sorts in `src/canonicalize.odin:886-914` with `sort.sort` or shared sort helper
- [ ] 6.10 Deduplicate `inject_prelude_effects_typecheck` and `inject_prelude_effects_lower` in `src/prelude.odin:102-329` by extracting shared effect data table
- [ ] 6.11 Replace manual loop in `copy_dynamic_bytes` (`src/wasm.odin:3-9`) with `copy(result, buf[:])`
- [ ] 6.12 Verify: `odin build src -out:camp` and `odin test src` pass after Phase 6

## 7. P6 E2E Test Quality

- [ ] 7.1 Remove duplicate test `tests/e2e/effects/effect-deep-handler/` (identical to `effect-perform-return-value`)
- [ ] 7.2 Add `wasm_exit = 0` and `wasm_stdout = "..."` to all compiling e2e tests' `expected.toml` files, starting with `pattern-matching/match-bool/`
- [ ] 7.3 Fix tests with no `main!`: add entry point to `effect-multiple-effects` and `effect-multiple-operations` in `tests/e2e/effects/`
- [ ] 7.4 Fix fragile shadowed-name string parsing: add `shadowed_name: Intern_ID` field to `Diagnostic` struct in `src/diagnostic.odin`, set it in `diag_shadow` in `src/diag_constructors.odin`, read it in `src/unused_analysis.odin:768-784`
- [ ] 7.5 Add `just clean` recipe to `justfile` to remove stale `.wasm` files and temp artifacts
- [ ] 7.6 Standardize string test naming: rename `string-interpolation` → `interpolation-basic` in `tests/e2e/strings/`
- [ ] 7.7 Rename misleading e2e test directories (coordinate AFTER `e2e-test-suite-green` is merged): identity-function, generic-pair, generic-with-constraint, generic-function-compose, wrong-arity-annotation, apply-non-function, arity-mismatch, recursive-type-error, missing-else, string-literal, string-concat, string-print
- [ ] 7.8 Verify: `just test-e2e` passes with runtime verification

## 8. P7 Tree-sitter Grammar Alignment

- [ ] 8.1 Change match arm arrow from `"->"` to `"=>"` in `grammar.js:382`; update test corpus files
- [ ] 8.2 Replace `effect_annotation` (`{E}`) with `effect_row` (`-[E | E]->`) in `grammar.js:320-324,485-490`; update `function_type` to use `optional(effect_row)` before `->`
- [ ] 8.3 Add `field("effect", $.type_identifier)` and `"in"` to `handle_expression` in `grammar.js:386-393`
- [ ] 8.4 Rewrite `handler_arm` in `grammar.js:397-406` to use dot-lambda prefix, `!` support, multiple params, and `=>` arrow
- [ ] 8.5 Fix record spread order in `grammar.js:337-342`: allow spread before fields
- [ ] 8.6 Add `optional("pub")` to `const_declaration` in `grammar.js:52-59`
- [ ] 8.7 Add `optional("@")` to `tag_expression` and `tag_pattern` in `grammar.js:251-254,441-444`
- [ ] 8.8 Add guard clause support: `optional(seq("if", field("guard", $._expression)))` in `match_arm` in `grammar.js:379-383`
- [ ] 8.9 Add row variables `..rest` to `tag_union_type` and `record_type` in `grammar.js:492-516`
- [ ] 8.10 Add `..` rest pattern to `record_pattern` in `grammar.js:452-456`
- [ ] 8.11 Add type parameters to `alias_declaration` in `grammar.js:100-105`
- [ ] 8.12 Fix integer regex to disallow leading zeros and trailing underscores in `grammar.js:208`
- [ ] 8.13 Fix float regex to disallow trailing underscores in `grammar.js:210`
- [ ] 8.14 Add `derives` and `pub` to reserved keywords; add `!` support in effect operation names
- [ ] 8.15 Remove or use 22 dead keyword rules in `grammar.js:596-617`
- [ ] 8.16 Fix transparent `type_variable` and `type_annotation` using `alias()` in `grammar.js:530,532`
- [ ] 8.17 Update `highlights.scm`: fix interpolated_string capture, add missing keyword highlights
- [ ] 8.18 Update `tags.scm`: add `newtype_declaration`
- [ ] 8.19 Update `locals.scm`: add lambda parameters and for-loop variables
- [ ] 8.20 Regenerate stale files: `just tree-sitter-generate`
- [ ] 8.21 Align tree-sitter binding dependency versions across `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`
- [ ] 8.22 Verify: `just lint-tree-sitter` passes

## 9. P8 Minor/Style Cleanup

- [ ] 9.1 Replace all `%d` and `%q` with `{}` in `src/test_format.odin` `testing.expectf` calls (~70 occurrences)
- [ ] 9.2 Replace `testing.expect(t, true)` with actual structural assertions in `src/test_parser.odin:94,142,231,252`
- [ ] 9.3 Remove debug print loop in `src/test_typecheck.odin:547-549`
- [ ] 9.4 Remove unused imports: `core:strings` from `test_typecheck.odin:4`, `core:mem` from `test_codegen.odin:4`, `core:fmt` from `test_mono.odin:3` and `test_modules.odin:3`
- [ ] 9.5 Fix misleading mono test names in `src/test_mono.odin:56,82,142`
- [ ] 9.6 Fix `find_decl_fn` and `find_decl_fn_by_name` to use exact equality instead of `has_prefix` in `src/test_ir.odin:37,1456`
- [ ] 9.7 Fix inconsistent indentation in `src/test_ir.odin:522,987`
- [ ] 9.8 Add `DFS_Color` enum to replace magic numbers 0/1/2 in `src/module_graph.odin:120-186`
- [ ] 9.9 Fix `check_immutable_binding` return value being ignored in `src/unused_analysis.odin:624`; add TODO comment for empty pointless-evaluation check body at line 648-656
- [ ] 9.10 Add `defer delete(no_color_val, context.allocator)` in `src/diag_renderer_cli.odin:18`
- [ ] 9.11 Fix `strings_repeat` in `src/diag_renderer_cli.odin:214-221`: rename to `char_repeat` or implement proper string repetition
- [ ] 9.12 Fix O(n²) string concatenation in `src/diag_renderer_lsp.odin:47`: use `strings.Builder`
- [ ] 9.13 Verify: `odin test src` passes after Phase 9

## 10. Final Validation

- [ ] 10.1 Run `odin build src -out:camp` — compiles without warnings
- [ ] 10.2 Run `odin test src` — all unit tests pass
- [ ] 10.3 Run `just test-e2e` — all e2e tests pass
- [ ] 10.4 Run `just lint-tree-sitter` — grammar valid
- [ ] 10.5 Run `just test` — full suite green

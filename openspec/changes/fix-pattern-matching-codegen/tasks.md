# Tasks: fix-pattern-matching-codegen

## 1. IR Extensions
- [x] 1.1 Add `IR_Pat_Bool`, `IR_Pat_Int`, `IR_Pat_String` to `IR_Pattern` union in `src/ir.odin`
- [x] 1.2 Add `string_table` field population for string patterns in `src/lower.odin` `lower_tpattern()`

## 2. Tag Index Resolution
- [x] 2.1 Add `resolve_tag_index()` in `src/lower.odin`
- [x] 2.2 Update `lower_ttag()` to call `resolve_tag_index()`
- [x] 2.3 Update `lower_tlist()` to call `resolve_tag_index()` for Nil/Cons tag indices

## 3. Literal Pattern Lowering
- [x] 3.1 Update `lower_tpattern()` to create `IR_Pat_Bool`, `IR_Pat_Int`, `IR_Pat_String`

## 4. WASM Encoding Fixes
- [x] 4.1 Fix `Wasm_Memory_Copy` in `src/wasm.odin`: append `0x00 0x00` memidx bytes
- [x] 4.2 Fix `emit_camp_list_push_body()` in `src/runtime.odin`: remove redundant load, reorder address computation

## 5. Codegen Env Extensions
- [x] 5.1 Add `local_types` and `store` to `Codegen_Env` in `src/codegen.odin`
- [x] 5.2 Set `env.store = &ctx.type_store` in `codegen()` initialization
- [x] 5.3 Populate `env.local_types` in Camp function local collection
- [x] 5.4 Populate `env.local_types` in _start function local collection
- [x] 5.5 Add `delete(env.local_types)` cleanup

## 6. _start Function Fix
- [x] 6.1 Set `env.tmp_local_base = 0` and `env.tmp_count = 0` before _start
- [x] 6.2 Initialize `env.locals` before _start non-effectful main path
- [x] 6.3 Include `env.locals` in _start's final `start_locals` declarations

## 7. Type-Aware Match Codegen
- [x] 7.1 Add `Match_Kind` enum and `determine_match_kind()` helper
- [x] 7.2 Implement Bool match: nested if/else with `i32.eq`
- [x] 7.3 Implement Int match: allocate i64 scrutinee local, nested if/else with `i64.eq`
- [x] 7.4 Implement String match: nested if/else with `camp_str_eq` runtime call
- [x] 7.5 Fix tag union match payload load: use `emit_load_for_type`

## 8. Exhaustiveness & Redundancy Checking
- [x] 8.1 Extend `collect_covered_tags()` for Bool, Int, String, nested patterns
- [x] 8.2 Add Bool exhaustiveness check in `typecheck_match()`
- [x] 8.3 Add Int/String exhaustiveness note
- [x] 8.4 Add `all_tags_covered` tracking and `diag_redundant_pattern` warning
- [x] 8.5 Add `diag_redundant_pattern()` constructor in `src/diag_constructors.odin`

## 9. E2E Test Fixes
- [x] 9.1 Fix match arm syntax: `->` to `=>` in tag-union test files
- [x] 9.2 Fix type annotation syntax: add brackets around tag union types in test files
- [x] 9.3 Regenerate `expected.toml` snapshots

## 10. Validation
- [x] 10.1 Run `odin test src` — all unit tests pass
- [x] 10.2 Run `just test-e2e` — all e2e tests pass
- [x] 10.3 Compile match-bool test and validate with wasmtime
- [x] 10.4 Compile tag-match-simple test and validate with wasmtime

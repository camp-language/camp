## 1. IR Extensions

- [ ] 1.1 Add `IR_Pat_Bool { value: bool }`, `IR_Pat_Int { value: i64 }`, `IR_Pat_String { string_id: Intern_ID }` to `IR_Pattern` union in `src/ir.odin`
- [ ] 1.2 Add `string_table` field population for string patterns in `src/lower.odin` `lower_tpattern()` — when lowering `CPattern_String`, add entry to string table and store its ID in `IR_Pat_String.string_id`

## 2. Tag Index Resolution

- [ ] 2.1 Add `resolve_tag_index()` in `src/lower.odin` that resolves a tag union type, follows newtype chains via `inner_id`, and finds the positional index of a tag name within `tag_entries`
- [ ] 2.2 Update `lower_ttag()` in `src/lower.odin` to call `resolve_tag_index()` instead of hardcoding `0`
- [ ] 2.3 Update `lower_tlist()` in `src/lower.odin` to call `resolve_tag_index()` for Nil/Cons tag indices

## 3. Literal Pattern Lowering

- [ ] 3.1 Update `lower_tpattern()` in `src/lower.odin` to create `IR_Pat_Bool` for `CPattern_Bool`, `IR_Pat_Int` for `CPattern_Int`, `IR_Pat_String` for `CPattern_String` instead of discarding as `IR_Pat_Var(Intern_ID(0))`

## 4. WASM Encoding Fixes

- [ ] 4.1 Fix `Wasm_Memory_Copy` in `src/wasm.odin`: append `0x00 0x00` (two memidx bytes) after `0xFC 0x0A`
- [ ] 4.2 Fix `emit_camp_list_push_body()` in `src/runtime.odin`: remove redundant initial `local.get 0; i32.load 0`, reorder address computation to `data_ptr + len * 8`

## 5. Codegen Env Extensions

- [ ] 5.1 Add `local_types: map[Intern_ID]IR_Type` and `store: ^Type_Store` to `Codegen_Env` in `src/codegen.odin`
- [ ] 5.2 Set `env.store = &ctx.type_store` in `codegen()` initialization
- [ ] 5.3 Populate `env.local_types` in Camp function local collection (alongside `env.local_map`)
- [ ] 5.4 Populate `env.local_types` in _start function local collection
- [ ] 5.5 Add `delete(env.local_types)` cleanup alongside `delete(env.local_map)`

## 6. _start Function Fix

- [ ] 6.1 Set `env.tmp_local_base = 0` and `env.tmp_count = 0` before emitting _start function body
- [ ] 6.2 Initialize `env.locals = make([dynamic]Wasm_Local_Decl, 0, 8)` before _start non-effectful main path
- [ ] 6.3 Include `env.locals` (dynamically-added during emit_expr) in _start's final `start_locals` declarations

## 7. Type-Aware Match Codegen

- [ ] 7.1 Add `Match_Kind` enum (`Tag_Union`, `Bool`, `Int`, `String`) and `determine_match_kind()` helper in `src/codegen.odin`
- [ ] 7.2 Implement Bool match: nested `if/else` with `i32.eq`, `scrutinee_local` at `tmp_local_base + 2`, `result_block_type` from `e.type.wasm_type`
- [ ] 7.3 Implement Int match: allocate i64 scrutinee local via `append(&env.locals, ...)`, nested `if/else` with `i64.eq`
- [ ] 7.4 Implement String match: nested `if/else` with `camp_str_eq` runtime call, `env.string_offsets` for pattern data offsets
- [ ] 7.5 Fix tag union match payload load: replace `Wasm_I32_Load` with `emit_load_for_type(payload_type.wasm_type, buf)` where payload_type comes from `env.local_types[payload_name]`

## 8. Exhaustiveness & Redundancy Checking

- [ ] 8.1 Extend `collect_covered_tags()` in `src/typecheck.odin` to handle `CPattern_Bool` (track true/false), `CPattern_Int`/`CPattern_String` (infinite, don't saturate), and recurse into `CPattern_Tag.payload` and `CPattern_Destructure.inner`
- [ ] 8.2 Add Bool exhaustiveness check in `typecheck_match()`: if scrutinee is Bool and both true/false not covered, error
- [ ] 8.3 Add Int/String exhaustiveness note: if scrutinee is Int/String and no wildcard, issue a note (not error, since infinite)
- [ ] 8.4 Add `all_tags_covered` tracking and `diag_redundant_pattern` warning in `src/typecheck.odin`
- [ ] 8.5 Add `diag_redundant_pattern()` constructor in `src/diag_constructors.odin` with `.Warning` category

## 9. E2E Test Fixes

- [ ] 9.1 Fix match arm syntax: `->` to `=>` in tag-union test files
- [ ] 9.2 Fix type annotation syntax: add brackets around tag union types in test files
- [ ] 9.3 Regenerate `expected.toml` snapshots with `just update-snapshots`

## 10. Validation

- [ ] 10.1 Run `odin test src` — all unit tests pass
- [ ] 10.2 Run `just test-e2e` — all e2e tests pass
- [ ] 10.3 Compile match-bool test and validate with wasmtime — exits with correct code
- [ ] 10.4 Compile tag-match-simple test and validate with wasmtime — exits with correct code

## Why

Pattern matching in Camp compiles but produces invalid WASM at runtime. Tag union dispatch always jumps to arm 0 (tag_index hardcoded), Bool/Int/String pattern matching generates wrong code (literal values discarded, wrong WASM types), the `_start` function doesn't allocate enough locals for match temporaries, and tag payload loads always use i32.load even for i64 fields. Additionally, several pre-existing WASM encoding bugs (memory.copy missing memidx bytes, list_push stack imbalance) cause ALL compiled programs to fail WASM validation.

## What Changes

- Fix `tag_index` always 0 in `IR_Construct_Tag` — add `resolve_tag_index()` to `lower.odin` that looks up tag position within the union's `tag_entries`
- Add `IR_Pat_Bool`, `IR_Pat_Int`, `IR_Pat_String` to `IR_Pattern` union so literal patterns survive lowering instead of being discarded as `IR_Pat_Var(dummy)`
- Implement type-aware match codegen in `codegen.odin` — Bool match uses nested `if/else` with `i32.eq`, Int match uses `i64.eq`, String match uses `str_eq`, tag union match uses `brtable` dispatch
- Fix `_start` function: set `tmp_local_base = 0`, include dynamically-added locals (e.g. i64 scrutinee for Int match) in local declarations
- Add `local_types` map to `Codegen_Env` so tag union match payload loads use `emit_load_for_type` instead of hardcoded `Wasm_I32_Load`
- Fix `Wasm_Memory_Copy` encoding: append `0x00 0x00` memidx bytes after `0xFC 0x0A`
- Fix `camp_list_push` stack imbalance: remove redundant `i32.load` at start, reorder to compute address correctly
- Extend exhaustiveness checking in `typecheck.odin` to handle `CPattern_Bool`, `CPattern_Int`, `CPattern_String`, nested patterns, and redundancy warnings
- Add `diag_redundant_pattern()` warning constructor
- Fix e2e test syntax: `->` to `=>` for match arms, `[Ok(I64) | Error(I64)]` bracket syntax

## Capabilities

### New Capabilities

- `match-literal-codegen`: Correct WASM code generation for Bool, Int, and String literal pattern matching (nested if/else with type-aware comparisons)

### Modified Capabilities

- `compiler`: Fix tag_index assignment, _start function local setup, memory.copy encoding, list_push stack balance, tag payload load type awareness
- `language`: Extend exhaustiveness checking to Bool/Int/String patterns and nested destructuring; add redundant pattern warning

## Impact

- `src/ir.odin` — IR_Pattern union, IR_Construct_Tag
- `src/lower.odin` — resolve_tag_index(), lower_tpattern() for literals
- `src/codegen.odin` — Codegen_Env (local_types, store), match codegen, _start function, collect_locals, string data segments
- `src/typecheck.odin` — collect_covered_tags(), typecheck_match()
- `src/diag_constructors.odin` — diag_redundant_pattern()
- `src/wasm.odin` — Wasm_Memory_Copy encoding
- `src/runtime.odin` — camp_list_push, camp_list_alloc, camp_str_concat (call indices), scheduler stubs
- `tests/e2e/` — Syntax fixes in tag-union and pattern-matching tests

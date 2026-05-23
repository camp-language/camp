## Context

The Camp compiler's pattern matching is broken across the entire pipeline. The lowering phase discards literal pattern values (Bool/Int/String), the codegen phase hardcodes `tag_index = 0` for all tag constructors, the `_start` function doesn't allocate temporaries for match expressions, and tag payload loads use `i32.load` even for `i64` fields. Pre-existing WASM encoding bugs (missing memidx in `memory.copy`, `list_push` stack imbalance) make ALL compiled programs fail WASM validation.

Current compiler pipeline: Parse → Canonicalize → Typecheck → Monomorphize → Lower → Effect Lower → Closure Convert → CPS → RC Insert → Codegen

Key type layout constants:
- `CAMP_TAG_HEADER_SIZE = 8`, `CAMP_TAG_TAG_OFFSET = 4` (byte offset for discriminant), `CAMP_TAG_FIELDS_OFFSET = 8`
- Tag fields are 8-byte aligned slots; i32 values stored with `i32.store`, i64 values with `i64.store`
- Bool is `IR_Literal_Bool` (i32 0/1), Int is `IR_Literal_Int` (i64), String is `IR_Literal_String` (i32 pointer)

## Goals / Non-Goals

**Goals:**
- All pattern matching compiles to valid WASM that passes wasmtime validation
- Bool match generates correct nested `if/else` with `i32.eq`
- Int match generates correct nested `if/else` with `i64.eq`
- String match generates correct nested `if/else` with `str_eq` call
- Tag union match dispatches to the correct arm based on tag discriminant
- Tag payload fields loaded with correct type-aware instruction (`i32.load` vs `i64.load`)
- Exhaustiveness checking covers Bool, Int, String, nested patterns
- Redundant wildcard patterns produce warnings
- Pre-existing WASM encoding bugs fixed so all programs validate

**Non-Goals:**
- Optimizing match dispatch (e.g., perfect hash, decision trees) — nested if/else is sufficient
- Match on float types
- Guard clauses in match arms (already partially supported)
- Or-patterns in match (already partially supported)

## Decisions

### Decision 1: Add IR_Pat_Bool, IR_Pat_Int, IR_Pat_String to IR_Pattern

**Choice**: Extend the `IR_Pattern` union with three new variants rather than encoding literals as variable bindings.

**Rationale**: The current lowering converts `CPattern_Bool(value)` to `IR_Pat_Var(Intern_ID(0))`, discarding the literal value. The codegen then treats it as a catch-all variable. New variants preserve the literal value through the lowering → codegen pipeline.

**Alternative**: Encode literal patterns as tag patterns (e.g., `true` → `True` tag in a `[True | False]` union). Rejected because it requires reifying Bool as a tag union in the IR, which doesn't match the language semantics where Bool is a primitive i32.

### Decision 2: Nested if/else for Bool/Int/String match instead of brtable

**Choice**: Use nested `if (result T) ... else ... end` blocks for non-tag-union matches.

**Rationale**: `brtable` requires an i32 index for dispatch, which works for tag discriminants but not for Bool (already i32 0/1), Int (i64), or String (pointer requiring equality check). Nested if/else is the simplest correct encoding.

**WASM structure for Bool match** (`match x { true => a | false => b }`):
```
local.get scrutinee
i32.const 1
i32.eq
if (result i64)
  <emit arm_true.body>
else
  <emit arm_false.body or wildcard>
end
```

**WASM structure for Int match** (`match x { 1 => a | 2 => b | _ => c }`):
```
local.get scrutinee
i64.const 1
i64.eq
if (result i64)
  <emit arm_1.body>
else
  local.get scrutinee
  i64.const 2
  i64.eq
  if (result i64)
    <emit arm_2.body>
  else
    <emit wildcard.body or unreachable>
  end
end
```

### Decision 3: resolve_tag_index() in lower.odin

**Choice**: Add a helper that resolves a tag union type and finds the positional index of a tag name within `tag_entries`.

**Rationale**: The codegen emits `tag_index` as the tag byte stored at `CAMP_TAG_TAG_OFFSET`. At runtime, `brtable` uses this byte to dispatch. Currently hardcoded to 0, causing all matches to jump to arm 0.

The resolver follows newtype chains (since tag union types may be wrapped in `Inferred_Type.inner_id`) and iterates `tag_entries` to find the matching name.

### Decision 4: local_types map on Codegen_Env

**Choice**: Add `local_types: map[Intern_ID]IR_Type` to `Codegen_Env`, populated during `collect_locals` and parameter setup.

**Rationale**: Tag payload fields are stored with type-aware `emit_store_for_type` (i32.store or i64.store), but loaded with hardcoded `Wasm_I32_Load`. The `local_types` map lets the tag union match codegen call `emit_load_for_type(payload_type.wasm_type, buf)` instead.

### Decision 5: Fix _start function local setup

**Choice**: Set `env.tmp_local_base = 0` and `env.tmp_count = 0` before emitting the _start function body. Include `env.locals` (dynamically added during emit_expr, e.g. i64 scrutinee local for Int match) in the final local declarations.

**Rationale**: The _start function hardcodes `env.next_local = 4` for tmp locals but never sets `tmp_local_base`, leaving it with a stale value from the last Camp function. The Int match codegen adds an i64 local via `append(&env.locals, ...)` and increments `env.next_local`, but the _start function builds its own `start_locals` array from `collected_locals` only, missing the dynamically-added locals.

### Decision 6: Fix Wasm_Memory_Copy encoding

**Choice**: Append `0x00 0x00` (two memidx bytes for memory 0) after the `0xFC 0x0A` opcode.

**Rationale**: The WASM spec requires `memory.copy` to encode as `0xFC 0x0A src_memidx dst_memidx`. Both memidx must be `0x00` for linear memory 0. Without them, wasmtime reads the next instruction byte (0x20 = `local.get`) as a memidx, producing "unknown memory 32".

### Decision 7: Fix camp_list_push stack imbalance

**Choice**: Remove the redundant initial `local.get 0; i32.load 0` (which loads list.len but never consumes it), and reorder the address computation to: `data_ptr + len * 8` directly.

**Rationale**: The current code loads `len` at the top, then separately loads `data_ptr` and `len` again for the address computation. The first `len` load is never consumed, leaving an extra i32 on the stack at function end.

## Risks / Trade-offs

- **Nested if/else depth**: For matches with many Int/String literal arms, deeply nested if/else blocks may bloat WASM binary size. → Mitigation: Accept for now; optimize to hash-based dispatch later if needed.
- **collect_locals pattern variable types**: Pattern-bound variables get default `IR_Type{wasm_type = .I32}` if their type can't be resolved from the tag union. → Mitigation: The `local_types` map is populated from the type store during codegen, where tag union payload types are available.
- **String table `transmute([]u8)entry.value`**: The current string data segment encoding may not correctly produce string bytes from an Odin `string`. → Mitigation: Investigate separately; this affects all programs with string literals, not just pattern matching.

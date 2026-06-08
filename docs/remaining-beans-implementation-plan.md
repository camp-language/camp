# Remaining Beans: Comprehensive Implementation Plan

## ⚠️ NON-NEGOTIABLE COMPLETION CONTRACT ⚠️

**Every task in this plan MUST be fully implemented, tested, and verified. There is no
"good enough", no partial completion, no "we'll come back to this", no deferral.**

- If a task takes 100 lines of WASM bytecode generation, write all 100 lines.
- If a task requires implementing SipHash-1-3 from scratch in raw WASM instructions, do it.
- If a task requires touching 10 files and adding 500 lines of runtime code, do it.
- If a task is harder than expected, that is not a reason to stop. It is a reason to think harder.
- If existing tests break, fix the code until they pass. Never suppress, skip, or delete a test.
- If `just check` fails at any point, stop and fix it before continuing.

**The work is done when:**
1. Every bean is closed (status: completed)
2. `odin test src` passes with zero failures
3. `just check` passes clean (format-check + build + test-e2e + lint + doc-tests)
4. Every new feature has unit tests (in `src/test_ir.odin`) AND e2e tests (in `tests/e2e/`)
5. Every change is committed and pushed

**There is no yield point between tasks.** The agent works Task 1 through Task 8 without
stopping. If blocked on one task, move to the next unblocked task and return later.
But every task gets completed. No exceptions.

---

## Overview

11 beans remain. This document is a step-by-step technical guide for an implementing agent.
The agent MUST be relentless — work until all beans are closed, all existing tests pass,
`just check` passes, and new tests have been added for every change.

## Dependency Graph

```
camp-structural-lowering (tag union Eq) ─────────────┐
camp-sirt (structural Ord) ──────────────────────────┤
camp-recursive-closure (bug fix) ────────────────────┤
camp-c3d4 remaining (Debug runtime bodies) ──────────┤
camp-9m0n (Hash stdlib impls) ──► camp-llot (SipHash runtime) ─┬► camp-gykd (container traits)
                                                               ├► camp-r33l (stdlib tests)
                                                               └► camp-a6je (kitchen sink tests)
```

**Execution order (respecting dependencies):**
1. camp-recursive-closure (standalone bug, unblocks list recursion)
2. camp-structural-lowering (tag union Eq, unblocks camp-sirt)
3. camp-sirt (structural Ord for records/tag unions/tuples)
4. camp-c3d4 remaining (Debug runtime bodies)
5. camp-9m0n + camp-llot (Hash intrinsics + SipHash-1-3 runtime)
6. camp-gykd (container traits: List/Map/Set/Result Eq/Ord/Debug/Hash)
7. camp-r33l (stdlib tests for U16/U32/U64/F32/F64/Str/Bytes/Map/Set)
8. camp-a6je (kitchen-sink integration tests)

After each step: run `just check`. Fix anything that breaks before moving on.
11 beans remain (8 remaining + 3 completed with residual work). This document covers 8
tasks: the 8 uncompleted beans (with camp-9m0n and camp-llot combined into Task 5).
---

## Task 1: camp-recursive-closure — Recursive closure fn_idx trap

**Status:** todo (bug)  
**Priority:** HIGH  
**Symptom:** Recursive list functions compile to valid WASM but trap at runtime:  
"undefined element: out of bounds table access"

### Root Cause Analysis (DIAGNOSTIC-FIRST — do NOT guess, inspect)

The issue is in closure conversion for self-referencing closures. When a function like:
```camp
sum = |xs: List(I64)| -> I64 { match xs { Nil => 0, Cons(h, t) => h + sum(t) } }
```
is closure-converted, `sum` is a free variable in its own body. The closure converter:
1. Creates a closed function `closed_N` with `_cenv` as first param
2. Captures `sum` in the environment (env record)
3. Builds closure record `[fn_idx=closed_N, env_ptr=env_record]`

When `sum(t)` executes recursively:
1. Loads `sum` from env → gets the closure record pointer
2. Loads `fn_idx` from closure record at offset `CAMP_TAG_FIELDS_OFFSET` (8)
3. Loads `env_ptr` from closure record at offset `CAMP_TAG_FIELDS_OFFSET + 8` (16)
4. Calls `call_indirect(fn_idx, env_ptr, t)`

**Preliminary analysis (verify before acting on):**

The `fn_idx` field in the closure record is an `IR_Var` with `name = closed_fn_name.name`.
In codegen, `emit_expr` for `IR_Var` resolves via `env.func_map[u64(e.name)]`
(`emit_expr.odin:392`). The closed function IS registered in `func_map` at
`codegen.odin:882`. So the func_map path SHOULD resolve correctly.

However, the bean reports "fn_idx is wrong/uninitialized". Possible root causes:

1. **`call_indirect` type index mismatch.** The closed function's WASM type is computed
   from its `IR_Param` list (closure_convert.odin:479-493). The `IR_Closure_Call` computes
   its type from `e.args` + env (emit_expr.odin:2461-2475). If these produce different
   `get_or_create_type` results (e.g., `i32` vs `i64` for a list pointer due to
   coercion), `call_indirect` traps with "type mismatch in call_indirect".

2. **Element table out of bounds.** If `fn_idx` resolves to a value beyond
   `total_funcs` (the element table size), the lookup traps. This could happen if
   `func_map` returns a stale or incorrect index.

3. **fn_idx resolves to 0 (default fallback).** If `func_map` lookup fails at
   `emit_expr.odin:392`, the fallback is `Wasm_I32_Const{value = 0}`. Index 0 IS
   a valid table entry, but it would call the WRONG function, which might trap
   internally.

**DO NOT apply a fix until you confirm which of these is the cause.**

### Debugging Steps (MANDATORY — do these first)

1. Add a test: `tests/e2e/execution/recursive-list-sum/Main.camp`:
   ```camp
   sum = |xs: List(I64)| -> I64 {
     match xs {
       Nil => 0
       Cons(h, t) => h + sum(t)
     }
   }
   pub main! = || -> I64 { sum([1, 2, 3, 4]) }
   ```
   Expected: exit code 10 (1+2+3+4)

2. Build: `just build`

3. Run to confirm the trap: `wasmtime run camp.wasm` (or the e2e runner)

4. Inspect the generated WASM with `wasm2wat`:
   - Find the closed function in the module — verify it exists
   - Find the element table section — verify the closed function's index is listed
   - Find the `call_indirect` instruction in the recursive call path — check its
     type index and compare with the closed function's actual type
   - If the trap is "undefined element": the fn_idx value is out of table bounds
   - If the trap is "type mismatch": the call_indirect type doesn't match the function

5. Only AFTER confirming the root cause, apply the fix:
   - **If type mismatch:** Fix the param type computation in either closure_convert
     (the closed function's params) or emit_expr (the Closure_Call's type).
   - **If fn_idx wrong:** Add logging to `emit_expr` for `IR_Var` to see what
     `func_map` returns. Check if the Intern_ID matches.
   - **If fn_idx = 0:** The func_map lookup is failing. Check if the closed function
     name's Intern_ID is consistent between closure_convert and codegen.

**Key files for debugging:**
- `src/ir/closure_convert.odin:539-544` — fn_idx_var creation
- `src/codegen/emit_expr.odin:1773-1781` — fn_idx translation in Construct_Record
- `src/codegen/emit_expr.odin:2445-2480` — Closure_Call codegen + type computation
- `src/codegen/codegen.odin:848-883` — func_map + decl_to_wasm_fn_idx population
- `src/codegen/codegen.odin:1116-1128` — element table population

### Verification
- `tests/e2e/execution/recursive-list-sum/`: `sum([1,2,3,4])` returns 10
- `tests/e2e/execution/recursive-list-length/`: `length([1,2,3])` returns 3
- `tests/e2e/execution/recursive-list-append/`: `append([1,2],[3,4])` == `[1,2,3,4]`
- Existing `tests/e2e/closures/recursive-closure/` continues to pass

---

## Task 2: camp-structural-lowering — Tag union structural Eq

**Status:** todo  
**Priority:** HIGH  
**Symptom:** `Ok(1) == Ok(1)` compares pointer values (wrong). Records and tuples
already have structural Eq (see `lower_structural_eq` and `lower_tuple_eq` in `lower.odin`).

### What's Missing

In `lower_tbinop` (`src/ir/lower.odin:1460-1471`), when `e.op == .Eq_Eq || e.op == .Bang_Eq`:
```odin
#partial switch tin in inf {
case semantics.Inferred_Record_Row:
    return lower_structural_eq(e, env, tin.record_fields, tin.record_rest)
case semantics.Inferred_Tuple:
    return lower_tuple_eq(e, env, tin)
}
```
**Missing:** `case semantics.Inferred_Tag_Union_Row:` — tag unions fall through to the
default `IR_BinOp(.Eq)` which does pointer comparison.

### Implementation

Add `lower_tag_union_eq` to `src/ir/lower.odin`. Strategy:

1. **Flatten tag entries** using `flatten_tag_entries` (already exists at line 1763)
2. **Compare tag indices first:** Load discriminant byte from each operand
   (at offset `CAMP_TAG_TAG_OFFSET` = 4) and compare. If different → return False.
3. **If same tag, compare payloads:** For each payload field of the matching tag,
   do field-by-field comparison chained with `&&`.

### Tag byte extraction (critical detail)

The IR has no byte-level load node. `IR_I32_Load` loads 4 bytes. The tag byte is at
offset 4 within the heap-allocated tag cell. Since WASM is little-endian, loading an
`i32` at offset 4 puts the tag byte in the least-significant byte.

**Approach:** Load i32 at offset 4, mask with `0xFF` to isolate the tag byte:
```
tag_l = IR_I32_Load(base=left, offset=4)   // loads 4 bytes starting at offset 4
tag_l_masked = IR_BinOp(.And, tag_l, 0xFF)  // isolate LSB = tag byte
tag_r = IR_I32_Load(base=right, offset=4)
tag_r_masked = IR_BinOp(.And, tag_r, 0xFF)
tags_equal = IR_BinOp(.Eq, tag_l_masked, tag_r_masked)
```

The mask with `0xFF` is necessary because the bytes after the tag byte
(scan_size, scalar_mask) would contaminate the comparison.

**Alternative:** Generate `IR_Match` on the left operand to dispatch by tag, then
compare the right operand's tag byte + payloads within each arm. This is more complex
but mirrors existing match codegen.

### Full algorithm

```odin
lower_tag_union_eq :: proc(
    e: ^semantics.TExpr_BinOp,
    env: ^Lower_Env,
    tag_entries: []semantics.Type_Tag_Entry,
    tag_rest: base.Type_Var_ID,
) -> IR_Expr {
    // 1. Flatten all tag entries
    all_tags: [dynamic]semantics.Type_Tag_Entry
    all_tags = make([dynamic]semantics.Type_Tag_Entry, 0, len(tag_entries))
    defer delete(all_tags)
    flatten_tag_entries(env.store, e.left.type_.type_id, &all_tags)
    
    bool_type := base.IR_Type{wasm_type = .I32, type_id = 0}
    i32_type := base.IR_Type{wasm_type = .I32, type_id = 0}
    
    left_ir := lower_texpr(e.left, env)
    right_ir := lower_texpr(e.right, env)
    
    // 2. Load and compare tag bytes (masked to isolate tag byte)
    left_tag_load := new(IR_I32_Load)
    left_tag_load^ = IR_I32_Load {
        base = left_ir, offset = CAMP_TAG_TAG_OFFSET, type = i32_type, span = e.span,
    }
    left_tag_mask := new(IR_BinOp)  // AND with 0xFF
    left_tag_mask^ = IR_BinOp {
        op = .And, left = IR_Expr(left_tag_load),
        right = make_ir_lit_int(0xFF, i32_type, e.span),
        type = i32_type, span = e.span,
    }
    // ... same for right_tag_mask ...
    
    tags_eq := new(IR_BinOp)
    tags_eq^ = IR_BinOp {
        op = .Eq, left = IR_Expr(left_tag_mask), right = IR_Expr(right_tag_mask),
        type = bool_type, span = e.span,
    }
    
    // 3. If tags differ → False. If same → compare payloads.
    // For each tag variant with payloads, generate field-by-field && chains.
    // Tags with no payloads: True (tags already match).
    // Chain payload comparisons with nested IR_If:
    //   if tag_l == TAG_I_INDEX:
    //     (left.payload0 == right.payload0) && (left.payload1 == right.payload1) && ...
    //   else if tag_l == TAG_J_INDEX:
    //     ...
    //   else: True  // no-payload tag
    
    // 4. Wrap: if !tags_eq then False else payload_comparison
    // For !=, wrap the result with wrap_not (existing helper).
}
```

**Payload access:** Tag payloads are at `CAMP_TAG_FIELDS_OFFSET + field_index * 8`
from the heap pointer. Use `IR_I32_Load` or `IR_I64_Load` depending on the payload
type. For heap payloads (records, other tags), use `IR_I32_Load` (pointer).

**Use existing IR nodes:** `IR_I32_Load` (load tag byte + payloads), `IR_BinOp` (compare,
mask), `IR_If` (branch on tag match).

### Files to modify
- `src/ir/lower.odin`: Add `lower_tag_union_eq`, add case in `lower_tbinop`

### Tests
```camp
// E2E: tests/e2e/execution/tag-union-eq/Main.camp
test "tag union eq" {
  expect Ok(1) == Ok(1)
  expect not (Ok(1) == Ok(2))
  expect not (Ok(1) == Err("no"))
  expect Err("a") == Err("a")
  expect not (Err("a") == Err("b"))
  expect Some(42) == Some(42)
  expect not (None == Some(0))
}
```

**Also add unit test in `src/test_ir.odin`** testing that `lower_tbinop` with `Eq_Eq`
on tag union types produces `IR_If` + tag comparison nodes (not raw `IR_BinOp(.Eq)`).

---

## Task 3: camp-sirt — Structural Ord for records, tag unions, tuples

**Status:** todo  
**Priority:** HIGH  
**Depends on:** Task 2 (tag union Eq is prerequisite for tag union Ord)

### Current State
Structural `==`/`!=` works for records and tuples (field-by-field). Structural `<`, `>`,
`<=`, `>=` does NOT exist — these fall through to default `IR_BinOp` which compares
pointers for heap types.

### Implementation

In `lower_tbinop` (`src/ir/lower.odin:1428`), after the existing Eq/Ne handling block,
add a parallel block for comparison operators:

```odin
if e.op == .Lt || e.op == .Gt || e.op == .Lt_Eq || e.op == .Gt_Eq {
    left_type_id := texpr_type_id(e.left)
    resolved := semantics.resolve_var(env.store, left_type_id)
    v := &env.store.vars[int(resolved)]
    if inf, ok := v.link.(semantics.Inferred_Type); ok {
        #partial switch tin in inf {
        case semantics.Inferred_Record_Row:
            return lower_structural_ord(e, env, tin.record_fields, tin.record_rest)
        case semantics.Inferred_Tuple:
            return lower_tuple_ord(e, env, tin)
        case semantics.Inferred_Tag_Union_Row:
            return lower_tag_union_ord(e, env, tin)
        }
    }
}
```

#### `lower_structural_ord` — Lexicographic record comparison

Sort fields alphabetically (same as `lower_structural_eq`). Generate:
```
let cmp_0 = compare(a.f0, b.f0)  // returns Order
if cmp_0 != Equal { return apply_op(cmp_0, op) }
let cmp_1 = compare(a.f1, b.f1)
if cmp_1 != Equal { return apply_op(cmp_1, op) }
...
return apply_op(Equal, op)  // all fields equal
```

Where `apply_op(Order, op)` converts an `Order` value to the requested comparison result:
- `Lt` → `order == Less`
- `Gt` → `order == Greater`
- `Lt_Eq` → `order != Greater`
- `Gt_Eq` → `order != Less`

**IR representation:** Use `IR_BinOp` nodes. The `compare` call for each field dispatches
to the field type's `Ord.compare` method. For primitive fields, the codegen emits native
WASM comparison. For structural fields, recursion handles it.

**Implementation detail:** Since `compare` is a function call (not a BinOp), generate
`IR_Call` to the field type's `Ord.compare` method, then pattern-match the result.
But this requires resolving the `Ord.compare` method for each field type at lowering time.

**Simpler approach:** Use the existing `IR_BinOp` comparison operators. For each field:
1. If `a.f_i < b.f_i` → return True (for `<`), or False (for `>=`)
2. If `a.f_i > b.f_i` → return False (for `<`), or True (for `>=`)
3. If equal → continue to next field

This avoids needing to resolve `Ord.compare` at the IR level and leverages the existing
comparison codegen for each field type (which already works for primitives).

```odin
// Pseudo-IR for lexicographic < on {a: I64, b: Str}:
//   if left.a < right.a { True }
//   else if left.a > right.a { False }
//   else if left.b < right.b { True }
//   else if left.b > right.b { False }
//   else { False }  // all equal → not less than
```

For `<=`, `>=`, adjust the final "all equal" case and the intermediate checks.

**Recursive structural fields:** If a field is itself a structural type (e.g.,
`{a: {x: I64}, b: I64}`), the `a.f_i < b.f_i` comparison for that field will
recursively trigger `lower_structural_ord`. This is correct — the recursive call
generates nested if-then-else chains for the inner record. No special handling needed,
but be aware of this when debugging: the generated IR will be deeply nested for
records-within-records.

#### `lower_tag_union_ord` — Tag union comparison

1. Compare tag indices (discriminant bytes): lower tag index wins
2. If same tag, compare payloads lexicographically
3. Tags with no payloads: equal if same tag

#### `lower_tuple_ord` — Tuple comparison

Same as record Ord but with positional field access (`_0`, `_1`, ...).

### Files to modify
- `src/ir/lower.odin`: Add `lower_structural_ord`, `lower_tag_union_ord`,
  `lower_tuple_ord`; add comparison-operator handling in `lower_tbinop`

### Tests
```camp
// Unit tests in src/test_ir.odin
@(test)
test_structural_ord_record :: proc(t: ^testing.T) {
    // Test that {a: 1, b: 2} < {a: 1, b: 3} lowers to nested if-then-else
}

// E2E tests
// tests/e2e/execution/structural-ord-record/Main.camp
main! = || -> I64 {
    if {a: 1, b: 2} < {a: 1, b: 3} { 1 } else { 0 }
}
// Expected: exit 1

// tests/e2e/execution/structural-ord-tuple/Main.camp
main! = || -> I64 {
    if (1, "a") < (1, "b") { 1 } else { 0 }
}
// Expected: exit 1
```

---

## Task 4: camp-c3d4 remaining — Debug runtime body implementations

**Status:** completed (trait registration) but runtime bodies are STUBS  
**Priority:** MEDIUM

### Current State
The `*_to_str` / `*_debug` runtime functions in `src/codegen/runtime.odin` are stubs
that return null (0). The codegen in `emit_expr.odin` already intercepts calls to
functions like `I64_debug`, `Bool_debug`, etc. and emits calls to the corresponding
`Runtime_Func` entries. The stubs just need real implementations.

### Already implemented:
- `emit_camp_i64_to_str_body` — COMPLETE (decimal string conversion)
- `emit_camp_i32_to_str_body` — COMPLETE

### Stubs to implement:
- `emit_camp_f64_to_str_body` (line 3752) — returns 0
- `emit_camp_bool_to_str_body` (line 3765) — returns 0

### Not yet created (need new Runtime_Func + body + codegen wiring):
- `emit_camp_char_debug_body` — Char to single-char string
- `emit_camp_bytes_debug_body` — Bytes hex dump
- `emit_camp_list_debug_body` — `[a, b, ...]` format
- `emit_camp_map_debug_body` — `{k1: v1, k2: ...}` format
- `emit_camp_set_debug_body` — `{e1, e2, ...}` format
- `emit_camp_result_debug_body` — `Ok(v)` / `Err(e)` format
- `emit_camp_json_debug_body` — JSON value
- `emit_camp_duration_debug_body` — human-readable
- `emit_camp_uuid_debug_body` — 8-4-4-4-12 hex
- `emit_camp_path_debug_body` — string repr
- `emit_camp_uri_debug_body` — string repr
- `emit_camp_regex_debug_body` — pattern string
- `emit_camp_base64_debug_body` — base64 string
- `emit_camp_unit_debug_body` — "{}" literal

### Pattern for adding a new runtime function

**Step 1: Add to `Runtime_Func` enum** (`src/codegen/emit_expr.odin:217-275`):
```odin
// After existing entries:
Bool_To_Str,
// Add:
Char_Debug,
Bytes_Debug,
List_Debug,
Map_Debug,
Set_Debug,
Result_Debug,
Unit_Debug,
```

**Step 2: Add function type + registration** (`src/codegen/codegen.odin`):
```odin
// Near existing to_str types (around line 380):
char_debug_type_idx := get_or_create_type(&env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})
// ... repeat for each ...

// Near existing registrations (around line 438):
char_debug_func_idx := add_function(&env, char_debug_type_idx)
runtime_func_indices[Runtime_Func.Char_Debug] = char_debug_func_idx
```

**Step 3: Add body emission** (`src/codegen/runtime.odin`):
```odin
emit_camp_char_debug_body :: proc(alloc_func_idx: int) -> Wasm_Code {
    // Params: (char_val: i32) -> i32 (Str pointer)
    // Alloc 5 bytes (4 header + 1 char), write len=1, write byte
    // ... WASM bytecode ...
}
```

**Step 4: Wire body** (`src/codegen/codegen.odin`, around line 710):
```odin
append(&mod.codes, emit_camp_char_debug_body(alloc_func_idx))
```

**Step 5: Add codegen interception** (`src/codegen/emit_expr.odin`, around line 894):
```odin
if name_str == "Char_debug" && len(e.args) == 1 {
    emit_expr(e.args[0], buf, env, runtime_indices)
    emit_instruction(
        Wasm_Call{index = u32(runtime_indices[Runtime_Func.Char_Debug])},
        buf,
    )
    break
}
```

### Implementation order (easiest first):
1. **Bool_to_str** — 2 branches: push "True" or "False" string data offset, return pointer
2. **Char_debug** — Single-byte string
3. **Unit_debug** — Return "{}" string
4. **F64_to_str** — Non-trivial: need float-to-decimal conversion in WASM. Start with
   integer part only, then add decimal. Use the same digit-extraction loop as i64_to_str
   but handle the fractional part.
5. **Bytes_debug** — Hex dump: for each byte, emit 2 hex chars
6. **Container debug** (List, Map, Set, Result) — Recursive: call `debug` on each element.
   These are the hardest because they require dynamic dispatch (calling the element type's
   debug function). Strategy: emit a loop that calls the element's debug function via
   the closure/call_indirect mechanism, concatenating results with separators.

**Priority for containers:** Implement only the primitive debug functions first.
Container debug (List_debug, Map_debug, etc.) can be deferred to Task 6 (camp-gykd).

### Tests
```camp
// tests/e2e/execution/debug-bool/Main.camp
pub main! = || -> I64 {
    // Debug Bool should produce "True" or "False"
    // Can't easily test string output via exit code...
    // Use expect + Console.println! or just verify compilation
    0
}
```

**Better:** Add unit tests in `src/test_ir.odin` that compile Camp code calling `debug()`
on various types and verify the IR structure. Add e2e tests that compile successfully
(the `crash "intrinsic"` bodies should no longer trap once the codegen intercepts them).

**For now:** Focus on `Bool_to_str` and `Char_debug`. The others can be stubs until
container debug is needed. The key blocker is that calling `debug(42)` currently works
(intercepted by codegen → calls `I64_To_Str` runtime function), so the system functions
for primitives. The stubs only matter when the runtime function returns null.

---

## Task 5: camp-9m0n + camp-llot — Hash runtime (SipHash-1-3)

**Status:** in-progress  
**Priority:** HIGH (blocks Tasks 6, 7, 8)

### Architecture

The Hash trait: `Hash : { hash : |Self, Hasher| -> Hasher }`  
The Hasher type: `@Hasher : {}` — opaque, internally a SipHash-1-3 state

### Hasher memory layout (EXACT)

`Hasher` is a heap-allocated record. Total size: 44 bytes payload + 8 bytes header = 52 bytes.

```
Offset  Size  Field
------  ----  -----
0       4     refcount (i32)        — standard tag header
4       1     tag (u8)             — 0x20 (unique tag for Hasher)
5       1     scan_size (u8)       — 0 (no heap pointers inside)
6       2     scalar_mask (u16)    — 0xFF (all scalars)
8       8     v0 (i64)             — SipHash state word 0
16      8     v1 (i64)             — SipHash state word 1
24      8     v2 (i64)             — SipHash state word 2
32      8     v3 (i64)             — SipHash state word 3
40      8     tail (i64)           — buffered bytes (little-endian)
48      4     tail_len (i32)       — number of bytes in tail (0..7)
```

Use a unique tag value (e.g., `HASHER_TAG :: 0x20`) so `camp_drop` can identify it.
`scan_size = 0` because the Hasher contains no heap pointers (all i64/i32 scalars).

### New Runtime_Func entries needed

```odin
// In Runtime_Func enum:
Hash_Init,        // () -> i32 (Hasher pointer)
Hash_Write_I64,   // (hasher: i32, val: i64) -> i32 (hasher)
Hash_Write_I32,   // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_I16,   // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_I8,    // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_F64,   // (hasher: i32, val: f64) -> i32 (hasher)
Hash_Write_F32,   // (hasher: i32, val: f32) -> i32 (hasher)
Hash_Write_Str,   // (hasher: i32, str: i32) -> i32 (hasher)
Hash_Finish,      // (hasher: i32) -> i64 (hash value)
```

Note: No `Hash_Write_Byte` — all writes go through typed functions that handle
byte decomposition internally.

### SipHash-1-3 Implementation

Implement in WASM bytecode (`src/codegen/runtime.odin`). The algorithm:

**SipHash constants:**
```
SIP_C0 :: 0x736f6d6570736575
SIP_C1 :: 0x646f72616e646f6d
SIP_C2 :: 0x6c7967656e657261
SIP_C3 :: 0x7465646279746573
```

**Initialization (`Hash_Init`):**
Allocate 52-byte Hasher. Set:
```
v0 = SIP_C0  (key is zero, so k0 ^ C0 = C0)
v1 = SIP_C1
v2 = SIP_C2
v3 = SIP_C3
tail = 0
tail_len = 0
```

**SipRound (compression round):**
```
v0 += v1; v2 += v3
v1 = ROTL64(v1, 13); v3 = ROTL64(v3, 16)
v1 ^= v0; v3 ^= v2
v0 = ROTL64(v0, 32)
v0 += v3; v2 += v1
v1 = ROTL64(v1, 17); v3 = ROTL64(v3, 21)
v1 ^= v3; v2 ^= v0
v2 = ROTL64(v2, 32)
```

**Byte buffering (critical):** SipHash processes 8-byte blocks. When `Hash_Write_I32`
is called (4 bytes), the bytes must be buffered:

```
Hash_Write_I32(hasher_ptr, val_i32):
    tail = load_i64(hasher_ptr + 40)
    tail_len = load_i32(hasher_ptr + 48)
    
    // Pack val as little-endian bytes into tail
    shifted = i64(val_i32) << (tail_len * 8)
    tail = tail | shifted
    tail_len = tail_len + 4
    
    // If tail_len >= 8, compress one block
    if tail_len >= 8:
        v0..v3 = load from hasher
        v3 ^= tail
        SipRound (1 round)
        v0 ^= tail
        tail_len = tail_len - 8
        // Handle remaining bytes (if tail_len was > 8, which can't happen for i32)
        store v0..v3 back
    
    store tail, tail_len back
    return hasher_ptr
```

For `Hash_Write_I64` (8 bytes), the value IS a full block:
```
Hash_Write_I64(hasher_ptr, val_i64):
    // Flush any existing tail first (if tail_len > 0)
    // Then compress val directly as one block
    v0..v3 = load from hasher
    v3 ^= val_i64
    SipRound (1 round)
    v0 ^= val_i64
    store v0..v3 back
    return hasher_ptr
```

For `Hash_Write_Str`: iterate bytes of the string, buffer each byte via tail.
String layout: `[len: i32][bytes...]`. Use a loop over `0..len`, load each byte,
shift into tail, compress when tail reaches 8 bytes.

**Finalization (`Hash_Finish`):**
```
Hash_Finish(hasher_ptr):
    tail = load_i64(hasher_ptr + 40)
    tail_len = load_i32(hasher_ptr + 48)
    
    // Pad tail: set byte at tail_len to 0xFF, rest to 0
    // (shift 0xFF into position, OR with existing tail)
    padded_tail = tail | (0xFF << (tail_len * 8))
    
    v0..v3 = load from hasher
    v3 ^= padded_tail
    SipRound (1 round)   // SipHash-1-3: 1 compression round
    v0 ^= padded_tail
    
    // Finalization: 3 rounds with v2 ^= 0xFF
    v2 ^= 0xFF
    SipRound (round 1 of 3)
    SipRound (round 2 of 3)
    SipRound (round 3 of 3)
    
    return v0 ^ v1 ^ v2 ^ v3
```

**WASM implementation notes:**
- Use `i64.add`, `i64.xor` directly
- WASM has no native `i64.rotl` — implement as:
  `ROTL64(x, n) = (i64.shl(x, n) | i64.shr_u(x, 64 - n))`
- Each SipRound is ~20 WASM instructions (8 adds, 4 xors, 4 rotls, misc)
- SipHash-1-3 total: 1 init + 1 compression + 3 finalization rounds = 5 SipRounds
- Total per `Hash_Finish` call: ~100 WASM instructions + byte processing loop

**Hasher tag constant:** Add `HASHER_TAG :: 0x20` to `codegen.odin` alongside
`MAP_HEADER_TAG :: 0x10` and `MAP_NODE_TAG :: 0x11`.

### Codegen wiring for Hash intrinsics

In `emit_expr.odin`, add interception for `Hash` module calls similar to `Map`:
```odin
if module_str == "Hash" || name_str ends with "_hash" {
    // Route to appropriate Hash_Write_* runtime function
}
```

**Alternative (simpler):** Add per-type interception like Debug:
```odin
if name_str == "I64_hash" && len(e.args) == 2 {
    // args[0] = value, args[1] = hasher
    emit_expr(e.args[1], buf, env, runtime_indices)  // push hasher
    emit_expr(e.args[0], buf, env, runtime_indices)  // push value
    emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Hash_Write_I64])}, buf)
    break
}
```

### Files to modify
- `src/codegen/emit_expr.odin`: Add `Hash_*` to `Runtime_Func`, add interception
- `src/codegen/codegen.odin`: Add function types, registrations, body emissions
- `src/codegen/runtime.odin`: Implement SipHash-1-3 + per-type hash functions

### Tests
```camp
// Unit test: compile code that calls hash and verify it doesn't crash
// tests/e2e/execution/hash-i64/Main.camp
import Hash { hash }
pub main! = || -> I64 {
    h = hash(42, Hasher{})
    0  // If we get here, hash didn't crash
}

// Unit test in src/test_ir.odin: verify Hash runtime functions are registered
```

**Critical test:** Verify that two equal values produce the same hash:
```camp
import Hash { hash }
import Ord { compare }
pub main! = || -> I64 {
    h1 = hash(42, Hasher{})
    h2 = hash(42, Hasher{})
    // h1 and h2 should be equal (same input → same hash)
    0
}
```

---

## Task 6: camp-gykd — Container traits (List/Map/Set/Result)

**Status:** todo  
**Priority:** HIGH  
**Depends on:** Task 5 (Hash runtime)

### What's needed

The stdlib already has `is Eq`, `is Ord`, `is Debug`, `is Hash` blocks for List, Map,
Set, and Result — all with `crash "intrinsic: ..."` bodies. These need either:
(A) Runtime WASM implementations, or
(B) Pure Camp implementations

### Recommended approach: Pure Camp where possible

**Eq for containers:**
- `List is Eq`: Walk both lists in parallel. If both Nil → True. If both Cons(h,t) →
  `h == t && rest_eq`. If mismatched → False. **Requires** `T: Eq` bound.
  **Problem:** Camp doesn't currently support trait bounds on `is` blocks.
  **Workaround:** Implement as intrinsic that dispatches at runtime based on element type.

- `Result is Eq`: `match (a, b) { (Ok(x), Ok(y)) => x == y, (Err(x), Err(y)) => x == y, _ => False }`
  Same bound issue.

**Since trait bounds aren't supported yet**, all container trait impls must be intrinsics
with runtime WASM implementations. The runtime functions receive the compare/hash/debug
function pointer as an extra argument (similar to Map's `ord_compare_func` pattern).

### Trait method resolution (critical architectural detail)

The runtime functions need a function pointer (e.g., the element type's `Eq.eq`).
The codegen must resolve this at compile time. Two approaches exist:

**Approach A — Lowering-time resolution (RECOMMENDED):** Mirror `resolve_ord_compare`.

1. Add fields to `IR_Call` for generic trait method pointers:
   ```odin
   IR_Call :: struct {
       // ... existing fields ...
       eq_compare_func:    base.Canonical_Name,  // for Eq.eq dispatch
       ord_compare_func:   base.Canonical_Name,  // existing — for Ord.compare
       hash_func:          base.Canonical_Name,  // for Hash.hash dispatch
       debug_func:         base.Canonical_Name,  // for Debug.debug dispatch
   }
   ```

2. In `lower_tcall`, when lowering a call like `List_eq(a, b)`:
   - Determine the element type from the List type argument
   - Call `resolve_trait_method(store, interner, element_type_id, "Eq", "eq")`
   - Store the resolved Canonical_Name in `eq_compare_func`

3. In codegen (`emit_expr.odin`), when intercepting `List_eq`:
   - Look up `e.eq_compare_func` in `func_map` to get the WASM function index
   - Pass it as the first argument to the runtime function

**Approach B — Codegen-time resolution:** Look up trait impls during codegen.
Requires passing the type store to codegen (currently not available). More invasive.
Use Approach A.

**Existing pattern to follow:** `resolve_ord_compare` at `lower.odin:2258` resolves
the `Ord.compare` method for Map/Set key types. The same pattern applies:
```odin
resolve_eq_fn :: proc(
    store: ^semantics.Type_Store,
    interner: ^base.Intern_Table,
    type_id: base.Type_Var_ID,
) -> base.Canonical_Name {
    func_name, ok := resolve_trait_method(store, interner, type_id, "Eq", "eq")
    if !ok { return base.Canonical_Name{} }
    return func_name
}
```

### Implementation pattern (using List_eq as example)

**Runtime function signature:** `camp_list_eq(eq_fn_idx: i32, list_a: i32, list_b: i32) -> i32`

**Lowering** (`lower.odin`): When the typechecker produces a call to the intrinsic
`List_eq`, resolve the element type's `Eq.eq` method and store it in the `IR_Call`.

**Codegen interception** (`emit_expr.odin`):
```odin
if name_str == "List_eq" && len(e.args) == 2 {
    // Resolve eq function from the IR_Call's eq_compare_func field
    eq_fn_idx := 0
    if e.eq_compare_func.name != 0 {
        if idx, ok := env.func_map[u64(e.eq_compare_func.name)]; ok {
            eq_fn_idx = idx
        }
    }
    emit_instruction(Wasm_I32_Const{value = i32(eq_fn_idx)}, buf)
    emit_expr(e.args[0], buf, env, runtime_indices)
    emit_expr(e.args[1], buf, env, runtime_indices)
    emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.List_Eq])}, buf)
    break
}
```

**Runtime body** (`runtime.odin`):
```odin
emit_camp_list_eq_body :: proc(eq_type_idx: int, table_idx: int) -> Wasm_Code {
    // Params: (eq_fn_idx: i32, list_a: i32, list_b: i32) -> i32
    // Walk both lists:
    //   Loop:
    //     if a == 0 (Nil) and b == 0 (Nil): return 1
    //     if a == 0 or b == 0: return 0
    //     // Both Cons: compare heads
    //     head_a = load(a, CAMP_TAG_FIELDS_OFFSET)     // Cons head
    //     head_b = load(b, CAMP_TAG_FIELDS_OFFSET)
    //     // Call eq_fn(head_a, head_b) via call_indirect
    //     push head_a, head_b
    //     call_indirect(eq_fn_idx, eq_type_idx, table_idx)
    //     if result == 0: return 0
    //     // Advance to tails
    //     a = load(a, CAMP_TAG_FIELDS_OFFSET + 8)      // Cons tail
    //     b = load(b, CAMP_TAG_FIELDS_OFFSET + 8)
    //     br 0
}
```

**call_indirect type for Eq.eq:** `(i32, i32) -> i32` (Self, Self) -> Bool.
Use `get_or_create_type` to get the type index, pass to `emit_camp_list_eq_body`.

### New Runtime_Func entries
```odin
List_Eq,       // (eq_fn: i32, a: i32, b: i32) -> i32
List_Compare,  // (cmp_fn: i32, a: i32, b: i32) -> i32 (Order)
List_Debug,    // (debug_fn: i32, a: i32) -> i32 (Str)
List_Hash,     // (hash_fn: i32, a: i32, h: i32) -> i32 (Hasher)
Result_Eq,     // (eq_fn: i32, a: i32, b: i32) -> i32
Result_Compare,
Result_Debug,
Result_Hash,
Map_Eq,        // (eq_fn: i32, a: i32, b: i32) -> i32
Map_Compare,
Map_Debug,
Map_Hash,
Set_Eq,
Set_Compare,
Set_Debug,
Set_Hash,
```

### Files to modify
- `src/codegen/emit_expr.odin`: Runtime_Func enum + interception for container trait calls
- `src/codegen/codegen.odin`: Type registration + body emission
- `src/codegen/runtime.odin`: WASM implementations

### Priority order
1. `List_eq` and `List_compare` (most commonly needed)
2. `Result_eq` and `Result_compare`
3. `Map_eq`, `Set_eq`
4. `*_debug` and `*_hash` for all containers

### Tests
```camp
// tests/e2e/execution/list-eq/Main.camp
pub main! = || -> I64 {
    if [1, 2, 3] == [1, 2, 3] { 1 } else { 0 }
}
// Expected: exit 1

// tests/e2e/execution/list-ord/Main.camp
pub main! = || -> I64 {
    if [1, 2] < [1, 3] { 1 } else { 0 }
}
// Expected: exit 1

// tests/e2e/execution/result-eq/Main.camp
pub main! = || -> I64 {
    if Ok(42) == Ok(42) { 1 } else { 0 }
}
// Expected: exit 1
```

---

## Task 7: camp-r33l — Stdlib tests for U16/U32/U64/F32/F64/Str/Bytes/Map/Set

**Status:** todo  
**Priority:** NORMAL  
**Depends on:** Task 5 (Hash runtime, for Hash trait tests)

### Test pattern

Follow existing patterns from `Bool.camp`, `I64.camp`, `U8.camp`:
- Single `test` block per file (to avoid camp test hang — known issue)
- Test order: happy path → boundary → identity → trait impls

### Files to add tests to

**`stdlib/Num/U16.camp`** (currently has no test block):
```camp
test "U16 traits" {
  expect 0 == 0
  expect 42 == 42
  expect not (0 == 1)
  expect 0 < 1
  expect 65535 > 0
  expect 42 <= 42
  expect 42 >= 42
}
```

**`stdlib/Num/U32.camp`**, **`stdlib/Num/U64.camp`**: Same pattern with appropriate max values.

**`stdlib/Num/F32.camp`**, **`stdlib/Num/F64.camp`**:
```camp
test "F64 traits" {
  expect 0.0 == 0.0
  expect 1.0 == 1.0
  expect not (0.0 == 1.0)
  expect 0.0 < 1.0
  expect 1.0 > 0.0
  expect -1.0 < 0.0
}
```

**`stdlib/Str.camp`**:
```camp
test "Str traits" {
  expect "" == ""
  expect "abc" == "abc"
  expect not ("abc" == "def")
  expect "a" < "b"
  expect "abc" < "abd"
  expect "b" > "a"
}
```

**`stdlib/Map.camp`** and **`stdlib/Set.camp`**: Add basic construction + operation tests.
Note: Map/Set tests depend on Hash runtime (Task 5) being complete.

**`stdlib/Bytes.camp`**: Add tests if Bytes module exists.

### Tests to NOT duplicate
Don't re-test what `Bool.camp` and `I64.camp` already cover. Focus on boundary values
specific to each type (e.g., U16 max = 65535, F64 negative zero, etc.).

### Verification
Run `just test-doc-tests` to execute stdlib tests.

---

## Task 8: camp-a6je — Kitchen-sink integration tests

**Status:** todo  
**Priority:** NORMAL  
**Depends on:** Tasks 2, 3, 5 (structural Eq/Ord, Hash runtime)

### What to add to `tests/e2e/language/kitchen-sink/Main.camp`

Add new sections exercising:

```camp
// ============================================================
// SECTION: Trait Implementations
// Demonstrates: Eq, Ord, Debug, Hash on primitives and structures
// ============================================================

// Structural equality on records
record_eq_demo = || -> Bool {
  {a: 1, b: "x"} == {a: 1, b: "x"}
}

// Structural equality on tag unions
tag_eq_demo = || -> Bool {
  Ok(42) == Ok(42)
}

// Structural equality on tuples
tuple_eq_demo = || -> Bool {
  (1, "a") == (1, "a")
}

// Ord comparison on records
record_ord_demo = || -> Bool {
  {a: 1, b: 2} < {a: 1, b: 3}
}

// Hash on primitives (if runtime is complete)
// hash_demo = || -> Hasher { hash(42, Hasher{}) }
```

### Update expected.toml
After adding sections, run `just update-snapshots` to regenerate expected output.

---

## Execution Checklist (NON-NEGOTIABLE)

For each task, the implementing agent MUST complete ALL of the following before moving to
the next task. Skipping any step is failure.

1. **Implement** the change completely — no stubs, no TODOs, no placeholders
2. **Run `odin test src`** — ALL unit tests must pass. Zero failures. Zero skips.
3. **Run `just build`** — must compile clean. Zero warnings if possible.
4. **Run `just test-e2e`** — ALL e2e tests must pass. Every single one.
5. **Add new tests** — unit tests in `src/test_ir.odin` + e2e tests in `tests/e2e/`
   for every new behavior. Minimum: one happy-path test, one edge-case test.
6. **Run `just check`** — FULL CI must pass: format-check + build + test + lint + doc-tests
7. **Close the bean** — update `.beans/*.md` status to `completed`
8. **Commit and push** — conventional commit format: `feat(scope): description`

### What "non-negotiable" means

- **No partial implementations.** If the plan says "implement SipHash-1-3 in WASM bytecode",
  that means writing every SipRound, every ROTL, every byte of the compression and
  finalization logic. Not a stub. Not a comment saying "TODO: implement SipHash".

- **No scope reduction.** If a task says "add Eq/Ord/Debug/Hash for List/Map/Set/Result",
  that means ALL four traits for ALL four types. Not "Eq for List" and then stopping.

- **No test suppression.** If `just check` fails, the code is wrong. Fix the code.
  If a test is genuinely incorrect, update the test with a comment explaining why.

- **No time pressure shortcuts.** The implementing agent has no concept of time.
  It works until the work is done. If a WASM runtime function takes 200 lines of
  bytecode generation, write all 200 lines. If SipHash needs 40 SipRounds worth of
  WASM instructions, emit them all.

- **No yield points.** A completed sub-task is not a yield point. A phase boundary
  is not a yield point. The only yield point is when ALL 8 tasks are complete,
  ALL beans are closed, and `just check` passes clean.

### Recovery from blockers

If a task is blocked (e.g., a dependency isn't ready, or an approach doesn't work):
1. Document the blocker in the bean
2. Move to the next unblocked task
3. Return to the blocked task after unblocking
4. NEVER close a bean as "completed" if it has known issues

### Final verification (after ALL tasks)

After completing all 8 tasks, run the full verification suite one final time:
```bash
just check          # Must pass clean
odin test src       # Must pass clean
just test-doc-tests # Must pass clean
```
If ANY of these fail, fix the issue and re-run. The work is not done until all pass.

## Key Files Reference

| File | Purpose |
|------|---------|
| `src/codegen/emit_expr.odin` | Runtime_Func enum, codegen interception for intrinsics |
| `src/codegen/codegen.odin` | Runtime function type registration, body emission wiring |
| `src/codegen/runtime.odin` | WASM bytecode body implementations |
| `src/ir/lower.odin` | IR lowering: structural Eq/Ord, binop handling |
| `src/ir/closure_convert.odin` | Closure conversion (recursive closure bug) |
| `src/ir/ir.odin` | IR node definitions |
| `src/semantics/prelude.odin` | Trait registration (Eq, Ord, Hash, Debug) |
| `src/semantics/types.odin` | Type inference types (Inferred_Tag_Union_Row, etc.) |
| `stdlib/*.camp` | Stdlib trait implementations |
| `tests/e2e/` | End-to-end tests |
| `src/test_ir.odin` | IR-level unit tests |

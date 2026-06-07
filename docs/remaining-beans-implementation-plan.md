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

---

## Task 1: camp-recursive-closure — Recursive closure fn_idx trap

**Status:** todo (bug)  
**Priority:** HIGH  
**Symptom:** Recursive list functions compile to valid WASM but trap at runtime:  
"undefined element: out of bounds table access"

### Root Cause Analysis

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

**The problem:** In `IR_Construct_Record` codegen (`emit_expr.odin:1773-1781`), the
`fn_idx` field translation from decl index to WASM function index only handles
`IR_Literal_Int`. The closure converter produces `IR_Var` with name = closed function name.
This `IR_Var` goes through normal emit which hits `env.func_map[u64(e.name)]` — this
should work IF the closed function name is in `func_map`.

**Debugging steps:**
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
2. Build and run to confirm the trap
3. Inspect the generated WASM (use `wasm2wat`) to check:
   - Is the element table populated for the closed function?
   - Is `fn_idx` in the closure record pointing to a valid table entry?
   - Does `call_indirect` use the right type index?
4. Likely fix locations:
   - **`src/ir/closure_convert.odin:539-544`**: The `fn_idx_var` IR_Var for the closed
     function may need to be an `IR_Literal_Int` referencing the decl index, so the
     `decl_to_wasm_fn_idx` translation in `emit_expr.odin:1774` kicks in. OR:
   - **`src/codegen/emit_expr.odin:1773-1781`**: Extend the fn_idx translation to also
     handle `IR_Var` by checking `env.func_map` directly.
   - **`src/codegen/codegen.odin`**: Ensure closed functions generated during closure
     conversion are registered in `func_map` AND `decl_to_wasm_fn_idx`.

**Key insight:** The `decl_to_wasm_fn_idx` map (populated at `codegen.odin:848-883`)
maps decl index → WASM function index. But `IR_Literal_Int` for fn_idx stores the
decl index. The codegen translates it. For `IR_Var`, the emit path goes through
`func_map` which uses Intern_ID keys. Both paths should reach the same WASM index.

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

The approach mirrors how `IR_Match` handles tag unions, but simpler since we know
both operands have the same type:

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
    
    // 2. Load tag bytes from both operands
    // Tag byte is at offset CAMP_TAG_TAG_OFFSET (4) from heap pointer
    left_ir := lower_texpr(e.left, env)
    right_ir := lower_texpr(e.right, env)
    
    // Generate: tag_index(left) == tag_index(right) && payload_eq
    // Tag comparison: load byte at offset 4 from each, compare with I32_Eq
    
    // For each tag, generate a match arm:
    //   if tag == tag_i: compare payloads field by field
    // Chain all tag-specific comparisons with OR
    // But only if tag matches for BOTH sides
    
    // Simpler approach: compare tag bytes, then if equal, compare payloads
    // using a match-like structure
    
    // ... (detailed IR construction)
}
```

**Alternative simpler approach** (recommended for first pass):
Since tag unions are heap-allocated with a discriminant byte, generate:
```
let tag_l = load_u8(left, CAMP_TAG_TAG_OFFSET)
let tag_r = load_u8(right, CAMP_TAG_TAG_OFFSET)
if tag_l != tag_r { return False }
// Same tag — compare payloads
// For each tag variant with payloads:
//   if tag_l == TAG_I_INDEX:
//     return (left.payload0 == right.payload0) && (left.payload1 == right.payload1) && ...
// Tags with no payloads: return True (tag bytes already match)
```

**Use existing IR nodes:** `IR_I32_Load` (load tag byte), `IR_BinOp(.Eq)` (compare),
`IR_If` (branch), `IR_Field_Access` (payload access).

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

At the WASM level, `Hasher` is a heap-allocated record holding:
- `[0..7]`: SipHash state v0 (i64)
- `[8..15]`: SipHash state v1 (i64)
- `[16..23]`: SipHash state v2 (i64)
- `[24..31]`: SipHash state v3 (i64)
- `[32..35]`: byte count / tail
- `[36..39]`: tail length

### New Runtime_Func entries needed

```odin
// In Runtime_Func enum:
Hash_Init,        // () -> i32 (Hasher pointer)
Hash_Write_Byte,  // (hasher: i32, byte: i32) -> i32 (hasher)
Hash_Write_I64,   // (hasher: i32, val: i64) -> i32 (hasher)
Hash_Write_I32,   // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_I16,   // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_I8,    // (hasher: i32, val: i32) -> i32 (hasher)
Hash_Write_F64,   // (hasher: i32, val: f64) -> i32 (hasher)
Hash_Write_F32,   // (hasher: i32, val: f32) -> i32 (hasher)
Hash_Write_Str,   // (hasher: i32, str: i32) -> i32 (hasher)
Hash_Finish,      // (hasher: i32) -> i64 (hash value)
```

### SipHash-1-3 Implementation

Implement in WASM bytecode (`src/codegen/runtime.odin`). The algorithm:

**Initialization:**
```
v0 = k0 ^ 0x736f6d6570736575
v1 = k1 ^ 0x646f72616e646f6d
v2 = k0 ^ 0x6c7967656e657261
v3 = k1 ^ 0x7465646279746573
```
Default key: k0 = k1 = 0 (no key mixing needed for hash maps).

**Compression round (SipRound):**
```
v0 += v1; v2 += v3
v1 = ROTL(v1, 13); v3 = ROTL(v3, 16)
v1 ^= v0; v3 ^= v2
v0 = ROTL(v0, 32)
v0 += v3; v2 += v1
v1 = ROTL(v1, 17); v3 = ROTL(v3, 21)
v1 ^= v3; v2 ^= v0
v2 = ROTL(v2, 32)
```

**Finalization:**
```
v2 ^= 0xff
// 4 SipRounds
v0 ^= v1 ^ v2 ^ v3
return v0
```

**WASM implementation notes:**
- Use `i64.add`, `i64.xor`, `i64.rotl` (via `i64.shl` + `i64.shr_u` + `i64.or`)
- WASM has no native `i64.rotl` — implement as `(x << n) | (x >>> (64 - n))`
- SipHash-1-3 uses 1 compression round and 3 finalization rounds

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

### Implementation pattern (using List_eq as example)

**Runtime function signature:** `camp_list_eq(eq_fn_idx: i32, list_a: i32, list_b: i32) -> i32`

**Codegen interception** in `emit_expr.odin`:
```odin
if name_str == "List_eq" && len(e.args) == 2 {
    // Resolve the element type's Eq.eq function index
    eq_fn_idx := resolve_eq_fn_for_type(element_type, env)
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

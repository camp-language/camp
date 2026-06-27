---
# camp-yxts
title: Container eq/compare/hash runtime funcs do i32.load on unboxed I64 payloads (read half)
status: todo
type: bug
priority: high
tags:
    - codegen
created_at: 2026-06-20T03:02:58Z
updated_at: 2026-06-27T23:21:00Z
blocked_by:
    - camp-24mj
---

## Problem

`Result_Eq`/`Result_Compare`/`Result_Hash` and `List_Compare`/`List_Hash`
(`src/codegen/container_hash.odin`) read tag-union payloads with `i32.load` at
`CAMP_TAG_FIELDS_OFFSET`. I64 payloads are stored **unboxed** as raw 8 bytes, so
`i32.load` reads only the low 4 bytes — an I64 value of `0x1_0000_0001` would
compare equal to `0x1`.

This is the same pre-existing limitation as `Result.debug`, which has a special
`Result_Debug_I64` path (`emit_result_debug_i64_body`) that calls `I64_To_Str`
directly.

## Also missing

`Wasm_I32_Wrap_I64{}` when passing the tag-union value to Result runtime fns. The
tag-union pointer may be promoted to i64 in some contexts; `List.debug` already
handles this at `src/codegen/emit_expr.odin:556-557`. The Result eq/compare/hash
dispatch (lines ~1209-1337) does not.

## Fix direction

Mirror `Result_Debug_I64`:
1. Detect when both Result variants' payloads are I64 (or List element is I64).
2. Emit a specialized runtime body using `i64.load` instead of `i32.load`.
3. Add the `Wasm_I32_Wrap_I64{}` wrap in the Result dispatch sites
   (`src/codegen/emit_expr.odin`).

Blocked on `camp-24mj` (trait method compilation) because the I64 path currently
relies on the pre-registered `I64_compare` runtime function, but the non-I64 path
needs trait methods compiled first to be testable end-to-end.

## Test

```
import List { compare }
import Order { [Less, Equal, Greater] }
main! = || -> I64 {
  match List.compare([1, 2, 3], [1, 2, 3]) { Equal => 1; _ => 0 }
}
```
Currently traps (signature mismatch — `I64_compare` is `(i64,i64)->i32` but
`call_indirect` expects `(i32,i32)->i32`); needs the I64-specialized path.

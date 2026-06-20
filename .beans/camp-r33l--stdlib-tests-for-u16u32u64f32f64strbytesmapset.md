---
# camp-r33l
title: Stdlib tests for U16/U32/U64/F32/F64/Str/Bytes/Map/Set
status: partial
type: task
priority: normal
created_at: 2026-06-06T22:45:06Z
updated_at: 2026-06-20T23:05:00Z
blocked_by: camp-yxts, camp-24mj
---

Add test blocks to stdlib modules that currently lack them: U16.camp, U32.camp, U64.camp, F32.camp, F64.camp, Str.camp, Bytes.camp, Map.camp, Set.camp. Follow existing test patterns (single test block per file to avoid camp test hang). Test order: happy path, boundary values, identity.

## Status

**Completed (tests added and passing):**
- U16.camp — "U16 traits" test block with boundary value `65535`
- U32.camp — "U32 traits" test block with boundary value `4294967295`
- U64.camp — "U64 traits" test block with boundary value `4294967295`
- F32.camp — "F32 traits" test block (F32 codegen bug fixed: see camp-f32b).
- F64.camp — "F64 traits" test block with float comparisons

I32.camp additionally consolidated from two `test` blocks ("I32 equality" + "I32 ordering", which both pre-existed but never passed under `camp test`) into a single "I32 traits" block to match the one-test-per-file convention noted in this bean and to actually pass (pre-existing I32-codegen bug also fixed by the `lower_texpr` `TExpr_Int`/`TExpr_Float` type re-resolution change in camp-f32b).

**Blocked:**
- Str.camp — Entire public API is `crash "intrinsic: ..."` stubs that trap at runtime. String comparison (`"a" == "a"`) traps (no native string compare). No testable runtime surface exists.
- Bytes.camp, Map.camp, Set.camp — `Bytes.new` / `Map.new` / `Set.new` fail type-check with "tag union does not match record" before any test body can run.

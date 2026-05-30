---
id: camp-c3d4
title: Implement Debug trait for stdlib types
status: todo
type: task
priority: high
created_at: 2026-05-30T16:21:00Z
updated_at: 2026-05-30T16:21:00Z
---

Stdlib defines `Debug : { debug : |Self| -> Str }` in `stdlib/Debug.camp`.
No types implement it. Already partially wired in compiler — runtime has `I64_To_Str`, `I32_To_Str`, `F64_To_Str`, `Bool_To_Str` intrinsics used for expect rich messages. Work needed to plumb these through trait dispatch.

Type-specific considerations:
- Num types: delegate to existing `to_str` intrinsic (e.g. `I64.to_str`)
- Bool: delegate to `Bool.to_str`
- Str: return self (`|s| -> Str { s }`)
- Bytes: hex/display format
- List: `[elem1, elem2, ...]` format — recursive
- Result: `Ok(val)` / `Err(err)` format
- Map: `{k1: v1, k2: v2}` format
- Set: `{e1, e2, ...}` format
- Path: string representation
- Duration: human-readable format
- Uri: string representation
- Uuid: standard 8-4-4-4-12 hex format
- Regex: pattern string
- Json: pretty-print format

Requires trait resolution in typechecker to wire calls like `x->debug()` to the correct `X_To_Str` intrinsic.

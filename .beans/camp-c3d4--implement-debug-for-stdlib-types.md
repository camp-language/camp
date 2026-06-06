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
---

## ✅ Done (PR #95)
- Debug trait registered in prelude
- `derives Debug` works in canonicalize
- `*_debug` codegen for I64, I32, F64, F32, Bool, Str (maps to `*_to_str` runtime functions)
- All stdlib types have `is Debug` blocks
- `Order is Debug` done in pure Camp

## ❌ Remaining: Runtime `*_to_str` / `*_debug` implementations
The `*_to_str` runtime functions in `src/codegen/runtime.odin` are STUBS — they return null.
Need hand-written WASM implementations for:

### Primitives (delegate to `*_debug`):
- `emit_camp_i64_to_str_body` — convert I64 to decimal string
- `emit_camp_i32_to_str_body` — convert I32 to decimal string
- `emit_camp_f64_to_str_body` — convert F64 to decimal string (non-trivial)
- `emit_camp_bool_to_str_body` — return "True" or "False"

### Opaque types (recursive content formatting):
- `emit_camp_map_debug_body` — `{k1: v1, k2: ...}` format
- `emit_camp_list_debug_body` — `[a, b, ...]` format
- `emit_camp_result_debug_body` — `Ok(v)` / `Err(e)` format
- `emit_camp_set_debug_body` — `{e1, e2, ...}` format
- `emit_camp_json_debug_body` — JSON pretty-print
- `emit_camp_duration_debug_body` — human-readable
- `emit_camp_uuid_debug_body` — 8-4-4-4-12 hex
- `emit_camp_bytes_debug_body` — hex dump
- `emit_camp_path_debug_body` — string repr
- `emit_camp_uri_debug_body` — string repr
- `emit_camp_regex_debug_body` — pattern string
- `emit_camp_base64_debug_body` — base64 string
- `emit_camp_char_debug_body` — quoted char

Each requires:
1. Add to `Runtime_Func` enum in `emit_expr.odin`
2. Write body emission function in `runtime.odin`
3. Wire type, add function, append code in `codegen.odin`
4. Handle call in `emit_expr.odin` `IR_Call` handler

Reference: `emit_camp_str_eq_body` (line 669) and `emit_camp_bool_to_str_body` (line 3749) for patterns.

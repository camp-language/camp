---
# camp-d3k2
title: Remove hand-written runtime intrinsics for primitive trait methods
status: blocked
type: task
priority: low
tags:
    - codegen
    - traits
    - runtime
created_at: 2026-06-22T06:30:00Z
updated_at: 2026-06-22T06:30:00Z
blocked_by:
    - camp-d3k1
---

`src/codegen/runtime.odin` contains hand-written WASM bodies for primitive
trait methods. These are registered in `func_map` before IR decls, so stdlib
impls overwrite them when available. Functions to remove:

**Compare bodies** (lines ~977-1006):
- `emit_i64_compare_body` — `I64_compare`, `I32_compare`, `I16_compare`,
  `I8_compare`, `U64_compare`, `U32_compare`, `U16_compare`, `U8_compare`,
  `F64_compare`, `F32_compare`
- `emit_bool_compare_body` — `Bool_compare`
- `emit_str_compare_body` — `Str_compare`, `Bytes_compare`
- `emit_char_compare_body` — `Char_compare`

**Debug trampolines**:
- `emit_i64_debug_trampoline_body` — `I64_debug`, `I32_debug`, etc.

**Hash bodies**:
- Similar pattern for `I64_hash`, `Bool_hash`, etc.

**Design B trampolines** (camp-ty9s):
- `emit_i64_trampoline_body` — raw i32 → Order cell bridge
- `emit_box_i64_key` — i64 key boxing for Map/Set

Once prelude impl registrations are removed (camp-d3k1) and all primitives
are always-compiled (camp-df9d), these become dead code. The func_map
registrations at lines ~977-1006 can also be removed.

---
# camp-d3k3
title: Add Display stdlib impls for primitive types
status: todo
type: task
priority: low
tags:
    - stdlib
    - traits
created_at: 2026-06-22T06:30:00Z
updated_at: 2026-06-22T06:30:00Z
blocked_by:
    - camp-df9d
---

All 5 Display impls (Str, I64, I32, F64, Bool) currently exist only in the
prelude (`src/semantics/prelude.odin:413-441`). No stdlib module has `is Display`
declarations. Once types are always-compiled, add Display impls to their
stdlib modules. Each impl body calls the existing runtime intrinsic:

- `stdlib/Str.camp`: `Str is Display { to_str = |val: Str| -> Str { val } }`
- `stdlib/Bool.camp`: `Bool is Display { to_str = |val: Bool| -> Str { crash "intrinsic: Bool_to_str" } }`

For I64, I32, F64 — these don't have stdlib modules yet (no always-compiled
modules). Their Display impls stay in the prelude until the Num modules are
always-compiled. If Num modules don't exist yet, create `stdlib/Num/I64.camp`
etc., or add Display impls to existing stdlib modules that reference these
types.

This is the last trait without stdlib coverage — Ord, Hash, Debug, Eq, Default
all have stdlib impls.

Test: verify `Bool_to_str` resolves to the stdlib impl (not prelude fallback)
by checking func_map after compilation.

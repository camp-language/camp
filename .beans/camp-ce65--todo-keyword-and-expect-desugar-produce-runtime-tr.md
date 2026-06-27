---
# camp-ce65
title: todo keyword and expect desugar produce runtime traps with no compile-time location context
status: todo
type: task
priority: low
tags:
    - codegen
created_at: 2026-06-24T04:27:22Z
updated_at: 2026-06-27T23:21:00Z
---

Source: error-path sweep.
- src/ir/lower.odin:318-336 — TExpr_Todo lowers to runtime crash "todo: not implemented" — no compile-time diagnostic telling the user where todo was used. Should at least emit a warning/note pinning the span, or a structured test-failure diagnostic.
- src/semantics/canonicalize.odin:724-737 — expect x desugars to if !x { crash "expectation failed" }. The message is opaque, carries no source location or expression text. Test-time assertion failures are runtime traps, not structured test diagnostics.
- src/codegen/emit_expr.odin:3216 — IR_Crash message is computed then discarded (Wasm_Drop) before camp_exit; runtime crashes carry no message context (see camp-ityu for that specific codegen fix — this bean covers the source-level desugar quality).

Done: todo emits a compile-time note/warning at its span (related to C0911 must_use pattern / unreachable analysis). expect failures in test mode produce structured assertion diagnostics with span + expr text rather than opaque "expectation failed".

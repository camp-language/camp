---
# camp-ityu
title: 'Codegen silent traps: Nominal_Construct multi-payload, binop Exp, IR_Method_Call, crash message discarded'
status: todo
type: bug
priority: high
tags:
    - codegen
created_at: 2026-06-24T04:27:11Z
updated_at: 2026-06-24T04:27:11Z
---

Source: error-path sweep. Several codegen paths emit Wasm_Unreachable / camp_exit silently with no diagnostic context:
- src/codegen/emit_expr.odin:3273-3278 — IR_Expr_Nominal_Construct for qualified variants or multi-payload newtypes emits Wasm_Unreachable ("not yet implemented") — should be a compile error, not runtime trap.
- src/codegen/emit_expr.odin:3330-3331 — binop .Exp emits Wasm_Unreachable; exponentiation unsupported at codegen (silent trap).
- src/codegen/emit_expr.odin:2551-2556 — IR_Method_Call reaching codegen traps via camp_exit(1) ("compiler bug"); should be diag_internal (C9000) with context.
- src/codegen/emit_expr.odin:3054,3057,2857 — Wasm_Unreachable fallbacks in par-for-each / write! op handling.
- src/codegen/emit_expr.odin:3216-3223 — IR_Crash: the crash message is computed then dropped (Wasm_Drop) before camp_exit(1); runtime crashes carry no diagnostic.

Done: each path either emits a proper compile-time diagnostic or, for IR_Method_Call, diag_internal with span. Nominal_Construct multi-payload and .Exp become real features or emit a "not yet implemented" error. Crash message reaches runtime. E2E tests cover each.

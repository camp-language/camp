---
# camp-epa1
title: 'Convert #partial switch fallthroughs to total switch with diagnostic-emitting defaults'
status: todo
type: task
priority: normal
tags:
    - codegen
    - typecheck
created_at: 2026-06-24T04:27:01Z
updated_at: 2026-06-27T17:13:12Z
---

Source: docs/language-spec.md §15 "#partial switch fallthroughs". 16 dispatch functions use #partial switch with silent fallthroughs. Convert to total switch with diagnostic-emitting defaults to prevent future silent gaps.

Target files: src/semantics/typecheck.odin, check_expr.odin, check_control.odin, canonicalize.odin, src/ir/lower.odin, effect_lower.odin, src/codegen/emit_expr.odin, codegen.odin. Note: src/semantics/check_decl.odin:336 has a bare unreachable() after a partial switch over decl kinds — that should emit a proper internal-error diagnostic rather than crash.

Done: `odin test src` passes with no #partial switch in dispatch functions; a genuinely unhandled variant emits diag_internal (C9000) with context instead of crashing.


[Updated 2026-06-27 per §15 sweep] Audit shows the gap is larger than the recipe's "16": 87 `#partial switch` occurrences remain across the 8 target files. Counts: emit_expr.odin (27), lower.odin (22), codegen.odin (8), check_control.odin (8), typecheck.odin (7), effect_lower.odin (6), check_expr.odin (5), canonicalize.odin (4). The §15 entry for this gap has been removed from docs/language-spec.md; this bean is the sole tracker.

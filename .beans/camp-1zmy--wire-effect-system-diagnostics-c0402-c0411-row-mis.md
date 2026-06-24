---
# camp-1zmy
title: Wire effect-system diagnostics C0402-C0411 (row mismatch, unnecessary effect, effect-not-in-scope, handler signature/resume, redundant handler, subtype warning)
status: todo
type: task
priority: high
tags:
    - diagnostics
    - effects
created_at: 2026-06-24T04:26:40Z
updated_at: 2026-06-24T04:26:40Z
---

Source: docs/diagnostics-catalog.md §5.3-5.11 (marked Critical priority). Constructors exist in src/diagnostics/constructors.odin but never emitted from src/ir/effect_lower.odin or src/semantics/:
diag_effect_row_mismatch C0402 (:1612), diag_unnecessary_effect_in_signature C0403 (:1644), diag_effect_not_in_scope C0404 (:1668), diag_handler_signature_mismatch C0405 (:1686), diag_missing_resume C0406 (:1708), diag_double_resume C0407 (:1726), diag_invalid_resume C0408 (:1740), diag_redundant_handler C0409 (:1751), diag_effect_row_subtype C0410 (:1772).
Also diag_unhandled_effect exists (:209) but only referenced in test_diagnostic.odin — never emitted in src/. Catalog §C9000 notes "perform without handler evidence" should become C0408, "handler arm has wrong parameter count"→C0405, "operation not found in effects"→C0404 — these currently surface as internal errors (diag_internal).

Done: e2e snapshots per code emitted from effect phases; internal-error call sites converted to user-facing diagnostics. Catalog rows flipped to ✅.

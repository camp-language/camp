---
# camp-xuen
title: Wire pattern-matching diagnostics C0502-C0509 (non-exhaustive tag union, fragile match, irrefutable pattern, record pattern field errors, duplicate binding, wildcard-after-catch-all)
status: todo
type: task
priority: high
tags:
    - diagnostics
    - typecheck
created_at: 2026-06-24T04:26:40Z
updated_at: 2026-06-24T04:26:40Z
---

Source: docs/diagnostics-catalog.md §6.3, §6.5-6.10. Constructors exist in src/diagnostics/constructors.odin but never emitted:
diag_non_exhaustive_tag C0502 (:1794) — catalog §C9000 notes "non-exhaustive match" currently surfaces as internal error, should become C0502. diag_fragile_match C0504 (:1817), diag_invalid_irrefutable_pattern C0505 (:1833), diag_missing_field_pattern C0506 (:1848), diag_unknown_field_pattern C0507 (:1862), diag_duplicate_binding_pattern C0508 (:1881), diag_wildcard_after_catch_all C0509 (:1895).

Done: e2e snapshots per code from src/semantics exhaustiveness/pattern checking. Catalog rows flipped to ✅.

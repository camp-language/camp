---
# camp-4613
title: design question — should `$x = $x` (undeclared LHS) reach C1001 NO-OP ASSIGNMENT before C0200 UNDEFINED NAME?
status: todo
type: bug
priority: normal
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-21T03:00:00Z
---

## Symptom

A bare `$x = $x` with NO prior declaration of `$x` fires **C0200 UNDEFINED NAME** on the RHS (`$x` referenced before its declaration completes), NOT C1001 NO-OP ASSIGNMENT. Reaching C1001 requires `$x` to already be declared (`$x = 1; $x = $x` — which after the camp-jrga check_shadow fix cleanly reaches C1001).

## Where

src/analysis/unused.odin:478-495 `collect_uses_assign`. `is_self_assignment` (unused.odin:536-544) runs only inside the `if _, exists := analysis.bindings[name]; exists` branch (existing binding = reassignment). If `$x` is undeclared, control takes the `else` branch (first-assignment = declaration) and `is_self_assignment` is never called → C1001 never fires. Name resolution emits C0200 (src/semantics/typecheck.odin:381-384) on the RHS `$x` during typecheck, which runs before the unused-analysis pass.

## Design question

Per docs/diagnostics-catalog.md §11.2, C1001 NO-OP ASSIGNMENT says "`$x = $x` is always a mistake" — implying the self-assignment lint should fire. But the compiler cannot reach C1001 from a bare `$x = $x` because the self-assign check requires the binding to exist. Current behavior (C0200 undefined) is defensible (the RHS `$x` genuinely isn't in scope yet), but it diverges from the catalog's "always a mistake" framing for the bare form.

## Decision recorded in camp-jrga (for the e2e test)

The `tests/e2e/unused-analysis/self-assignment` e2e test was rewritten to `$x = 1; $x = $x` to exercise C1001 (the minimal form that reaches it), asserting C1001 via single-file build. The bare `$x = $x` form is NOT tested. This bean records the open design question: should the bare form lint as C1001 (requiring the self-assign check to run pre-declaration or name resolution to defer), or is C0200 the intended behavior? Needs project-owner decision.

## Files

- src/analysis/unused.odin:478-495 (collect_uses_assign)
- src/analysis/unused.odin:536-544 (is_self_assignment)
- src/semantics/typecheck.odin:381-384 (C0200 emission)
- docs/diagnostics-catalog.md §11.2 (C1001 spec)

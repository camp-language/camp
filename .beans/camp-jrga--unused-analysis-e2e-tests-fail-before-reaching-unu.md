---
# camp-jrga
title: Unused analysis e2e tests fail before reaching unused pass — 12/14 tests caught by name resolution/shadowing first
status: todo
type: bug
priority: normal
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

14 e2e tests in `tests/e2e/unused-analysis/` all expect `exit=1`, but only 2 of them actually reach the unused-analysis pass:

| Test | Expected error | Actual first error |
|------|---------------|-------------------|
| `contradictory-prefix` | C1000 (contrary prefix) | C0200 (UNDEFINED NAME) |
| `immutable-unused` | C0900 (unused binding) | C0200 (UNDEFINED NAME) |
| `record-escape` | (field escape tracking) | C0200 (UNDEFINED NAME) |
| `record-unused-field` | C0901 (unused field) | C0200 (UNDEFINED NAME) |
| `self-assignment` | C1001 (no-op assign) | C0200 (UNDEFINED NAME) |
| `shadowing-priority` | (shadowing > unused) | C0201 (SHADOWING) |
| `underscore-exempt` | (exempt from unused) | C0200 (UNDEFINED NAME) |
| `unused-import` | C0902 (unused import) | C0200 (UNDEFINED NAME) |
| `unused-pattern-binder` | (pattern binder unused) | C0200 (UNDEFINED NAME) |
| `var-loop-exempt` | (loop var exempt) | C0200 + C0201 |
| `var-loop-pure-unused` | (pure var unused) | C0200 + C0201 |
| `var-overwrite-before-read` | (overwrite warning) | C0201 (SHADOWING) |

**Only 2 tests reach unused analysis:** `pointless-eval` and `record-discard-not-use`.

## Root Cause

The tests reference undefined names (`items`, `expensive`, `process`, `Module`) or do shadowing. Name resolution (C0200/C0201) runs before unused analysis in the pipeline. The unused analysis passes never see these cases.

## Fix

Rewrite the 12 failing tests to use valid, in-scope bindings that exercise the unused-analysis rules. For example:
- `immutable-unused`: use a real function from stdlib/prelude instead of `items.length`
- `unused-import`: import a real prelude module instead of imaginary `Module`
- `self-assignment`: use `$x = 1` then `$x = $x` so `$x` is in scope

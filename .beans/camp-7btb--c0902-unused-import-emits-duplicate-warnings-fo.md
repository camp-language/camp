---
# camp-7btb
title: C0902 UNUSED IMPORT emits duplicate warnings for the same imported name
status: todo
type: bug
priority: low
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-21T03:00:00Z
---

## Symptom

`import List { length, map }` where NEITHER name is used emits THREE C0902 UNUSED IMPORT warnings: `length` TWICE and `map` once. Expected: one warning per unused imported name (two total).

## Reproduction

```
import List { length, map }
main! = || -> I64 { 42 }
```
via `camp check <file>`:
```
-- C0902: UNUSED IMPORT  `length` imported from `List` is never used.
-- C0902: UNUSED IMPORT  `length` imported from `List` is never used.   <- duplicate
-- C0902: UNUSED IMPORT  `map` imported from `List` is never used.
3 warning(s) found
```

## Where

- `register_import` (src/analysis/unused.odin:189-201) — appends one `Import_Info` per name (correct; one `length` entry).
- `check_unused_imports` (src/analysis/unused.odin:788-798) — iterates `analysis.imports` once per entry (looks correct).
- `mark_import_used` (src/analysis/unused.odin:204-211) — sets `used=true` on first match and returns.

So for a single unused `length`, only one C0902 should fire. The duplicate suggests `length` is registered TWICE in `analysis.imports`. Likely `collect_uses_cfile` (unused.odin:248-260) registers imports once, but the single-file build path may run the unused pass or register imports twice (e.g. once by `collect_uses_cfile` and once by `mark_import_used` appending, or the CFile.imports slice has `length` listed twice from canonicalization).

## Fix direction

Investigate why `analysis.imports` contains `length` twice. Grep `register_import` callers; check whether canonicalize (src/semantics/canonicalize.odin) duplicates import names for the `[Ok, Err]` variant-grouping form vs plain names. This is cosmetic but produces noisy output and messy e2e snapshots (the unused-import test in camp-jrga asserts the 3-warning form as a workaround).

## Files

- src/analysis/unused.odin:189-211 (register_import / mark_import_used)
- src/analysis/unused.odin:248-260 (collect_uses_cfile import registration)
- src/analysis/unused.odin:788-798 (check_unused_imports)
- src/semantics/canonicalize.odin (import canonicalization — possible duplicate)

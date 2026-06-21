---
# camp-g6h9
title: '`$count = $count + 1` (self-referential reassignment) where $count is otherwise unused does NOT fire C0904'
status: todo
type: bug
priority: normal
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-21T03:00:00Z
---

## Symptom

A `$`-var that is reassigned via a self-referential RHS (`$count = $count + 1`) and is otherwise never read does NOT fire C0904 UNUSED ASSIGNMENT, even though the assignment is pointless (the var is never consumed). A non-self-referential reassignment (`$count = 99`) in the same position DOES fire C0904.

## Reproduction

```
main! = || -> I64 {
  $count = 0
  $count = $count + 1      // self-ref RHS — NO C0904
  42
}
```
→ clean, no warnings. But:
```
main! = || -> I64 {
  $count = 0
  $count = 99              // non-self-ref — C0904 x2 fires
  42
}
```
→ C0904 (overwrite before read) + C0904 (final value never consumed).

## Where

src/analysis/unused.odin:478-495 `collect_uses_assign` — for a reassignment `$count = $count + 1`, the code calls `record_use(analysis, name, .Self_Assign_Rhs, assign.span)` (line 490) to mark the RHS read of `$count`. src/analysis/unused.odin:1009-1025 `assignment_has_read_before` then checks `use_sites` for `.Read / .Field_Access / .Escape_*` — `.Self_Assign_Rhs` is NOT in that set (excluded at binding_has_essential_use:854 too), so it should NOT suppress. Yet C0904 does not fire.

The suppression appears to come from `binding_has_essential_use` (unused.odin:849-859) excluding `.Self_Assign_Rhs` — returning false — which SHOULD make `!binding_has_essential_use(bi)` true in `check_reassignable_var` (unused.odin:975) and fire C0904 on the final assignment. So the missing C0904 indicates the final-assignment branch is not reached, OR `assignment_has_read_before` is returning true incorrectly for the non-final assignment.

## Why this matters (surfaced by camp-jrga)

The `tests/e2e/unused-analysis/var-loop-pure-unused` test originally used `$count = $count + 1`; it was rewritten to `$count = 99` to actually trigger C0904 (the self-ref form produced no warning). This gap means real pointless self-increment loops (`for _ in xs { $count = $count + 1 }` where `$count` is never read) are not flagged.

## Fix direction

Trace `check_reassignable_var` (unused.odin:945-1006) for the 2-assignment self-ref case. Likely `assignment_has_read_before` returns true because `.Self_Assign_Rhs` SHOULD be excluded but something includes it, OR the loop-exemption branch (unused.odin:977 `has_essential_reads_in_loop`) is wrongly firing. Needs debugging.

## Files

- src/analysis/unused.odin:945-1006 (check_reassignable_var)
- src/analysis/unused.odin:1009-1025 (assignment_has_read_before)
- src/analysis/unused.odin:849-859 (binding_has_essential_use)
- src/analysis/unused.odin:478-495 (collect_uses_assign — Self_Assign_Rhs recording)

---
# camp-xuen
title: Wire pattern-matching diagnostics C0502-C0509 (non-exhaustive tag union, fragile match, irrefutable pattern, record pattern field errors, duplicate binding, wildcard-after-catch-all)
status: in-progress
type: task
priority: high
tags:
    - diagnostics
    - typecheck
created_at: 2026-06-24T04:26:40Z
updated_at: 2026-06-27T03:35:23Z
---

Source: docs/diagnostics-catalog.md §6.3, §6.5-6.10. Constructors exist in src/diagnostics/constructors.odin but never emitted:
diag_non_exhaustive_tag C0502 (:1794) — catalog §C9000 notes "non-exhaustive match" currently surfaces as internal error, should become C0502. diag_fragile_match C0504 (:1817), diag_invalid_irrefutable_pattern C0505 (:1833), diag_missing_field_pattern C0506 (:1848), diag_unknown_field_pattern C0507 (:1862), diag_duplicate_binding_pattern C0508 (:1881), diag_wildcard_after_catch_all C0509 (:1895).

Done: e2e snapshots per code from src/semantics exhaustiveness/pattern checking. Catalog rows flipped to ✅.

Claimed & worked in worktree smores/wire-pattern-match-diagnostics.

Implemented (6/7):
- C0502 non-exhaustive tag union: src/semantics/check_control.odin typecheck_match. Recovers the closed variant set by walking the scrutinee's row chain via new helper collect_tag_row_variants (src/semantics/typecheck.odin) — the scrutinee's resolved var pointed at the pattern's open 1-entry row (post-unification), so the previous diag_internal fired nothing. Newtype-owned unions use store.newtype_decls[nt].owned_tags via new helper newtype_owning_tags. Anonymous unions use a pre-pattern snapshot (snapshot_tag_union_variants) since unification of a closed annotation row with an open pattern row decomposes the chain and (for payloaded unions) does not propagate the `closed` flag. Replaces the internal-error fallback.
- C0504 fragile match: fires only for newtype-owned unions with >1 variant matched exhaustively without a wildcard (anonymous `[A | B]` can't gain variants).
- C0506 missing field / C0507 unknown field: check_record_pattern_fields compares pattern field names against the scrutinee's resolved record row post-unification. Open patterns (`{ .. }` / `{ ..rest }`) exempt from C0506. C0506 suppressed when C0507 fires for the same pattern.
- C0508 duplicate binding: check_duplicate_bindings walks each match-arm pattern.
- C0509 wildcard-after-catch-all: refines C0503 redundancy detection — wildcard/var arm unreachable due to a prior catch-all gets C0509 (warning) instead of C0503.

C0505 (invalid irrefutable pattern): NOT implemented. Doc-vs-code discrepancy flagged in docs/diagnostics-catalog.md §6.6. Camp has no `let` keyword (recipe §Assignment: `name = expr`); statement-level destructuring (`{a,b}=record`, `[a,b,...rest]=list`, `@UserId(n)=uid`) is desugared to field-access assignments that never produce a refutable pattern. The constructor diag_invalid_irrefutable_pattern has no triggerable code path under current syntax. Re-evaluate if a `let`/refutable-binding form is ever introduced.

Bug fix: diag_missing_field_pattern (constructors.odin:1855) format string `{..}` was parsed as a fmt.tprintf placeholder → `%!(MISSING)` garbage. Escaped to `{{..}}`.

Tests: 6 e2e snapshots (tests/e2e/errors/{non-exhaustive-tag-match,fragile-match,missing-field-pattern,unknown-field-pattern,duplicate-binding-pattern,wildcard-after-catch-all}); updated tag-match-non-exhaustive snapshot (was wrongly expecting the non-exhaustive match to compile). 7 constructor unit tests (src/test_diagnostic.odin) + 9 semantic unit tests (src/test_check_control.odin). Catalog §6 rows flipped to Implemented (C0505 to Not Applicable).

Gate: format-check, test-unit (522), test-e2e (204), tree-sitter all green. test-doc-tests fails on stdlib/Bool.camp "Bool traits" — PRE-EXISTING on clean main (verified via git stash), unrelated to this work.

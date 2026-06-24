---
# camp-jh1r
title: Wire trait/generics + newtype diagnostics C0605-C0610, C0704 (missing constraint, conflicting impls, trait not found, supertrait, cyclic trait, ambiguous trait, newtype field access)
status: todo
type: task
priority: normal
tags:
    - diagnostics
    - traits
created_at: 2026-06-24T04:26:40Z
updated_at: 2026-06-24T04:26:40Z
---

Source: docs/diagnostics-catalog.md §7.6-7.11, §8.5. Constructors exist in src/diagnostics/constructors.odin but never emitted:
diag_missing_trait_constraint C0605 (:1908), diag_conflicting_implementations C0606 (:1928), diag_trait_not_found C0607 (:1949 — catalog §C9000 notes "trait not found in registry" → C0607), diag_supertrait_not_satisfied C0608 (:1967), diag_cyclic_trait_dependency C0609 (:1989), diag_ambiguous_trait_resolution C0610 (:2004), diag_newtype_field_access C0704 (:2025).

Done: e2e snapshots per code from trait-resolution/newtype phases. Catalog rows flipped to ✅.

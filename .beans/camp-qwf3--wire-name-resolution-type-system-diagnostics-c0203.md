---
# camp-qwf3
title: Wire name-resolution + type-system diagnostics C0203-C0320 (undefined type/effect, private access, not-a-function/type, record field errors, row unification, recursive alias, invalid main, etc.)
status: todo
type: task
priority: high
tags:
    - diagnostics
    - typecheck
created_at: 2026-06-24T04:26:31Z
updated_at: 2026-06-28T02:19:55Z
---

Source: docs/diagnostics-catalog.md §3.4-3.9 and §4.8-4.21. Constructors exist in src/diagnostics/constructors.odin but never emitted from src/semantics/{check_expr,check_decl,typecheck,canonicalize,unify}.odin:
Name res: diag_undefined_type C0203 (:1239), diag_undefined_effect C0204 (:1257), diag_private_access C0205 (:1275), diag_ambiguous_reference C0206 (:1302), diag_not_a_function C0207 (:1324), diag_not_a_type C0208 (:1343).
Type sys: diag_cannot_infer_return C0307 (:1375), diag_type_annotation_mismatch C0308 (:1386), diag_missing_field C0309 (:1409), diag_unknown_field C0310 (:1429), diag_field_type_mismatch C0311 (:1448), diag_cannot_unify_effect_rows C0312 (:1469), diag_row_label_mismatch C0313 (:1507), diag_type_param_kind_mismatch C0314 (:1530), diag_recursive_type_alias C0315 (:1553), diag_invalid_main_signature C0316 (:1567), diag_newtype_coercion C0702 (:610, marked defined-but-unused).

Done: e2e snapshot tests per code, emitted from semantic phases. Catalog rows flipped to ✅. May need splitting — if so create children under this parent.


## Update (gap-discovery sweep, 2026-06-28)
Verified emit sites per code. The body above is stale on two points:
- **C0203 (`diag_undefined_type`) is already WIRED** — emit sites at `src/semantics/typecheck.odin:564` and `src/semantics/check_expr.odin:528`. Catalog §3.4 row was flipped to ✅ Implemented; summary table updated. Drop C0203 from this bean's scope.
- **C0306 (`diag_ambiguous_type`, constructors.odin:1023) and C0320 (`diag_tuple_pattern_count`, constructors.odin:2363) are NOT-WIRED** and were missing from the bean body's enumerated list. Add them to scope.

Net scope after correction: C0204, C0205, C0206, C0207, C0208 (Name Resolution, 5 codes) + C0306, C0307–C0316, C0320 (Type System, 12 codes) + C0702 (newtype coercion) = 18 codes. Consider splitting into child beans: one for §3 Name Resolution (C0204-C0208) and one for §4 Type System (C0306, C0307-C0316, C0320), matching the camp-1zmy/camp-xuen/camp-jh1r per-domain pattern.

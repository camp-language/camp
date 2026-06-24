---
# camp-qwf3
title: Wire name-resolution + type-system diagnostics C0203-C0320 (undefined type/effect, private access, not-a-function/type, record field errors, row unification, recursive alias, invalid main, etc.)
status: todo
type: task
priority: normal
tags:
    - diagnostics
    - typecheck
created_at: 2026-06-24T04:26:31Z
updated_at: 2026-06-24T04:26:31Z
---

Source: docs/diagnostics-catalog.md §3.4-3.9 and §4.8-4.21. Constructors exist in src/diagnostics/constructors.odin but never emitted from src/semantics/{check_expr,check_decl,typecheck,canonicalize,unify}.odin:
Name res: diag_undefined_type C0203 (:1239), diag_undefined_effect C0204 (:1257), diag_private_access C0205 (:1275), diag_ambiguous_reference C0206 (:1302), diag_not_a_function C0207 (:1324), diag_not_a_type C0208 (:1343).
Type sys: diag_cannot_infer_return C0307 (:1375), diag_type_annotation_mismatch C0308 (:1386), diag_missing_field C0309 (:1409), diag_unknown_field C0310 (:1429), diag_field_type_mismatch C0311 (:1448), diag_cannot_unify_effect_rows C0312 (:1469), diag_row_label_mismatch C0313 (:1507), diag_type_param_kind_mismatch C0314 (:1530), diag_recursive_type_alias C0315 (:1553), diag_invalid_main_signature C0316 (:1567), diag_newtype_coercion C0702 (:610, marked defined-but-unused).

Done: e2e snapshot tests per code, emitted from semantic phases. Catalog rows flipped to ✅. May need splitting — if so create children under this parent.

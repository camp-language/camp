---
# camp-hfso
title: Wire parser diagnostics C0110-C0121 (duplicate fields/variants/effects, invalid match arm, visibility, effect-row syntax, tuple sizes)
status: completed
type: task
priority: normal
tags:
    - diagnostics
    - parser
created_at: 2026-06-24T04:26:31Z
updated_at: 2026-06-27T03:24:27Z
---

Source: docs/diagnostics-catalog.md §2.10-2.21. Constructors exist in src/diagnostics/constructors.odin but never emitted from src/frontend/parser.odin:
- diag_duplicate_field_literal C0110 (:1148), diag_duplicate_field_pattern C0111 (:1159), diag_duplicate_variant C0112 (:1170), diag_duplicate_effect_row C0113 (:1181), diag_invalid_match_arm C0114 (:1193), diag_missing_arrow_fn_type C0115 (:1204), diag_invalid_visibility C0116 (:1215), diag_invalid_effect_row_syntax C0117 (:1226), diag_tuple_pattern_count C0320 (:2363), diag_empty_tag_union C0318 (:1596), diag_duplicate_type_param C0317 (:1582), diag_raw_id_not_needed C0209 (:1358).

Done: e2e snapshot tests for each code, emitted from parser. Catalog rows flipped to ✅.

---
# camp-ip4r
title: Wire module/import + unused/lint + Perceus + CLI diagnostics (C0808-C0811, C0906-C0913, C1100-C1102, C1204-C1207)
status: todo
type: task
priority: normal
tags:
    - diagnostics
    - analysis
created_at: 2026-06-24T04:26:51Z
updated_at: 2026-06-24T04:26:51Z
---

Source: docs/diagnostics-catalog.md §9.9-9.12, §10.7-10.14, §12.1-12.3, §13.5-13.8. Constructors exist in src/diagnostics/constructors.odin but never emitted:
Module/import: diag_duplicate_import C0808 (:2046), diag_import_shadows_binding C0809 (:2061), diag_self_import C0810 (:2075), diag_suggest_import C0811 (:2086, Note).
Unused/lint: diag_unused_function C0906 (:2109), diag_unused_type_definition C0907 (:2121), diag_unused_type_parameter C0908 (:2132), diag_unused_effect_handler C0909 (:2146), diag_unreachable_code C0910 (:2160), diag_must_use_discarded C0911 (:2171), diag_redundant_else C0912 (:2186), diag_unnecessary_mutability C0913 (:2197).
Perceus: diag_reference_leak C1100 (:2214), diag_unnecessary_copy C1101 (:2229), diag_consume_after_use C1102 (:2240).
CLI: diag_output_dir_not_found C1204 (:2263), diag_invalid_option C1205 (:2274), diag_conflicting_options C1206 (:2286), diag_compilation_limit C1207 (:2301).

Done: e2e/unit tests per code from src/analysis/unused.odin (unused), src/build (CLI), and Perceus/codegen paths. Catalog rows flipped to ✅. Large scope — split into children if needed (unused-lint, perceus, cli-import as separate PRs).

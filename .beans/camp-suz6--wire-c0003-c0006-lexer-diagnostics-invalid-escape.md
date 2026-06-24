---
# camp-suz6
title: Wire C0003-C0006 lexer diagnostics (invalid escape, unterminated per-line string, invalid numeric literal, unterminated block comment)
status: todo
type: task
priority: normal
tags:
    - diagnostics
    - parser
created_at: 2026-06-24T04:26:31Z
updated_at: 2026-06-24T04:26:31Z
---

Source: docs/diagnostics-catalog.md §1.3-1.6. Four lexer constructors exist but are never emitted:
- diag_invalid_escape (C0003) — src/diagnostics/constructors.odin:1061
- diag_unterminated_per_line_string (C0004) — :1073
- diag_invalid_numeric_literal (C0005) — :1084
- diag_unterminated_block_comment (C0006) — :1102

Done looks like: e2e tests in tests/e2e/lexer/ (or similar) exercising each error with the expected C0xxx code emitted from src/frontend/lexer.odin. Kitchen-sink or snapshot updated via just update-snapshots. Catalog rows flipped from 🆕 to ✅.

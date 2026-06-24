---
# camp-unku
title: Parse lambda where-clauses (Expr_Lambda.where_clauses field never populated)
status: todo
type: task
priority: normal
tags:
    - parser
created_at: 2026-06-24T04:27:01Z
updated_at: 2026-06-24T04:27:01Z
---

Source: docs/syntax-recipe.md §15 "Lambda where-clauses". Expr_Lambda has where_clauses field in AST but src/frontend/parser.odin never populates it.

Fix: parse `where` after lambda body in parser.odin; plumb through canonicalize/typecheck/lower. Done: a camp test using a lambda with a where clause parses and passes semantic checks; kitchen-sink updated.

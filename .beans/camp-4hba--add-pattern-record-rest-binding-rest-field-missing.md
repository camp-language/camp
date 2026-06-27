---
# camp-4hba
title: Add Pattern_Record ..rest binding (rest field missing in AST)
status: todo
type: task
priority: normal
tags:
    - parser
created_at: 2026-06-24T04:27:01Z
updated_at: 2026-06-24T04:27:01Z
---

Source: docs/syntax-recipe.md §15 "Pattern_Record ..rest". Pattern_Record missing rest field for ..rest binding.

Fix: add rest: base.Intern_ID to AST, parse ..identifier in record patterns in src/frontend/parser.odin, plumb through canonicalize/typecheck/lower. Done: a match on a record using { field, ..rest } compiles and rest binds remaining fields.

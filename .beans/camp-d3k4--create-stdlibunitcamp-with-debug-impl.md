---
# camp-d3k4
title: Create stdlib/Unit.camp with Debug impl
status: todo
type: task
priority: low
tags:
    - stdlib
    - traits
created_at: 2026-06-22T06:30:00Z
updated_at: 2026-06-22T06:30:00Z
---

`Unit_debug` is registered in the prelude (`prelude.odin:509`) but has no
stdlib module. `Unit` is a Void-typed type so `Unit_debug` is unusual (returns
a fixed string "()"). Create `stdlib/Unit.camp` with:
- `Unit is Debug { debug = || -> Str { "()" } }`
- Add to STDLIB_MODULES and ALWAYS_COMPILE
- Update test_stdlib.odin count

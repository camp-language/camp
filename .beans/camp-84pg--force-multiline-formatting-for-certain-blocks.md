---
# camp-84pg
title: Force multiline formatting for certain blocks
status: done
type: task
priority: normal
created_at: 2026-05-29T07:01:28Z
updated_at: 2026-05-30T00:00:00Z
resolved_at: 2026-05-30T00:00:00Z
---

## Resolution

Decided block formatting rules after grilling session:

- **Block rule** (standalone, lambda, if/else, match arm, handler arm): single-line when exactly 1 expr item, expr is not match/return/assignment, expr is single-line per first-separator heuristic, no newline after `{`, no preceding comment.
- **Record rule** (record literals, par blocks, effect types, trait types): single-line when no newline after `{`, no preceding comment. Any field count OK.
- **Always multiline**: for loops, par for, handle in/with, test bodies, is impls, newtype method blocks.
- **Preceding comment** after `{` forces multiline. Trailing comment doesn't.
- **Match arm / handler arm bodies**: preserve braces vs bare as written.
- **Return, assignment**: always multiline as sole block items.
- **Crash, todo**: CAN be single-line (they're expressions).

Details written to docs/block-formatting-spec.md.

---
# camp-suz6dblw
title: Wire C0003-C0006 lexer diagnostics
status: in-progress
type: feature
priority: high
created_at: 2026-06-24T04:40:23Z
updated_at: 2026-06-24T16:00:58Z
---

## Implementation notes (camp-suz6)

Wired C0003, C0004, C0005 into src/frontend/lexer.odin. C0006 left as
defined-but-unused (Camp has no block comments per syntax-recipe §1;
user decision: skip C0006, mark not-applicable in catalog).

- C0003: `lexer_validate_string_escape` called from both scalar and SIMD
  string scan paths. Valid escapes: \n \t \r \\ \" \$ \0 (union of recipe
  and constructor hint — user decision).
- C0004: emitted in `lexer_lex_perline_string` when EOF reached before the
  closing newline of a \-line. Message reworded to match actual EOF model
  (no "closing \ alone on its own line" concept exists).
- C0005: `lexer_report_invalid_numeric` wired into hex/octal/binary lexers.
  Fixes a pre-existing infinite loop: `break` inside `switch` only broke
  the switch, not the surrounding `for` (out-of-base trailing digit like
  the 2 in `0b102` spun forever). Switched to labeled `break <label>`.

Catalog: C0003/C0004/C0005 flipped to ✅ Implemented; C0006 marked
Not Applicable; counts updated (68 implemented, 5 defined-but-unused,
54 proposed new).

Tests: 9 unit tests in src/test_lexer.odin; 3 e2e tests under
tests/e2e/errors/{invalid-escape,unterminated-perline-string,
invalid-numeric-literal}. `interpolation-raw` e2e snapshot updated
(its `\f` escape is now correctly flagged C0003).

`just check` is green except the pre-existing `test-doc-tests` failure
in stdlib/Bool.camp ("Bool traits" compilation failed) which also fails
on the unmodified baseline — unrelated to this change.

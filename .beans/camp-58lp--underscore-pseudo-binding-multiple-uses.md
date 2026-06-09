---
# camp-58lp
title: Make `_` a pseudo-binding usable multiple times
status: todo
type: bug
priority: medium
created_at: 2026-06-08T23:59:00Z
updated_at: 2026-06-08T23:59:00Z
---

## Problem

Using `_` more than once in the same scope triggers a shadowing error:

```camp
_ = foo()
_ = bar()
-- C0201: SHADOWING
-- `_` shadows a binding from an enclosing scope. All shadowing is forbidden.
```

This forces awkward workarounds like declaring unique names for discarded values.

## Proposed Fix

`_` should be treated as a pseudo-binding (like in Rust, Haskell, OCaml, etc.):
- Multiple `_ = expr` statements in the same scope should be allowed.
- `_` should never actually bind — it's a "don't care" pattern.
- No shadowing check should apply to `_`.

## Impact

- Affects canonicalization / name resolution (wherever shadowing is checked).
- Common use case: calling side-effectful intrinsics (e.g. `debug`, `print`) and discarding results.

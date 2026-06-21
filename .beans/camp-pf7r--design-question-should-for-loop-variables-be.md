---
# camp-pf7r
title: design question — should `for` loop variables be exempt from C0900 UNUSED BINDING when the loop var is iterated but never read?
status: todo
type: bug
priority: normal
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-21T03:00:00Z
---

## Symptom

```
main! = || -> I64 {
  for item in [1, 2, 3] {
    Console.println!("x")
  }
  0
}
```
fires **C0900 UNUSED BINDING** on `item` (the loop variable), because `item` is iterated but never read in the loop body. Many languages exempt loop variables from unused-binding warnings (the iteration itself is the "use"), or require `_item` to mark intent.

## Where

src/analysis/unused.odin:400-406 — the `^semantics.CExpr_For` case calls `register_binding(analysis, e.for_var, …)` registering the loop var as a normal binding. If the loop body never reads `e.for_var`, it has no `.Read` use site → C0900 fires in `check_immutable_binding` (unused.odin:801-847).

## Design question

Should Camp exempt loop variables from C0900 (treating "iterated" as a use), or is flagging an unread loop var the intended behavior (forcing `_item`)? The `tests/e2e/unused-analysis/var-loop-exempt` test name suggests exemption was intended ("loop var exempt"), but the compiler currently does NOT exempt. No spec/recipe text addresses this directly.

## Decision recorded in camp-jrga (for the e2e test)

The `var-loop-exempt` test was written with an UNREAD `item` and asserts C0900 on `item` via `args = "check-file"` (i.e. the test documents CURRENT behavior, not the "exempt" intent). If the project owner decides loop vars SHOULD be exempt, this test would need to flip to asserting NO C0900 (and the compiler would need a loop-var exemption in `collect_uses_expr` For case or `check_immutable_binding`).

## Files

- src/analysis/unused.odin:400-406 (CExpr_For — registers loop var)
- src/analysis/unused.odin:801-847 (check_immutable_binding — emits C0900)
- tests/e2e/unused-analysis/var-loop-exempt/Main.camp

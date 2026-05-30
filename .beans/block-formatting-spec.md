# Block Formatting Spec

## Overview

Camp's formatter decides whether a brace-delimited block renders single-line or multiline based on the block's contents and owner construct. Two distinct rule sets govern this decision: the **Block Rule** (expression blocks) and the **Record Rule** (field-oriented blocks).

---

## First Separator Break Heuristic

Both rules use the same low-level heuristic to determine if a child expression is itself "multiline":

Look at the original source. After the opening delimiter (`{`, `[`, `(`), does the **first separator** (comma between entries, newline between block stmts) have a newline in its gap? If yes, the expression is multiline. If there are no separators (single-item), the expression is flat.

This is the same logic already implemented for records, lists, calls, and tuples via `info.first_separator_break[span.start]`.

---

## Block Rule

Applies to: standalone blocks, lambda bodies, function bodies, if/else branches, match arm bodies, handler arm bodies.

A block is **single-line** when ALL of:
1. It contains exactly one item (the tail expression — no leading assignments/declarations)
2. That item is an **expression** (not `return`, not `$x = ...`, not a `for` loop body itself)
3. That expression is itself **single-line** (no newline at its level per the heuristic)
4. The original source had **no newline** after the opening `{` (checked via `first_separator_break`)
5. No **preceding comment** sits between `{` and the expression

Otherwise, the block is **multiline**.

### Expression types that force multiline when they are the sole block item:
- `match { ... }` — match is always multiline
- `return expr` — return is control flow, always multiline
- `$x = expr` — assignment/variable binding, always multiline

### Expression types that CAN be single-line as sole block item:
- Literals, identifiers, calls, tags, records, tuples, lists, field access, method calls, binops, prefix ops, lambdas, crash, todo, record updates, match (NO — this is counter to above), handle, par, if/else (yes), interpolated strings, dot lambdas, nested blocks

### Preserving braces for arm bodies
Match arms and handler arms can have bare expressions or block expressions as bodies. The formatter **preserves** whether the user wrote braces or not — it never adds or removes `{}` around an arm body. If the body is a `Expr_Block`, it formats per block rule; if it's any other expression, it stays bare.

---

## Record Rule

Applies to: record literals, par blocks, effect type bodies (`Console! : { ... }`), trait type bodies (`Eq : { ... }`).

A record-like block is **single-line** when:
1. The original source had **no newline** after the opening `{`
2. No **preceding comment** sits between `{` and the first field

(Number of fields is irrelevant — can have many comma-separated entries on one line.)

### Record rule vs block rule
Par blocks and type bodies follow the record rule because they are structurally records (name:value pairs). This means `par { x: expr, y: expr }` on one line is valid regardless of entry count.

---

## Always Multiline (Declaration-owned)

These brace-delimited constructs are **always multiline** regardless of content:

| Construct | Reason |
|---|---|
| `for x in xs { body }` | For loop body |
| `par for x in xs { body }` | For loop variant |
| `handle E! in body with { ... }` | Handle body and handler block |
| `test "name" { body }` | Declaration-owned |
| `Color is Eq { ... }` | Is impl (declaration-owned) |
| `@Name: T { ... }` | Newtype method block (declaration-owned) |
| `expect cond` | No braces |

---

## Summary Table

| Owner | Rule | Single-line possible? |
|---|---|---|
| Standalone expr block `{ expr }` | Block | Yes, 1 non-multiline expr |
| Lambda body `\|x\| -> T { expr }` | Block | Yes |
| If/else branch `if cond { expr }` | Block | Yes |
| Match arm body `Pattern => { expr }` | Block, preserve braces | Yes |
| Handler arm body `.op(res) => { expr }` | Block, preserve braces | Yes |
| Par block `par { name: expr }` | Record | Yes, any count |
| Function body `name = \|x\| { expr }` | Block (lambda) | Yes |
| For loop body `for x in xs { ... }` | Always multiline | No |
| Par for body `par for x in xs { ... }` | Always multiline | No |
| Handle `in` body `handle E! in expr` | Always multiline | No |
| Handle `with` block `with { ... }` | Always multiline (match-like) | No |
| Test body `test "name" { ... }` | Always multiline | No |
| Is impl `Color is Eq { ... }` | Always multiline | No |
| Newtype method block `@T: X { ... }` | Always multiline | No |
| Effect ops `Console! : { ... }` | Record | Yes |
| Trait methods `Eq : { ... }` | Record | Yes |
| Preceding comment after `{` | Forces multiline | No |

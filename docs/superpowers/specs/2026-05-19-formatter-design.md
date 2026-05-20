# Camp Formatter Design Specification

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture & Core Principles](#2-architecture--core-principles)
3. [CLI Interface & LSP Integration](#3-cli-interface--lsp-integration)
4. [Indentation & Spacing](#4-indentation--spacing)
5. [Multiline Heuristic](#5-multiline-heuristic)
6. [Declaration Formatting](#6-declaration-formatting)
7. [Expression Formatting](#7-expression-formatting)
8. [Type Formatting](#8-type-formatting)
9. [String Literals & Multiline Strings](#9-string-literals--multiline-strings)
10. [Comments & Blank Lines](#10-comments--blank-lines)
11. [Backslash Token](#11-backslash-token)
12. [Name Pun Records](#12-name-pun-records)
13. [Bracket Reference](#13-bracket-reference)

---

## 1. Overview

`camp fmt` is a zero-configuration source formatter for Camp. It always produces the same output for the same source program. There are no config files, no CLI flags that change formatting behavior, and no line-length limits.

The formatter is deterministic and idempotent: running it on already-formatted code produces identical output.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Zero config | No options | Eliminates formatting debates, consistent across all projects |
| No line-length limit | Programmer controls line breaks | No heuristics for "too long"; the programmer decides via first-separator/backslash |
| Hybrid AST + source-aware | Parse to AST, but use source positions for formatting choices | Guarantees well-formed output while preserving programmer intent (multiline, comments, blank lines) |
| Refuse on errors | No partial formatting | Output is always valid Camp |
| 4 spaces | Indentation | Consistent, no tab/space mixing |

---

## 2. Architecture & Core Principles

**Hybrid approach**: Parse source to AST (validating well-formedness), then pretty-print using a Wadler-style `Doc` IR. Source-position awareness is injected at Doc-construction time to drive the multiline heuristic (first-separator rule, backslash split points). Comments and blank lines are extracted from the source text using AST node positions and reattached during output.

**Error policy**: Refuse to format files with syntax errors. Exit with a diagnostic. This guarantees formatted output is always valid Camp.

**Core API**:

```
format(source: string, file_path: string) -> (string, []Diagnostic)
```

A pure function the LSP calls directly. CLI and `--check` mode are wrappers around this.

**Idempotency**: The formatter's output is a fixed point. Running `camp fmt` on already-formatted code produces identical output.

---

## 3. CLI Interface & LSP Integration

### CLI Modes

| Command | Behavior |
|---------|----------|
| `camp fmt [paths...]` | Format in-place (default). Paths can be files or directories (walks for `*.camp`). |
| `camp fmt --check [paths...]` | Diff-check only. Prints a diff of what would change. Exits 0 if formatted, 1 if not. |
| `camp fmt --stdin` | Read stdin, write stdout. For editor/pipe integration. |
| `camp fmt` (no paths, no `--stdin`) | Walk current directory for `*.camp` files. |

### Flags

| Flag | Purpose |
|------|---------|
| `--check` | Check mode (no file modification) |
| `--stdin` | Read from stdin, write to stdout |
| `--help` | Usage info |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All files formatted (or already formatted in `--check` mode) |
| 1 | Some files would change (`--check` mode) or syntax errors found |
| 2 | Invalid CLI arguments |

Matches `rustfmt --check` and general Unix convention.

### LSP Integration

The LSP server calls `format(source, file_path)` directly. No subprocess. The `textDocument/formatting` LSP method maps to this function call, returning `TextEdit[]` diffs.

---

## 4. Indentation & Spacing

### Indentation

4 spaces. No tabs.

### Spacing Rules

| Context | Rule | Example |
|---------|------|---------|
| Around `=` | Spaces on both sides | `add = \|x\| x + 1` |
| After `,` | Space | `\|x, y\|` |
| Around infix operators | Spaces | `x + y` |
| Around `->` | Spaces on both sides | `\|x\| -> Int` |
| Empty parens/brackets | No space | `()`, `[]` |
| Inside braces | Spaces | `{ x + 1 }` |
| Before call parens | No space | `f(x)` |
| Before block brace | Space | `\|x\| -> Int { x + 1 }` |
| Inside lambda pipes | No space | `\|x\|` |
| After `:` in annotations | Space | `x: Int` |
| Before `:` in annotations | No space | `x: Int` |

---

## 5. Multiline Heuristic

The formatter's central algorithm determines whether comma-separated lists and `|`-separated lists render single-line or multi-line. Three mechanisms control this.

### 5.1 First-Separator Rule

For a comma list or `|`-separated list, if the source has a line break at the first separator (first comma or first `|`), the formatter expands the entire group to multi-line (each item on its own line). If no break at the first separator, the group stays single-line.

**Comma lists**:

```camp
// Single-line (no break at first comma):
f(a, b, c)

// Multi-line (break at first comma):
f(
    a,
    b,
    c,
)
```

**`|`-separated lists** (tag unions, effect rows, aliases) — break before `|`:

```camp
// Single-line:
-[Console | IO]->

// Multi-line (break at first |):
-[
    Console
    | IO
]->
```

```camp
// Single-line:
[Ok(a) | Err(e)]

// Multi-line:
[
    Ok(a)
    | Err(e)
]
```

**Operator chains** (BinOps, method chains) — break before operator:

```camp
// Single-line:
x + y + z

// Multi-line (break at first operator):
x
+ y
+ z

// Single-line method chain:
list.iter().map(f).collect()

// Multi-line:
list
    .iter()
    .map(f)
    .collect()
```

### 5.2 Backslash Split Points

A backslash token (`\`) after a comma (before the next item) or before an operator splits the group into independent sub-groups. Each sub-group checks its own first-separator independently. The backslash also forces a line break at that point.

Backslashes are **preserved** in the formatted output. The formatter never adds or removes them. This is essential for idempotency — removing backslashes would lose split information on re-format.

**Comma list with backslash**:

```camp
// Source: [a, b, \ c, d]
// Sub-group [a, b]: no break at first comma -> single-line
// Sub-group [c, d]: no break at first comma -> single-line
// But backslash forces a break -> parent uses multiline brackets:
[
    a, b, \
    c, d,
]
```

**BinOp chain with backslash**:

```camp
// Source: x + y \ + z + w
// Sub-group [x + y]: no break at first operator -> single-line
// Sub-group [z + w]: no break at first operator -> single-line
// Backslash forces a break:
x + y
\ + z + w
```

### 5.3 Multiline Bracket Style

If any sub-group is multi-line (including via backslash line breaks), the parent brackets use multiline style: opening bracket on its own line, closing bracket on its own line, children indented.

Even if some sub-groups are single-line, the overall list uses multiline brackets if any part is multi-line.

### 5.4 Trailing Commas and Trailing Pipes

The formatter controls trailing separators in output:

- Multi-line comma lists always get a trailing comma
- Single-line comma lists never get a trailing comma
- `|`-separated lists (tag unions, effect rows) never get a trailing `|` — a trailing `|` would semantically imply "or something else"
- `where` constraint lists never get a trailing comma — the `where` clause is not a bracketed container, and the trailing comma serves no purpose before the body `{`
- The programmer's trailing comma in the source is not preserved as-is — it is normalized according to the output format

The first-separator rule (not trailing separators) drives the multiline/single-line decision.

---

## 6. Declaration Formatting

### Top-Level Declarations

- `pub` stays on the same line as the declaration: `pub greet = |name| "Hello"`
- `@derive` on its own line before the declaration, with the derive list following the first-comma rule
- Blank lines between declarations are preserved (single blank line). Multiple consecutive blank lines collapse to one.
- No blank line is added or removed between declarations the programmer put adjacent.

### Const Declarations

```camp
name = body
name: Type = body
name! = body
```

### Effect Declarations

One line if empty, multi-line with operations otherwise:

```camp
effect Empty {}

effect IO {
    println!
    readln!
}
```

### Trait Declarations

```camp
trait Display {
    display: Self -> Str
}

trait Ord is Eq {
    compare: Self, Self -> Ordering
}
```

### Alias Declarations

```camp
alias Io = File | Console
```

### Import Declarations

The exposing list follows the first-comma multiline rule:

```camp
import List
import List exposing [map, filter, fold]
import List exposing [
    map,
    filter,
    fold,
]
import My.Module as M
```

### Newtype Declarations

```camp
UserId is Hash := U64
```

### Test/Expect Declarations

```camp
test "addition works" = { ... }
expect 1 + 1 == 2
```

---

## 7. Expression Formatting

### Lambdas

Expression body on same line as params. Block body: `{` on same line as params, body indented.

```camp
|x| x + 1

|x: Int| -> Int {
    x + 1
}
```

Multiline params follow the first-comma rule. The opening `|` goes on its own line, and the closing `|` goes on its own line:

```camp
|
    x: List(a),
    y: Map(a, a),
| -> Map(a, b) { ... }
```

### Blocks

Each statement on its own line, indented. Final expression is the return value.

```camp
{
    x = 1
    y = 2
    x + y
}
```

### If/Else

Braceless single-line (when both branches are simple expressions, both-or-neither braces, never mixed):

```camp
if x > 0 x else 0
if x > 0 { x } else { 0 }
```

Multi-line: `else` on its own line, all branches get braces:

```camp
if condition {
    long_branch_body
} else {
    other_body
}
```

### Match Expressions

Each arm on its own line. Arm bodies follow the same block/expression rules as lambdas.

```camp
effect Empty {}

effect IO {
    println!
    readln!
}
```

### Handle/Intercept Expressions

Handler arms formatted like match arms.

```camp
handle IO in {
    IO.println!("hi")
} with {
    .println!(resume, s) => resume({})
}
```

### Records and Record Updates

Follow first-comma rule. `..record` is the first item in updates.

```camp
{ name: "Camp", age: 1 }

{
    name: "Camp",
    age: 1,
}
```

### Lists

Follow first-comma rule.

```camp
[1, 2, 3]

[
    1,
    2,
    3,
]
```

### Function Calls

Args follow first-comma rule. No space before `(`.

```camp
f(a, b, c)

f(
    a,
    b,
    c,
)
```

### Method Chains

Follow first-operator rule (first `.` line break triggers multiline). Backslash before `.` works as split point.

```camp
list.iter().map(f).collect()

list
    .iter()
    .map(f)
    .collect()
```

### BinOp Chains

Follow first-operator rule. Break before operator in multiline.

```camp
x + y + z

x
+ y
+ z
```

### Tag Construction

`Ok(42)`, `None` — same as function call formatting for payloads.

### String Literals

Never reflowed. See Section 9 for string-specific rules.

### Field Access

No special rules — `record.field` stays as-is.

### Assignments

`$total = $total + 1` — formatted like any other expression.

### Return, Panic, and Todo

- `return value` — early return from a function, usable in an `if` block without an `else`
- `panic "message"` — unrecoverable error, aborts execution
- `todo "message"` — placeholder for unimplemented code

All three are prefix expressions, no special formatting beyond a space after the keyword.

---

## 8. Type Formatting

Types appear inline with expressions and declarations. No special line-breaking for types themselves — they follow the surrounding context.

### Primitive Types

`I64`, `Str`, `Bool`, etc. — as-is.

### Type Parameters

Type parameters are inferred from usage — no declaration bracket needed. When trait constraints are required, a `where` clause appears after the return type and before the body.

```camp
// No constraints — type params inferred from usage:
map = |f: |a| -> b, list: List(a)| -> List(b) { ... }

// With constraints — where clause:
format = |x: a| -> Str where a is Display { ... }

// Multiline where — args + return on one line, where multiline:
format = |x: a, y: b| -> Str
    where
        a is Display,
        b is Eq
{
    ...
}

// Multiline args force multiline where:
format = |
    x: a,
    y: b,
| -> Str
    where
        a is Display,
        b is Eq
{
    ...
}
```

The `where` clause has three states:
1. **Single-line**: everything on one line (`|x: a| -> Str where a is Display { ... }`)
2. **Where-only multiline**: args + return on one line, `where` on its own line indented once, constraints indented twice following the first-comma rule
3. **Forced multiline**: any multilining in the signature (args, return type) forces the where into multiline style (same layout as state 2)

### Applied Types

`List(a)`, `Map(k, v)`, `Result(a, e)` — type args in `()`, consistent with tag payload syntax. Follow first-comma rule for multiline:

```camp
Result(a, e)

Result(
    a,
    e,
)
```

### Function Types

`|a, b| -> c` (pure), `|a| -[Eff1 | Eff2]-> c` (effectful). Params follow first-comma rule.

### Record Types

`{ name: Str, age: U64 }` — follow first-comma rule, same as record expressions.

### Tag Union Types

`[Ok(a) | Err(e)]` — follow first-`|` rule with break-before-`|`:

```camp
[Ok(a) | Err(e)]

[
    Ok(a)
    | Err(e)
]
```

With type args applied using `()`:

```camp
Result(a, e) := [Ok(a) | Err(e)]
```

### Open Tag Unions

`[Ok(a) | ..]`, `[Ok(a) | ..rest]` — the `..` and `..rest` are treated as items in the `|`-separated list.

### Effect Row Types

`-[Console | IO]->` — follow first-`|` rule:

```camp
-[Console | IO]->

-[
    Console
    | IO
]->
```

Open effect rows: `-[e]->` (effect variable), `-[Console | ..]->` (open).

### Type Annotations in Declarations

Inline, as the language defines:

```camp
add = |x: Int, y: Int| -> Int { x + y }
map = |f: |a| -> b, list: List(a)| -> List(b) { ... }
format = |x: a| -> Str where a is Display { ... }
x: Int = 3
```

---

## 9. String Literals & Multiline Strings

### Single-Line Strings

`"hello world"` — never reflowed. Backslash line continuation supported: `\` followed by any whitespace (including newlines, spaces, tabs) until the next non-whitespace character is removed entirely, joining the lines.

```camp
// Source:
"hello \
    world"
// Output: "helloworld"
```

### Triple-Quoted Strings

`"""..."""` — multiline string literals.

Rules:

- Opening `"""` must be followed by a newline. Content starts on the next line. No content on the opening line.
- Closing `"""` determines base indentation. The whitespace before the closing `"""` is the reference indent. That amount is stripped from every content line.
- Under-indentation relative to the closing `"""` is a syntax error (matching Swift's enforcement).
- Content that is more indented than the base retains its relative indentation.
- Whitespace-only lines are normalized to empty (don't contribute to indent calculation).
- The newline immediately before the closing `"""` is stripped. To include a trailing newline in the string, add a blank content line before the closing `"""`.
- Trailing whitespace on content lines is trimmed by default. A backslash at the end of a content line (after non-whitespace characters) preserves all whitespace up to and including the backslash position. The backslash itself is removed from the string output.

```camp
// No trailing newline:
greeting = """
    Hello
    World
    """
// Output: "Hello\nWorld"

// With trailing newline:
greeting = """
    Hello
    World

    """
// Output: "Hello\nWorld\n"

// Trailing whitespace preserved with backslash:
padded = """
    hello   \
    world
    """
// Output: "hello   \nworld"
```

### Formatter Behavior on Strings

String content is never reflowed or reformatted. The formatter only adjusts the indentation of the `"""` delimiters to match the surrounding context. Content line indentation is adjusted relative to the closing `"""` position.

---

## 10. Comments & Blank Lines

### Comment Syntax

| Type | Syntax |
|------|--------|
| Line comment | `// comment` |
| Doc comment | `/// doc comment` |
| Block comments | Not supported |

### Comment Formatting

- Line comments are re-indented to match the surrounding context. Content is not reflowed.
- Comments attach to the next syntactic element unless separated by a blank line.
- A blank line before a comment detaches it from the previous element.
- Trailing comments (on the same line as code) stay on that line.

### Blank Lines

- Between top-level declarations: preserved as a single blank line. Multiple consecutive blank lines collapse to one.
- Within blocks: preserved as a single blank line between statements. Multiple collapse to one.
- Within multiline expressions (records, lists, function args, etc.): preserved as a single blank line. Multiple collapse to one.
- The formatter never adds blank lines that weren't in the source.

---

## 11. Backslash Token

The backslash (`\`) is a lexer-level token used as a formatting directive. It tells the formatter where to force line breaks and create split points in comma lists and operator chains.

### Lexer Rules

- `\` is recognized as a `Backslash` token kind
- Valid positions: after a comma (before the next item) or before an operator (including `.` for method chains)
- Elsewhere in expression/type context, it's a syntax error
- Inside string literals, `\` retains its existing escape meaning (not a formatting token)

### Parser Behavior

- The parser ignores backslash tokens entirely — they produce no AST nodes
- The parser skips over them as if they were whitespace

### Formatter Behavior

- During the hybrid source-aware Doc-construction phase, the formatter reads the token stream (preserving backslash positions via source spans) to identify split points
- Backslashes are preserved in the formatted output at the same split points
- This ensures idempotency: re-formatting preserves the split structure

### Disambiguation

- Inside a string literal: `\` starts an escape sequence (including line continuation in single-line strings and trailing-whitespace preservation in triple-quoted strings)
- Outside a string: `\` is the formatting split-point token

---

## 12. Name Pun Records

| Syntax | Meaning |
|--------|---------|
| `{ x }` | Block returning `x` |
| `{ x: }` | Single-field record, name pun for `{ x: x }` |
| `{ x, y }` | Multi-field record with name puns |
| `{ x: x, y: y }` | Same as above, expanded form |
| `{ x: 1, y: 2 }` | Record with explicit values |

The formatter emits single-field name puns as `{ x: }` (not `{ x }`) to avoid ambiguity with blocks. Multi-field name puns use the shorthand `{ x, y }`.

---

## 13. Bracket Reference

Summary of bracket usage across Camp syntax:

| Bracket Pair | Content Separator | Uses |
|-------------|-------------------|------|
| `[]` | `,` | List literals, list patterns, exposing lists, derive lists |
| `[]` | `\|` | Tag union types, effect rows |
| `{}` | `,` | Records, record types, blocks |
| `()` | `,` | Function calls, tag payloads, type argument application, function params, grouping |
| `\|...\|` | `,` | Lambda parameter delimiters (`\|\|` is zero-arg lambda) |
| `-[...]->` | `\|` | Effect row in function type |
| `where` | `,` | Trait constraints on type parameters |

# Formatter Design

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Zero config | No options | Eliminates formatting debates, consistent across all projects |
| No line-length limit | Programmer controls line breaks | No heuristics for "too long"; the programmer decides via first-separator/backslash |
| Hybrid AST + source-aware | Parse to AST, use source positions for formatting choices | Guarantees well-formed output while preserving programmer intent |
| Refuse on errors | No partial formatting | Output is always valid Camp |
| 4 spaces | Indentation | Consistent, no tab/space mixing |

## Architecture

**Hybrid approach**: Parse source to AST (validating well-formedness), then pretty-print using a Wadler-style `Doc` IR. Source-position awareness is injected at Doc-construction time to drive the multiline heuristic (first-separator rule, backslash split points). Comments and blank lines are extracted from the source text using AST node positions and reattached during output.

**Error policy**: Refuse to format files with syntax errors. Exit with a diagnostic. This guarantees formatted output is always valid Camp.

**Core API**:

```
format(source: string, file_path: string) -> (string, []Diagnostic)
```

A pure function the LSP calls directly. CLI and `--check` mode are wrappers around this.

**Idempotency**: The formatter's output is a fixed point. Running `camp fmt` on already-formatted code produces identical output.

## CLI Interface

| Command | Behavior |
|---------|----------|
| `camp fmt [paths...]` | Format in-place. Paths can be files or directories (walks for `*.camp`). |
| `camp fmt --check [paths...]` | Diff-check only. Prints diff. Exits 0 if formatted, 1 if not. |
| `camp fmt --stdin` | Read stdin, write stdout. For editor/pipe integration. |
| `camp fmt` (no paths, no `--stdin`) | Walk current directory for `*.camp` files. |

Exit codes: 0 (formatted), 1 (would change or syntax errors), 2 (invalid args). Matches `rustfmt --check` and general Unix convention.

LSP integration: The LSP server calls `format(source, file_path)` directly. No subprocess. `textDocument/formatting` maps to this function call, returning `TextEdit[]` diffs.

## Indentation & Spacing

4 spaces. No tabs.

Spacing rules:
- `=`: spaces both sides (`add = |x| x + 1`)
- After `,`: space (`|x, y|`)
- Infix operators: spaces (`x + y`)
- `->`: spaces both sides (`|x| -> Int`)
- Empty parens/brackets: no space (`()`, `[]`)
- Inside braces: spaces (`{ x + 1 }`)
- Before call parens: no space (`f(x)`)
- Before block brace: space (`|x| -> Int { x + 1 }`)
- Inside lambda pipes: no space (`|x|`)
- After `:` in annotations: space (`x: Int`)
- Before `:` in annotations: no space

## Multiline Heuristic

### First-Separator Rule

For comma-separated or `|`-separated lists, if the source has a line break at the first separator, expand to multi-line (each item on own line). If no break, stay single-line.

Comma lists:
```camp
f(a, b, c)           // single-line (no break at first comma)
f(                    // multi-line (break at first comma)
    a,
    b,
    c,
)
```

`|`-separated lists (tag unions, effect rows) — break before `|`:
```camp
-[Console | IO]->     // single-line
-[                    // multi-line
    Console
    | IO
]->
```

Operator chains — break before operator:
```camp
x + y + z             // single-line
x                     // multi-line
+ y
+ z
```

Method chains — break before `.`:
```camp
list.iter().map(f).collect()   // single-line
list                           // multi-line
    .iter()
    .map(f)
    .collect()
```

### Backslash Split Points

`\` after a comma (before next item) or before an operator splits the group into independent sub-groups. Each sub-group checks its own first-separator independently. The backslash also forces a line break.

Backslashes are **preserved** in output. The formatter never adds or removes them — essential for idempotency.

```camp
// [a, b, \ c, d] → sub-groups [a, b] and [c, d] checked independently
[
    a, b, \
    c, d,
]
```

### Multiline Bracket Style

If any sub-group is multi-line, the parent brackets use multiline style: opening bracket on own line, closing bracket on own line, children indented.

### Trailing Separators

- Multi-line comma lists: always trailing comma
- Single-line comma lists: never trailing comma
- `|`-separated lists: never trailing `|` (would semantically imply "or something else")
- `where` constraint lists: never trailing comma

## Declaration Formatting

### Top-Level

- `pub` stays on same line: `pub greet = |name| "Hello"`
- `@derive` on its own line before the declaration
- Blank lines between declarations preserved (single blank line; multiple collapse to one)
- No blank line added or removed between adjacent declarations

### Const Declarations

```camp
name = body
name: Type = body
name! = body
```

### Effect Declarations

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

### Import Declarations

Exposing list follows first-comma rule:
```camp
import List exposing [map, filter, fold]
import List exposing [
    map,
    filter,
    fold,
]
```

### Newtype, Test, Expect

```camp
UserId is Hash := U64
test "addition works" = { ... }
expect 1 + 1 == 2
```

## Expression Formatting

### Lambdas

Expression body on same line. Block body: `{` on same line, body indented.

```camp
|x| x + 1

|x: Int| -> Int {
    x + 1
}
```

Multiline params: opening `|` on own line, closing `|` on own line:
```camp
|
    x: List(a),
    y: Map(a, a),
| -> Map(a, b) { ... }
```

### Blocks

Each statement on own line, indented. Final expression is return value.

### If/Else

Braceless single-line (both-or-neither braces, never mixed):
```camp
if x > 0 x else 0
if x > 0 { x } else { 0 }
```

Multi-line: `else` on own line, all branches get braces:
```camp
if condition {
    long_branch_body
} else {
    other_body
}
```

### Match, Handle/Intercept

Each arm on own line. Handler arms formatted like match arms.

### Records and Record Updates

Follow first-comma rule. `..record` is first item in updates.

### Lists, Function Calls

Follow first-comma rule. No space before `(`.

### Method Chains, BinOp Chains

Follow first-operator rule. Break before operator in multiline.

### Tag Construction

Same as function call formatting for payloads.

### Return, Panic, Todo

Prefix expressions, space after keyword. No special formatting.

## Type Formatting

Types follow surrounding context. No special line-breaking for types themselves.

### Function Types

`|a, b| -> c` (pure), `|a| -[Eff1 | Eff2]-> c` (effectful). Params follow first-comma rule.

### Tag Union Types

Follow first-`|` rule with break-before-`|`:
```camp
[Ok(a) | Err(e)]

[
    Ok(a)
    | Err(e)
]
```

### Effect Row Types

`-[Console | IO]->` — follow first-`|` rule. Open rows: `-[e]->`, `-[Console | ..]->`.

### Record Types

`{ name: Str, age: U64 }` — follow first-comma rule, same as record expressions.

### Applied Types

`List(a)`, `Map(k, v)` — type args in `()`, follow first-comma rule.

### Where Clauses

Three states:
1. Single-line: `|x: a| -> Str where a is Display { ... }`
2. Where-only multiline: args + return on one line, `where` on own line, constraints indented twice following first-comma rule
3. Forced multiline: any multilining in signature forces where into multiline style

## String Literals

### Single-Line

Never reflowed. Backslash line continuation: `\` followed by any whitespace until next non-whitespace is removed, joining lines.

### Triple-Quoted

- Opening `"""` followed by newline. No content on opening line.
- Closing `"""` determines base indentation. That amount stripped from every content line.
- Under-indentation relative to closing `"""` is a syntax error.
- More-indented content retains relative indentation.
- Whitespace-only lines normalized to empty.
- Newline before closing `"""` stripped. Add blank line for trailing newline.
- Trailing whitespace trimmed by default. Backslash at end of content line preserves whitespace up to and including backslash position; backslash itself removed.

### Formatter Behavior on Strings

String content never reflowed or reformatted. Formatter only adjusts `"""` delimiter indentation. Content line indentation adjusted relative to closing `"""` position.

## Comments

- Line comments (`//`) and doc comments (`///`) re-indented to match context. Content not reflowed.
- Block comments not supported.
- Comments attach to next syntactic element unless separated by blank line.
- Trailing comments stay on same line as code.

## Blank Lines

- Between top-level declarations: preserved as single blank line, multiple collapse to one.
- Within blocks: preserved as single blank line, multiple collapse to one.
- Within multiline expressions: preserved as single blank line, multiple collapse to one.
- Formatter never adds blank lines that weren't in the source.

## Backslash Token

The backslash (`\`) is a lexer-level formatting directive token.

### Lexer

- Recognized as `Backslash` token kind
- Valid positions: after comma (before next item) or before operator (including `.` for method chains)
- Elsewhere in expression/type context: syntax error
- Inside string literals: retains escape meaning

### Parser

- Ignores backslash tokens entirely — no AST nodes produced
- Skips over them as if whitespace

### Formatter

- Reads token stream during Doc-construction phase to identify split points
- Preserves backslashes in output at same split points
- Ensures idempotency: re-formatting preserves split structure

### Disambiguation

- Inside string literal: `\` starts escape sequence (line continuation, trailing-whitespace preservation)
- Outside string: `\` is formatting split-point token

## Name Pun Records

| Syntax | Meaning |
|--------|---------|
| `{ x }` | Block returning `x` |
| `{ x: }` | Single-field record, name pun for `{ x: x }` |
| `{ x, y }` | Multi-field record with name puns |
| `{ x: x, y: y }` | Expanded form |

Formatter emits single-field name puns as `{ x: }` (not `{ x }`) to avoid ambiguity with blocks. Multi-field uses shorthand `{ x, y }`.

## Bracket Reference

| Bracket Pair | Content Separator | Uses |
|-------------|-------------------|------|
| `[]` | `,` | List literals, list patterns, exposing lists, derive lists |
| `[]` | `\|` | Tag union types, effect rows |
| `{}` | `,` | Records, record types, blocks |
| `()` | `,` | Function calls, tag payloads, type argument application, function params, grouping |
| `\|...\|` | `,` | Lambda parameter delimiters |
| `-[...]->` | `\|` | Effect row in function type |
| `where` | `,` | Trait constraints on type parameters |

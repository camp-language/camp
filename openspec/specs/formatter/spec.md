# Domain Specification: Formatter

## Purpose

Provide a zero-configuration, deterministic, idempotent source formatter for Camp that always produces the same output for the same source program.

## Requirements

### Requirement: Zero Configuration

The formatter SHALL have no configuration files, no CLI flags that change formatting behavior, and no line-length limits.

#### Scenario: No formatting options

- Given any Camp source file
- When `camp fmt` is invoked
- Then the formatter SHALL produce the same output regardless of environment, user preferences, or flags

### Requirement: Idempotency

Running the formatter on already-formatted code SHALL produce identical output.

#### Scenario: Re-formatting

- Given a Camp source file has been formatted by `camp fmt`
- When `camp fmt` is run on the output again
- Then the result SHALL be identical to the first formatted output

### Requirement: Determinism

The formatter SHALL produce identical output for identical input across all invocations.

#### Scenario: Consistent output

- Given the same Camp source input
- When formatted multiple times
- Then each invocation SHALL produce identical output

### Requirement: Refuse on Errors

The formatter SHALL NOT format files with syntax errors.

#### Scenario: Syntax error in source

- Given a Camp source file with syntax errors
- When `camp fmt` is invoked on it
- Then the formatter SHALL exit with a diagnostic and produce no output for that file

### Requirement: Indentation

The formatter SHALL use 4 spaces for indentation. No tabs.

#### Scenario: Indentation normalization

- Given a source file with tab indentation or non-standard space counts
- When formatted
- Then all indentation SHALL be normalized to 4 spaces

### Requirement: First-Separator Multiline Rule

The formatter SHALL determine single-line vs multi-line rendering based on whether the first separator has a line break in the source.

#### Scenario: Comma list — no break at first comma

- Given a comma-separated list where the first comma is on the same line
- When formatted
- Then the list SHALL render single-line: `f(a, b, c)`

#### Scenario: Comma list — break at first comma

- Given a comma-separated list where the first comma has a line break
- When formatted
- Then the list SHALL render multi-line with each item on its own line and a trailing comma

#### Scenario: Pipe-separated list — break at first pipe

- Given a `|`-separated list (tag union, effect row) where the first `|` has a line break
- When formatted
- Then the list SHALL render multi-line with break before `|`

#### Scenario: Operator chain — break at first operator

- Given a binary operator chain where the first operator has a line break
- When formatted
- Then the chain SHALL render multi-line with break before each operator

### Requirement: Backslash Split Points

Backslash tokens (`\`) SHALL create independent sub-groups within comma lists and operator chains, each checked by its own first-separator rule.

#### Scenario: Backslash in comma list

- Given a source `[a, b, \ c, d]`
- When formatted
- Then `[a, b]` and `[c, d]` SHALL each be checked independently for multiline, with the backslash forcing a line break at that point

#### Scenario: Backslash preservation

- Given a source containing backslash split-point tokens
- When formatted
- Then the backslash tokens SHALL be preserved in the output (never added or removed), ensuring idempotency

### Requirement: Trailing Separators

The formatter SHALL normalize trailing separators.

#### Scenario: Multi-line comma list

- Given a comma list rendered multi-line
- Then it SHALL always have a trailing comma

#### Scenario: Single-line comma list

- Given a comma list rendered single-line
- Then it SHALL never have a trailing comma

#### Scenario: Pipe-separated list

- Given a `|`-separated list
- Then it SHALL never have a trailing `|` (would semantically imply "or something else")

### Requirement: Multiline Bracket Style

If any sub-group within a bracketed list is multi-line, the parent brackets SHALL use multiline style (opening bracket on own line, closing bracket on own line, children indented).

#### Scenario: Mixed single/multi-line sub-groups

- Given a bracketed list where some sub-groups are single-line and at least one is multi-line
- When formatted
- Then the overall list SHALL use multiline bracket style

### Requirement: CLI Modes

The formatter SHALL support in-place formatting, check mode, and stdin mode.

#### Scenario: In-place formatting

- Given `camp fmt [paths...]` is invoked with file or directory paths
- Then files SHALL be formatted in-place; directories SHALL be walked for `*.camp` files

#### Scenario: Check mode

- Given `camp fmt --check [paths...]` is invoked
- Then the formatter SHALL print a diff of what would change and exit 0 if formatted, 1 if not

#### Scenario: Stdin mode

- Given `camp fmt --stdin` is invoked
- Then the formatter SHALL read stdin and write formatted output to stdout

#### Scenario: No paths and no stdin

- Given `camp fmt` is invoked with no paths and no `--stdin`
- Then the formatter SHALL walk the current directory for `*.camp` files

### Requirement: Exit Codes

The formatter SHALL use the following exit codes: 0 for success (all files formatted or already formatted in `--check`), 1 for changes needed (`--check`) or syntax errors, and 2 for invalid CLI arguments.

#### Scenario: All files formatted

- **WHEN** `camp fmt --check` runs on already-formatted files
- **THEN** it SHALL exit with code 0

#### Scenario: Files need formatting

- **WHEN** `camp fmt --check` runs on files that would change
- **THEN** it SHALL exit with code 1

#### Scenario: Invalid arguments

- **WHEN** `camp fmt` is invoked with unrecognized flags
- **THEN** it SHALL exit with code 2

### Requirement: LSP Integration

The LSP server SHALL call the formatter's core function directly without subprocess delegation.

#### Scenario: LSP formatting request

- Given the LSP server receives `textDocument/formatting`
- Then it SHALL call `format(source, file_path)` directly and return `TextEdit[]` diffs

### Requirement: String Literal Preservation

String content SHALL never be reflowed or reformatted.

#### Scenario: Single-line string

- Given a single-line string literal
- When formatted
- Then the string content SHALL remain unchanged

#### Scenario: Per-line prefix multiline string indentation

- Given a per-line prefix multiline string using `\` at line start
- When formatted
- Then the `\` prefix indentation SHALL be adjusted to match surrounding context; content indentation SHALL be recalculated relative to the `\` prefix position

### Requirement: Comment Preservation

Comments SHALL be re-indented to match context but content SHALL not be reflowed.

#### Scenario: Line comment re-indentation

- Given a line comment with incorrect indentation
- When formatted
- Then the comment SHALL be re-indented to match the surrounding context

#### Scenario: Comment attachment

- Given a comment immediately before a syntactic element (no blank line separating)
- When formatted
- Then the comment SHALL attach to the next syntactic element

### Requirement: Blank Line Normalization

Multiple consecutive blank lines SHALL collapse to a single blank line. The formatter SHALL never add blank lines that weren't in the source.

#### Scenario: Multiple blank lines

- Given a source with three consecutive blank lines between declarations
- When formatted
- Then the output SHALL have exactly one blank line

### Requirement: Spacing Rules

The formatter SHALL enforce consistent spacing: spaces around `=`, after `,`, around infix operators, around `->`, no space inside empty parens/brackets, spaces inside braces, no space before call parens, space before block braces, no space inside lambda pipes, space after `:` in annotations, and no space before `:` in annotations.

#### Scenario: Assignment spacing

- **WHEN** formatting `x=1`
- **THEN** it SHALL emit `x = 1`

#### Scenario: Infix operator spacing

- **WHEN** formatting `a+b`
- **THEN** it SHALL emit `a + b`

#### Scenario: Empty brackets

- **WHEN** formatting `f( )` or `[ ]`
- **THEN** it SHALL emit `f()` or `[]` with no interior spaces

### Requirement: Name Pun Disambiguation

Single-field name puns SHALL be emitted as `{ x: }` to avoid ambiguity with blocks. Multi-field name puns SHALL use the shorthand `{ x, y }`.

#### Scenario: Single-field name pun

- Given a single-field record `{ x }` (name pun)
- When formatted
- Then it SHALL be emitted as `{ x: }`

### Requirement: Where Clause Formatting

Where clauses SHALL have three rendering states: single-line, where-only multiline, or forced multiline (when any signature component is multi-line).

#### Scenario: Single-line where

- Given a function with a single constraint
- When the entire signature fits on one line
- Then the where clause SHALL be inline: `|x: a| -> Str where a is Display { ... }`

#### Scenario: Where-only multiline

- Given a function with multiple constraints where the args and return fit on one line
- When formatted
- Then `where` SHALL appear on its own line with constraints indented and following the first-comma rule

#### Scenario: Forced multiline where

- Given a function with multiline parameters
- When formatted
- Then the where clause SHALL use multiline style regardless of constraint count

For the complete syntax reference, see `docs/syntax-recipe.md`.

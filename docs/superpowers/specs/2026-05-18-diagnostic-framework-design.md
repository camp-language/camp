# Diagnostic Framework Design

## Goal

Replace Camp's minimal error system with an Elm-style diagnostic framework that produces friendly, precise error messages with source snippets, underlines, hints, and suggestions. The framework serves both CLI output and LSP diagnostics from a shared data model, and co-designs with the e2e snapshot testing system for deterministic output.

## Current State

Camp has a flat `Error` struct with `category` (Warning/Error/Internal), `message` (string), and `span` (single source span). The reporter formats errors as `file:line:col: category: message`. Dual-span unification errors lose their second span. No source snippets, no colors, no error codes, no hints, no suggestions. Warnings and Internal categories exist but are never emitted in production.

### Bugs in Current System

1. **Intern_ID rendered as integer**: Three `collector_add` calls format `Intern_ID` values directly, printing integer IDs instead of human-readable strings (lexer/typecheck/unify)
2. **Type errors not individually reported**: `cli.odin:76-78` prints only "type errors found, stopping." without showing the actual errors via `report_error`, unlike the parse error path
3. **OS errors swallowed**: `cli.odin:40` has `err` in scope but does not include it in the "could not read file" message
4. **Secondary spans lost**: `Unify_Error.span_b` is never used by the reporter
5. **Dual-span same variable**: Function arity and tag payload arity mismatches pass `context_var` for both positions in `make_unify_error`, resulting in `span_a == span_b`

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Error detail level | Elm-style | Friendly, minimal, focused on one clear message per error |
| CLI vs LSP | Shared model, dual renderers | Same diagnostic type, format-specific renderers |
| Source snippets | Yes, with underlines | Core of what makes Elm/Rust errors great |
| Multi-span errors | Inline multi-span | Both spans shown as labeled source snippets |
| Error codes | No codes | Elm-style; errors identified by message alone |
| Color support | Auto-detect TTY | ANSI colors when stdout is a TTY, plain text otherwise |
| Suggestions | Yes, with typo suggestions | "Did you mean `foo`?" and similar hints |
| Internal errors | Friendly report prompt | "This is a bug in Camp, please report it" with link |
| Warning handling | Render support only | Infrastructure supports warnings (same format, yellow), but no warnings emitted yet |
| Snapshot compatibility | Co-designed | Plain-text output (no TTY = no ANSI) means deterministic snapshots |

## Approach: Typed Error Variants

Replace the flat `Error` struct with sum-type error variants — one struct per error kind, each carrying exactly the data it needs. A `Diagnostic` type wraps any variant with shared metadata. The renderer pattern-matches on variants to produce tailored output.

Each error kind has a constructor function that builds the complete `Diagnostic` — message, labels, and hints — in one place. Pipeline code passes data; the constructor handles presentation.

## Data Model

### Core Types

```odin
Diagnostic_Category :: enum {
    Warning,
    Error,
    Internal,
}

Span_Label :: struct {
    span:  Source_Span,
    label: string,
}

Diagnostic :: struct {
    category: Diagnostic_Category,
    span:     Source_Span,
    message:  string,
    labels:   [dynamic]Span_Label,
    hints:    [dynamic]string,
}
```

`labels` carries secondary span annotations (e.g., "this is type `I64`" pointing at the other side of a mismatch). `hints` carries suggestion strings like "Did you mean `foo`?".

### Error Variants

Each error kind is a distinct struct type. These structs are *only used at construction time* — each variant struct has a corresponding `diag_*` constructor that produces a `Diagnostic`. The renderer never pattern-matches on variants; it consumes the `Diagnostic` struct's `message`, `labels`, and `hints` fields directly. The variant structs exist to give constructors strongly-typed, per-error input parameters instead of loose strings.

```odin
Lex_Unexpected_Char :: struct {
    char: u8,
}
Lex_Unterminated_String :: struct {}
Parse_Expected_Token :: struct {
    expected: Token_Kind,
    actual:   Token,
}
Parse_Unexpected_Token :: struct {
    token: Token,
}
Parse_Expected_Type :: struct {
    actual: Token,
}
Type_Effectful_Naming :: struct {
    name:    string,
    effects: string,
}
Type_Undefined_Name :: struct {
    name:          string,
    similar_names: []string,
}
Type_Unhandled_Effect :: struct {
    effect_name: string,
}
Unify_Type_Mismatch :: struct {
    type_a: string,
    type_b: string,
    span_b: Source_Span,
}
Unify_Primitive_Mismatch :: struct {
    name_a: string,
    name_b: string,
    span_b: Source_Span,
}
Unify_Value_Row_Conflict :: struct {
    kind_a: string,
    kind_b: string,
    span_b: Source_Span,
}
Unify_Infinite_Type :: struct {
    type_expr: string,
    span_b:    Source_Span,
}
Unify_Arity_Mismatch :: struct {
    expected: int,
    actual:   int,
    span_b:   Source_Span,
}
Unify_Tag_Arity_Mismatch :: struct {
    tag_name: string,
    expected: int,
    actual:   int,
    span_b:   Source_Span,
}
CLI_Invalid_Extension :: struct {
    path:      string,
    extension: string,
}
CLI_File_Not_Found :: struct {
    path:     string,
    os_error: string,
}
CLI_Unknown_Command :: struct {
    command: string,
}
```

### Collector

`Error_Collector` becomes `Diagnostic_Collector`:

```odin
Diagnostic_Collector :: struct {
    diagnostics:     [dynamic]Diagnostic,
    warning_count:   int,
    error_count:     int,
    internal_count:  int,
}
```

`collector_add` becomes `collector_add_diag`, taking a `Diagnostic`. Pipeline code calls `collector_add_diag(&ctx.collector, diag_unexpected_char(ch, span))`.

### Internal Errors

Internal errors get a special constructor that appends the report-prompt hint:

```odin
diag_internal :: proc(message: string, span: Source_Span) -> Diagnostic {
    d: Diagnostic
    d.category = .Internal
    d.span = span
    d.message = message
    append(&d.hints, "This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues")
    return d
}
```

## Rendering

### CLI Renderer

The CLI renderer produces Elm-style output.

**Simple single-span error (lexer):**
```
-- UNEXPECTED CHARACTER ----------------------------------------- main.camp

1 | x = @
        ^
I don't recognize the character `@`.
```

**Multi-span error (type mismatch):**
```
-- TYPE MISMATCH ----------------------------------------- main.camp

The two branches of this `if` produce different types.

4 |   x = if true 1 else "no"
         ^^^^^^^^^^^^^^^^^^^^^
5 |   y = 42
         ^^
The condition at line 4 produces a `I64`, but the else branch
at line 5 produces a `String`.
```

**Error with hint (undefined name):**
```
-- UNDEFINED NAME ----------------------------------------- main.camp

3 | result = foo(1)
                ^^^
I cannot find `foo`. Did you mean `bar`?
```

**Internal error:**
```
-- INTERNAL ERROR ----------------------------------------- main.camp

Something went wrong inside the compiler.

5 | x = f(x)
        ^^^^

This is a bug in Camp. Please report it at
https://github.com/smores56/camp/issues
```

**Warning:**
```
-- WARNING ----------------------------------------- main.camp

3 | x = 1
      ^^^^
(warning message in same format, yellow header)
```

### Rendering Rules

1. **Header line**: `-- {TITLE} -- {file_path}` — title is uppercase, padded with dashes to 60 chars
2. **Message body**: The `message` field, word-wrapped to 80 chars, printed below the header
3. **Source snippet**: The relevant source line(s) with line numbers. Gutter width auto-scales for line numbers up to 9999
4. **Underline**: `^` characters spanning the exact byte range of the primary span. Secondary spans use `~` characters with their label text after
5. **Labels**: Each `Span_Label` renders as a separate snippet block showing its source line + `~` underline + label text
6. **Hints**: Printed after all span blocks, one per line
7. **Summary line**: After all diagnostics, print `compilation failed with {n} error(s)` (or `{n} warning(s)` for warnings-only)

### Color Scheme (TTY only)

| Element | ANSI |
|---------|------|
| Header title | Bold red (errors), bold yellow (warnings), bold magenta (internal) |
| Header dashes | Dim/gray |
| File path | Underlined |
| Primary underline (`^`) | Red/yellow/magenta matching category |
| Secondary underline (`~`) | Cyan |
| Hint text | Green |
| Line numbers | Dim/gray |

When stdout is not a TTY (piped, snapshot tests), output is plain text with no ANSI escapes.

### Multi-Diagnostic Output

Each diagnostic is separated by a blank line. Diagnostics are printed in collection order (pipeline order: lexer → parser → typecheck). Final summary line:

```
compilation failed with 2 error(s)
```

For warnings-only:

```
2 warning(s) found
```

### LSP Renderer

Maps `Diagnostic` to LSP PublishDiagnostics:

```odin
LSP_Rendered :: struct {
    range:    LSP_Range,
    severity: LSP_DiagnosticSeverity,
    message:  string,
    related:  [dynamic]LSP_DiagnosticRelatedInfo,
}
```

Mapping rules:
- `Diagnostic.span` → `range` (convert byte offsets to Position via line/col lookup)
- `Diagnostic.category` → `severity` (Error=1, Warning=2, Internal=1)
- `Diagnostic.message` + hint text (joined with `\n\n`) → `message`
- Each `Span_Label` → one `relatedInformation` entry (location + label)

The LSP renderer and CLI renderer both consume the same `Diagnostic` type — no format-specific logic leaks into the diagnostic constructors.

### Snapshot Compatibility

The e2e runner captures raw stderr from the `camp build` subprocess. Since the subprocess stdout is not a TTY, the CLI renderer auto-emits plain text. Snapshots are deterministic (no color codes, no TTY-dependent formatting). Line wrapping is fixed at 80 chars consistently.

## Error Catalog

Every diagnostic variant, its Elm-style title, example output, and constructor signature.

### Lexer Errors

**`Lex_Unexpected_Char`** — Title: `UNEXPECTED CHARACTER`
```
-- UNEXPECTED CHARACTER ----------------------------------------- main.camp

1 | x = @
        ^
I don't recognize the character `@`.
```
Constructor: `diag_unexpected_char(char: u8, span: Source_Span) -> Diagnostic`

**`Lex_Unterminated_String`** — Title: `UNTERMINATED STRING`
```
-- UNTERMINATED STRING ----------------------------------------- main.camp

1 | x = "hello
          ^^^^^^
This string never ends. Try adding a closing `"`.
```
Constructor: `diag_unterminated_string(span: Source_Span) -> Diagnostic`

### Parser Errors

**`Parse_Expected_Token`** — Title: `SYNTAX ERROR`
```
-- SYNTAX ERROR ----------------------------------------- main.camp

3 | f = (x -> I64 { x }
              ^
I expected a `)` here, but I got `->` instead.
```
Constructor: `diag_expected_token(expected: Token_Kind, actual: Token, span: Source_Span) -> Diagnostic`
- Renders `Token_Kind` as human-readable name (e.g. `.Kw_If` → `"if"`, `.RParen` → `")"`)
- Uses `actual.text` (the real lexeme) in the message

**`Parse_Unexpected_Token`** — Title: `SYNTAX ERROR`
```
-- SYNTAX ERROR ----------------------------------------- main.camp

3 | x = | 42
        ^
I was not expecting `|` here. Are you trying to write a pattern match?
```
Constructor: `diag_unexpected_token(token: Token) -> Diagnostic`
- Suggests likely intent based on token kind (e.g. `|` → pattern match hint)

**`Parse_Expected_Type`** — Title: `SYNTAX ERROR`
```
-- SYNTAX ERROR ----------------------------------------- main.camp

2 | f = (x: if) -> I64 { x }
             ^^
I was expecting a type here, but I found `if` instead.
```
Constructor: `diag_expected_type(actual: Token, span: Source_Span) -> Diagnostic`

### Typecheck Errors

**`Type_Effectful_Naming`** — Title: `EFFECTFUL FUNCTION NAMING`
```
-- EFFECTFUL FUNCTION NAMING ----------------------------------------- main.camp

3 | main = || -> {IO} I64 { 0 }
        ^^^^
This function performs effect `IO`, so its name needs to end with `!`.
Try: `main!`
```
Constructor: `diag_effectful_naming(name: string, effects: string, span: Source_Span) -> Diagnostic`
- `effects` is the resolved effect row rendered as a human string (e.g. `"{IO}"`)
- Hint: `"Try: {name}!"`

**`Type_Undefined_Name`** — Title: `UNDEFINED NAME`
```
-- UNDEFINED NAME ----------------------------------------- main.camp

3 | result = foo(1)
                ^^^
I cannot find `foo`. Did you mean `bar`?
```
Constructor: `diag_undefined_name(name: string, similar: []string, span: Source_Span) -> Diagnostic`
- `similar` comes from Levenshtein distance over in-scope names
- If no similar names: `"I cannot find `{name}`."` (no "Did you mean" line)

**`Type_Unhandled_Effect`** — Title: `UNHANDLED EFFECT`
```
-- UNHANDLED EFFECT ----------------------------------------- main.camp

5 |   IO.println("hi")
     ^^^^^^^^^^^
This expression performs effect `IO`, but there is no `handle` block
around it. Try wrapping it with:

    handle <expr> with { IO.println(s) -> resume(()) }
```
Constructor: `diag_unhandled_effect(effect_name: string, span: Source_Span) -> Diagnostic`
- Hint suggests adding a `handle` block

### Unification Errors

**`Unify_Type_Mismatch`** — Title: `TYPE MISMATCH`
```
-- TYPE MISMATCH ----------------------------------------- main.camp

4 | x = if true 1 else "no"
         ^^^^^^^^^^^^^^^^^^^
5 |   y = 42
         ^^
The condition at line 4 produces a `I64`, but the else branch
at line 5 produces a `String`.
```
Constructor: `diag_type_mismatch(type_a: string, type_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic`
- `type_a`/`type_b` are fully resolved type strings (e.g. `"I64"`, `"String -> I64"`)
- `span_b` rendered as a secondary label with `~` underline

**`Unify_Primitive_Mismatch`** — Title: `TYPE MISMATCH`
```
-- TYPE MISMATCH ----------------------------------------- main.camp

3 | x: String = 42
              ^^^^^
4 |   y: I64 = "hello"
               ^^^^^^^
`String` does not match `I64`.
```
Constructor: `diag_primitive_mismatch(name_a: string, name_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic`

**`Unify_Value_Row_Conflict`** — Title: `TYPE MISMATCH`
```
-- TYPE MISMATCH ----------------------------------------- main.camp

3 | x = { a: 1 }
        ^^^^^^^^^
4 |   y = Ok(42)
           ^^^^^^
I expected a value type here, but I found a row type instead.
```
Constructor: `diag_value_row_conflict(kind_a: string, kind_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic`

**`Unify_Infinite_Type`** — Title: `INFINITE TYPE`
```
-- INFINITE TYPE ----------------------------------------- main.camp

3 | f = (x) { f(x) }
         ^^^^^^^^^
This creates an infinite type. `f` is defined in terms of itself,
which would make the type infinitely large.
```
Constructor: `diag_infinite_type(type_expr: string, span: Source_Span, span_b: Source_Span) -> Diagnostic`
- Uses "infinite type" instead of "occurs check" (avoids jargon)

**`Unify_Arity_Mismatch`** — Title: `ARITY MISMATCH`
```
-- ARITY MISMATCH ----------------------------------------- main.camp

3 | f = (a, b) -> I64 { a + b }
        ^^^^^^^^^^^^^^^^^^^^^^^^
4 |   f(1)
       ^^^
This function expects 2 arguments, but it was called with 1.
```
Constructor: `diag_arity_mismatch(expected: int, actual: int, span: Source_Span, span_b: Source_Span) -> Diagnostic`

**`Unify_Tag_Arity_Mismatch`** — Title: `TAG ARITY MISMATCH`
```
-- TAG ARITY MISMATCH ----------------------------------------- main.camp

3 | x : Ok(I64) | Error(String) = Ok(42, 99)
                                   ^^^^^^^^^^
4 |   match x { Ok(v) -> v | Error(e) -> e + 1 }
                                 ^^^^^^^^^^^^^^
Tag `Ok` expects 1 payload, but here it has 2.
```
Constructor: `diag_tag_arity_mismatch(tag_name: string, expected: int, actual: int, span: Source_Span, span_b: Source_Span) -> Diagnostic`

### CLI Errors

CLI errors have no source span, so they skip the snippet section. span = `Source_Span_ZERO`.

**`CLI_Invalid_Extension`** — Title: `INVALID FILE EXTENSION`
```
-- INVALID FILE EXTENSION -----------------------------------------

I expected a `.camp` file, but you gave me `test.txt`.
```
Constructor: `diag_invalid_extension(path: string, extension: string) -> Diagnostic`

**`CLI_File_Not_Found`** — Title: `FILE NOT FOUND`
```
-- FILE NOT FOUND -----------------------------------------

I could not read `/nonexistent.camp` (No such file or directory).
```
Constructor: `diag_file_not_found(path: string, os_error: string) -> Diagnostic`

**`CLI_Unknown_Command`** — Title: `UNKNOWN COMMAND`
```
-- UNKNOWN COMMAND -----------------------------------------

I don't know the command `foo`. Try `build`, `check`, `test`, or `fmt`.
```
Constructor: `diag_unknown_command(command: string) -> Diagnostic`
- Hint lists all valid commands

### Warnings

Same format, yellow header. No warnings emitted yet, but the renderer supports them:

```
-- WARNING ----------------------------------------- main.camp

3 | x = 1
      ^^^^
(unused variable)
```

### Diagnostic Title Map

| Variant | Title |
|---------|-------|
| `Lex_Unexpected_Char` | `UNEXPECTED CHARACTER` |
| `Lex_Unterminated_String` | `UNTERMINATED STRING` |
| `Parse_Expected_Token` | `SYNTAX ERROR` |
| `Parse_Unexpected_Token` | `SYNTAX ERROR` |
| `Parse_Expected_Type` | `SYNTAX ERROR` |
| `Type_Effectful_Naming` | `EFFECTFUL FUNCTION NAMING` |
| `Type_Undefined_Name` | `UNDEFINED NAME` |
| `Type_Unhandled_Effect` | `UNHANDLED EFFECT` |
| `Unify_Type_Mismatch` | `TYPE MISMATCH` |
| `Unify_Primitive_Mismatch` | `TYPE MISMATCH` |
| `Unify_Value_Row_Conflict` | `TYPE MISMATCH` |
| `Unify_Infinite_Type` | `INFINITE TYPE` |
| `Unify_Arity_Mismatch` | `ARITY MISMATCH` |
| `Unify_Tag_Arity_Mismatch` | `TAG ARITY MISMATCH` |
| `CLI_Invalid_Extension` | `INVALID FILE EXTENSION` |
| `CLI_File_Not_Found` | `FILE NOT FOUND` |
| `CLI_Unknown_Command` | `UNKNOWN COMMAND` |

## File Organization

| File | Purpose |
|------|---------|
| `src/diagnostic.odin` | `Diagnostic`, `Diagnostic_Category`, `Span_Label`, `Diagnostic_Collector`, all variant structs |
| `src/diag_constructors.odin` | All `diag_*` constructor functions, title map |
| `src/diag_renderer_cli.odin` | CLI renderer (TTY/plain-text), `render_diagnostic`, `render_all`, `span_to_line_col`, source snippet extraction, TTY detection |
| `src/diag_renderer_lsp.odin` | `LSP_Rendered` struct and mapping types only — full LSP renderer is future work |
| `src/error.odin` | Removed (replaced by diagnostic.odin) |
| `src/reporter.odin` | Removed (replaced by diag_renderer_cli.odin) |

## Migration Path

1. Create `diagnostic.odin` with new types + collector
2. Create `diag_constructors.odin` with all constructors
3. Create `diag_renderer_cli.odin` with CLI renderer
4. Update `context.odin` to use `Diagnostic_Collector`
5. Migrate each pipeline phase (lexer → parser → canonicalize → typecheck → unify) to use `diag_*` constructors
6. Update `cli.odin` to use new renderer (and fix the type-error-reporting bug)
7. Update all tests that reference `Error_Collector`/`Error` to use `Diagnostic_Collector`/`Diagnostic`
8. Remove `error.odin` and `reporter.odin`
9. Update e2e snapshot `.expected.toml` files with new error format

## Snapshot Co-Design

The e2e snapshot testing system captures `stderr` from `camp build`. Since the build subprocess runs non-interactively (no TTY), the CLI renderer emits plain text. This means:

- Snapshots are deterministic across all environments
- `--update` produces the same output as CI
- Error output changes only when we intentionally improve messages (tracked via `git diff` after `--update`)
- The `errors/` category in the e2e spec will need `.expected.toml` files updated to match the new format once implemented

### Expected Snapshot Changes

The e2e spec defines 14 error tests in `errors/`. Each will need its `stderr` field updated from the current `file:line:col: category: message` format to the new Elm-style format. The `exit` field remains `1` for all error tests.

For `command-line/` tests, CLI errors (no source span) render without snippet blocks, so their `stderr` will be the header + message only.

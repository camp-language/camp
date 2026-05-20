# Diagnostics Design

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
| Warning handling | Render support only | Infrastructure supports warnings but no warnings emitted yet |
| Snapshot compatibility | Co-designed | Plain-text output (no TTY = no ANSI) means deterministic snapshots |

## Current State & Bugs

Camp has a flat `Error` struct with `category`, `message`, and single `span`. Bugs:

1. **Intern_ID rendered as integer**: Three `collector_add` calls format `Intern_ID` values directly, printing integer IDs instead of human-readable strings
2. **Type errors not individually reported**: `cli.odin:76-78` prints only "type errors found, stopping" without showing actual errors
3. **OS errors swallowed**: `cli.odin:40` has `err` in scope but doesn't include it in the message
4. **Secondary spans lost**: `Unify_Error.span_b` is never used by the reporter
5. **Dual-span same variable**: Function arity and tag payload arity mismatches pass `context_var` for both positions

## Data Model

### Core Types

```odin
Diagnostic_Category :: enum { Warning, Error, Internal }

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

`labels` carries secondary span annotations. `hints` carries suggestion strings.

### Error Variants

Each error kind is a distinct struct type used only at construction time. Each variant has a `diag_*` constructor that produces a `Diagnostic`. The renderer never pattern-matches on variants; it consumes `Diagnostic` fields directly.

**Lexer:** `Lex_Unexpected_Char`, `Lex_Unterminated_String`

**Parser:** `Parse_Expected_Token`, `Parse_Unexpected_Token`, `Parse_Expected_Type`

**Typecheck:** `Type_Effectful_Naming`, `Type_Undefined_Name`, `Type_Unhandled_Effect`

**Unification:** `Unify_Type_Mismatch`, `Unify_Primitive_Mismatch`, `Unify_Value_Row_Conflict`, `Unify_Infinite_Type`, `Unify_Arity_Mismatch`, `Unify_Tag_Arity_Mismatch`

**CLI:** `CLI_Invalid_Extension`, `CLI_File_Not_Found`, `CLI_Unknown_Command`

### Collector

```odin
Diagnostic_Collector :: struct {
    diagnostics:     [dynamic]Diagnostic,
    warning_count:   int,
    error_count:     int,
    internal_count:  int,
}
```

`collector_add` becomes `collector_add_diag`. Pipeline code calls `collector_add_diag(&ctx.collector, diag_unexpected_char(ch, span))`.

### Internal Errors

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

## CLI Rendering

### Rendering Rules

1. **Header line**: `-- {TITLE} -- {file_path}` — title uppercase, padded with dashes to 60 chars
2. **Message body**: Word-wrapped to 80 chars, printed below header
3. **Source snippet**: Relevant source line(s) with line numbers. Gutter width auto-scales for line numbers up to 9999
4. **Underline**: `^` for primary span, `~` for secondary spans with label text
5. **Labels**: Each `Span_Label` renders as separate snippet block
6. **Hints**: Printed after all span blocks, one per line
7. **Summary line**: `compilation failed with {n} error(s)` or `{n} warning(s) found`

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

### Example Output

Simple single-span:
```
-- UNEXPECTED CHARACTER ----------------------------------------- main.camp

1 | x = @
        ^
I don't recognize the character `@`.
```

Multi-span:
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

With hint:
```
-- UNDEFINED NAME ----------------------------------------- main.camp

3 | result = foo(1)
                ^^^
I cannot find `foo`. Did you mean `bar`?
```

## LSP Rendering

```odin
LSP_Rendered :: struct {
    range:    LSP_Range,
    severity: LSP_DiagnosticSeverity,
    message:  string,
    related:  [dynamic]LSP_DiagnosticRelatedInfo,
}
```

Mapping: `Diagnostic.span` → `range`, `Diagnostic.category` → `severity` (Error=1, Warning=2, Internal=1), `Diagnostic.message` + hints joined → `message`, each `Span_Label` → `relatedInformation`.

## Error Catalog

| Variant | Title | Constructor |
|---------|-------|-------------|
| `Lex_Unexpected_Char` | `UNEXPECTED CHARACTER` | `diag_unexpected_char(char, span)` |
| `Lex_Unterminated_String` | `UNTERMINATED STRING` | `diag_unterminated_string(span)` |
| `Parse_Expected_Token` | `SYNTAX ERROR` | `diag_expected_token(expected, actual, span)` |
| `Parse_Unexpected_Token` | `SYNTAX ERROR` | `diag_unexpected_token(token)` |
| `Parse_Expected_Type` | `SYNTAX ERROR` | `diag_expected_type(actual, span)` |
| `Type_Effectful_Naming` | `EFFECTFUL FUNCTION NAMING` | `diag_effectful_naming(name, effects, span)` |
| `Type_Undefined_Name` | `UNDEFINED NAME` | `diag_undefined_name(name, similar, span)` |
| `Type_Unhandled_Effect` | `UNHANDLED EFFECT` | `diag_unhandled_effect(effect_name, span)` |
| `Unify_Type_Mismatch` | `TYPE MISMATCH` | `diag_type_mismatch(type_a, type_b, span, span_b)` |
| `Unify_Primitive_Mismatch` | `TYPE MISMATCH` | `diag_primitive_mismatch(name_a, name_b, span, span_b)` |
| `Unify_Value_Row_Conflict` | `TYPE MISMATCH` | `diag_value_row_conflict(kind_a, kind_b, span, span_b)` |
| `Unify_Infinite_Type` | `INFINITE TYPE` | `diag_infinite_type(type_expr, span, span_b)` |
| `Unify_Arity_Mismatch` | `ARITY MISMATCH` | `diag_arity_mismatch(expected, actual, span, span_b)` |
| `Unify_Tag_Arity_Mismatch` | `TAG ARITY MISMATCH` | `diag_tag_arity_mismatch(tag_name, expected, actual, span, span_b)` |
| `CLI_Invalid_Extension` | `INVALID FILE EXTENSION` | `diag_invalid_extension(path, extension)` |
| `CLI_File_Not_Found` | `FILE NOT FOUND` | `diag_file_not_found(path, os_error)` |
| `CLI_Unknown_Command` | `UNKNOWN COMMAND` | `diag_unknown_command(command)` |

## File Organization

| File | Purpose |
|------|---------|
| `src/diagnostic.odin` | `Diagnostic`, `Diagnostic_Category`, `Span_Label`, `Diagnostic_Collector`, variant structs |
| `src/diag_constructors.odin` | All `diag_*` constructor functions, title map |
| `src/diag_renderer_cli.odin` | CLI renderer (TTY/plain-text), `render_diagnostic`, `render_all`, `span_to_line_col`, TTY detection |
| `src/diag_renderer_lsp.odin` | `LSP_Rendered` struct and mapping types |
| `src/error.odin` | Removed (replaced) |
| `src/reporter.odin` | Removed (replaced) |

## Migration Path

1. Create `diagnostic.odin` with new types + collector
2. Create `diag_constructors.odin` with all constructors
3. Create `diag_renderer_cli.odin` with CLI renderer
4. Update `context.odin` to use `Diagnostic_Collector`
5. Migrate each pipeline phase (lexer → parser → canonicalize → typecheck → unify)
6. Update `cli.odin` to use new renderer (fix type-error-reporting bug)
7. Update all tests referencing `Error_Collector`/`Error`
8. Remove `error.odin` and `reporter.odin`
9. Update e2e snapshot `.expected.toml` files

## Snapshot Co-Design

The e2e runner captures stderr from `camp build`. Since the subprocess is non-interactive (no TTY), the CLI renderer emits plain text. Snapshots are deterministic. The 14 error tests in `errors/` will need `.expected.toml` files updated to match the new format. CLI errors (no source span) render without snippet blocks.

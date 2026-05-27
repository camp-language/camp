# Domain Specification: Diagnostics

## Purpose

Produce friendly, precise compiler diagnostics with source snippets, underlines, hints, and suggestions — serving both CLI output and LSP diagnostics from a shared data model.

## Requirements

### Requirement: Typed Error Variants

The diagnostic system SHALL use sum-type error variants — one struct per error kind carrying exactly the data it needs — wrapped in a shared `Diagnostic` type.

#### Scenario: Constructing a diagnostic

- Given a specific error condition occurs in the compiler pipeline
- When the pipeline calls a `diag_*` constructor
- Then the constructor SHALL produce a `Diagnostic` with the correct `code`, `category`, `message`, `labels`, and `hints` for that error kind

### Requirement: Error Codes

Every diagnostic SHALL carry a unique `C####` error code for searchability and `camp --explain` support.

#### Scenario: Error code in diagnostic

- Given a diagnostic is created
- When the diagnostic is rendered
- Then the code SHALL appear in the header (e.g., `-- C0300: TYPE MISMATCH -- file.camp`)

#### Scenario: Error code ranges

- Given the diagnostic code system
- Then codes SHALL be organized by category: C0001–C0099 (Lexer), C0100–C0199 (Parser), C0200–C0299 (Name Resolution), C0300–C0399 (Type System), C0400–C0499 (Effect System), C0500–C0599 (Pattern Matching), C0600–C0699 (Traits/Generics), C0700–C0799 (Newtype/Nominal), C0800–C0899 (Module/Import), C0900–C0999 (Unused Warnings), C1000–C1099 (Unused Errors), C1100–C1199 (Perceus/RC), C1200–C1299 (CLI/Build), C9000–C9099 (Internal)

#### Scenario: LSP code mapping

- Given a diagnostic is mapped to LSP format
- Then the `code` field SHALL be included in the LSP diagnostic

### Requirement: Diagnostic Categories

Every diagnostic SHALL be categorized as Warning, Error, or Internal.

#### Scenario: Error diagnostic

- Given a compilation error occurs
- When the diagnostic is created
- Then its category SHALL be `Error`

#### Scenario: Warning diagnostic

- Given a compilation warning occurs
- When the diagnostic is created
- Then its category SHALL be `Warning`

#### Scenario: Internal error diagnostic

- Given an internal compiler error occurs
- When the diagnostic is created
- Then its category SHALL be `Internal` and a hint SHALL be appended prompting the user to report the bug

### Requirement: Multi-Span Diagnostics

Diagnostics SHALL support primary and secondary span annotations.

#### Scenario: Type mismatch with two spans

- Given a unification error between two expressions at different source locations
- When the diagnostic is created
- Then it SHALL contain a primary `span` and a `Span_Label` with `span_b` pointing to the secondary location

### Requirement: Hints and Suggestions

Diagnostics SHALL carry hint strings for actionable suggestions.

#### Scenario: Undefined name with similar names

- Given an undefined name reference
- When similar names exist in scope (via Levenshtein distance)
- Then the diagnostic SHALL include a hint like "Did you mean `bar`?"

#### Scenario: Undefined name with no similar names

- Given an undefined name reference
- When no similar names exist in scope
- Then the diagnostic SHALL NOT include a "Did you mean" suggestion

#### Scenario: Effectful naming error

- Given a function performs effects but lacks the `!` suffix
- Then the diagnostic SHALL include a hint suggesting the corrected name

### Requirement: CLI Rendering

The CLI renderer SHALL produce Elm-style output with headers, source snippets, underlines, and hints.

#### Scenario: Single-span error rendering

- Given a diagnostic with a single span
- When rendered for CLI output
- Then the output SHALL contain a header line (`-- {CODE}: {TITLE} -- {file_path}`), the source snippet with line numbers, a `^` underline spanning the primary span, the message, and any hints

#### Scenario: Multi-span error rendering

- Given a diagnostic with a primary span and secondary labels
- When rendered for CLI output
- Then the primary span SHALL be underlined with `^` and each secondary span SHALL be shown as a separate snippet block underlined with `~` and labeled

#### Scenario: CLI error with no source span

- Given a CLI error (e.g., file not found) with `Source_Span_ZERO`
- When rendered for CLI output
- Then the output SHALL contain the header and message but no source snippet block

### Requirement: Color Support

The CLI renderer SHALL use ANSI colors when stdout is a TTY and plain text otherwise.

#### Scenario: TTY output

- Given stdout is a TTY
- When diagnostics are rendered
- Then headers SHALL use bold red (errors), bold yellow (warnings), or bold magenta (internal); underlines, hints, and line numbers SHALL use their respective ANSI colors

#### Scenario: Non-TTY output

- Given stdout is not a TTY (piped or redirected)
- When diagnostics are rendered
- Then the output SHALL contain no ANSI escape codes

### Requirement: LSP Rendering

The LSP renderer SHALL map `Diagnostic` to LSP `PublishDiagnostics` format.

#### Scenario: Mapping diagnostic to LSP

- Given a `Diagnostic` with code, category, span, message, labels, and hints
- When mapped to LSP format
- Then `span` SHALL become `range` (byte offsets to Position), `category` SHALL become `severity` (Error=1, Warning=2, Internal=1), `code` SHALL become `code`, `message` and hint text joined with `\n\n` SHALL become `message`, and each `Span_Label` SHALL become a `relatedInformation` entry

### Requirement: Diagnostic Collector

The collector SHALL accumulate diagnostics and track counts by category.

#### Scenario: Collecting diagnostics

- Given the compiler pipeline produces diagnostics
- When each diagnostic is added to the collector
- Then the collector SHALL increment the appropriate count (warning, error, or internal) and store the diagnostic in order

#### Scenario: Summary output

- Given diagnostics have been collected
- When rendering is complete
- Then a summary line SHALL be printed: `compilation failed with {n} error(s)` for errors, or `{n} warning(s) found` for warnings-only

### Requirement: Snapshot Determinism

Diagnostic output in non-TTY mode SHALL be deterministic for snapshot testing.

#### Scenario: Snapshot compatibility

- Given the e2e runner captures stderr from `camp build`
- When the subprocess has no TTY
- Then the CLI renderer SHALL emit plain text with no color codes, and line wrapping SHALL be fixed at 80 characters

### Requirement: Error Catalog Completeness

The diagnostic system SHALL define constructors for all error variants. The complete catalog of all diagnostics, their codes, messages, hints, and rationale is documented in `docs/diagnostics-catalog.md`.

#### Scenario: Lexer errors

- Given unexpected characters or unterminated strings
- Then `diag_unexpected_char` (C0001) and `diag_unterminated_string` (C0002) SHALL produce appropriate diagnostics

#### Scenario: Parser errors

- Given expected tokens, unexpected tokens, or expected types
- Then `diag_expected_token` (C0100), `diag_unexpected_token` (C0101), and `diag_expected_type` (C0102) SHALL produce diagnostics with human-readable token names

#### Scenario: Typecheck errors

- Given effectful naming, undefined names, or unhandled effects
- Then `diag_effectful_naming` (C0400), `diag_undefined_name` (C0200), `diag_unhandled_effect` (C0401), and `diag_unhandled_effect_entry` (C0401) SHALL produce diagnostics with appropriate messages and hints

#### Scenario: Unification errors

- Given type mismatches, primitive mismatches, row conflicts, infinite types, arity mismatches, or tag arity mismatches
- Then the corresponding `diag_*` constructors SHALL produce diagnostics with both primary and secondary spans where applicable

#### Scenario: CLI errors

- Given invalid file extensions, missing files, or unknown commands
- Then `diag_invalid_extension` (C1200), `diag_file_not_found` (C1201), and `diag_unknown_command` (C1202) SHALL produce diagnostics without source snippets

#### Scenario: Unused analysis errors

- Given unused bindings, unused record fields, unused imports, pointless evaluations, contradictory prefixes, no-op assignments, or unused assignments
- Then `diag_unused_binding` (C0900), `diag_unused_record_field` (C0901), `diag_unused_import` (C0902), `diag_pointless_evaluation` (C0903), `diag_contradictory_prefix` (C1000), `diag_noop_assignment` (C1001), and `diag_unused_assignment` (C0904) SHALL produce diagnostics with appropriate messages and hints

For the complete syntax reference, see `docs/syntax-recipe.md`. For the full diagnostic catalog with all codes, messages, and rationale, see `docs/diagnostics-catalog.md`.

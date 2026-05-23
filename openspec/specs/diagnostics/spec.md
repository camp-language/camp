# Domain Specification: Diagnostics

## Purpose

Produce friendly, precise compiler diagnostics with source snippets, underlines, hints, and suggestions — serving both CLI output and LSP diagnostics from a shared data model.

## Requirements

### Requirement: Typed Error Variants

The diagnostic system SHALL use sum-type error variants — one struct per error kind carrying exactly the data it needs — wrapped in a shared `Diagnostic` type.

#### Scenario: Constructing a diagnostic

- Given a specific error condition occurs in the compiler pipeline
- When the pipeline calls a `diag_*` constructor
- Then the constructor SHALL produce a `Diagnostic` with the correct `category`, `message`, `labels`, and `hints` for that error kind

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
- Then the output SHALL contain a header line (`-- {TITLE} -- {file_path}`), the source snippet with line numbers, a `^` underline spanning the primary span, the message, and any hints

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

- Given a `Diagnostic` with category, span, message, labels, and hints
- When mapped to LSP format
- Then `span` SHALL become `range` (byte offsets to Position), `category` SHALL become `severity` (Error=1, Warning=2, Internal=1), `message` and hint text joined with `\n\n` SHALL become `message`, and each `Span_Label` SHALL become a `relatedInformation` entry

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

The diagnostic system SHALL define constructors for all error variants: lexer errors, parser errors, typecheck errors, unification errors, and CLI errors.

#### Scenario: Lexer errors

- Given unexpected characters or unterminated strings
- Then `diag_unexpected_char` and `diag_unterminated_string` SHALL produce appropriate diagnostics

#### Scenario: Parser errors

- Given expected tokens, unexpected tokens, or expected types
- Then `diag_expected_token`, `diag_unexpected_token`, and `diag_expected_type` SHALL produce diagnostics with human-readable token names

#### Scenario: Typecheck errors

- Given effectful naming, undefined names, or unhandled effects
- Then `diag_effectful_naming`, `diag_undefined_name`, and `diag_unhandled_effect` SHALL produce diagnostics with appropriate messages and hints

#### Scenario: Unification errors

- Given type mismatches, primitive mismatches, row conflicts, infinite types, arity mismatches, or tag arity mismatches
- Then the corresponding `diag_*` constructors SHALL produce diagnostics with both primary and secondary spans where applicable

#### Scenario: CLI errors

- Given invalid file extensions, missing files, or unknown commands
- Then `diag_invalid_extension`, `diag_file_not_found`, and `diag_unknown_command` SHALL produce diagnostics without source snippets

#### Scenario: Unused analysis errors

- Given unused bindings, unused record fields, unused imports, pointless evaluations, contradictory prefixes, no-op assignments, or unused assignments
- Then `diag_unused_binding`, `diag_unused_record_field`, `diag_unused_import`, `diag_pointless_evaluation`, `diag_contradictory_prefix`, `diag_noop_assignment`, and `diag_unused_assignment` SHALL produce diagnostics with appropriate messages and hints

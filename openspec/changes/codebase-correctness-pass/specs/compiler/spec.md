## MODIFIED Requirements

### Requirement: LSP analysis includes prelude types
The LSP analysis pipeline SHALL call `inject_prelude` before typechecking, so that built-in types (`Bool`, `I64`, `Str`, etc.) are available in scope.

#### Scenario: LSP diagnostics for prelude types
- **WHEN** an LSP client opens a file that references `Bool` or `I64`
- **THEN** no "undefined name" error is produced for these prelude types

### Requirement: File write errors are propagated
The compiler SHALL report an error and exit with non-zero code when writing the output `.wasm` file fails (e.g., disk full, permission denied).

#### Scenario: Write to read-only directory
- **WHEN** the compiler attempts to write to a read-only directory
- **THEN** a "FILE WRITE FAILED" error is emitted and the compiler exits with code 1

### Requirement: Parser expect returns span of expected position
`parser_expect` SHALL return a token whose span reflects the position where the expected token should have been, not the position of the token after the consumed unexpected token.

#### Scenario: Missing fat arrow in match arm
- **WHEN** a match arm is missing `=>` and `parser_expect` is called
- **THEN** the returned span points to the position where `=>` should have been, not to the next arm's pattern

### Requirement: Lexer advance has bounds check
`lexer_advance` SHALL return 0 when the lexer position is at or past the end of source, matching the guard in `lexer_peek`.

#### Scenario: Advance past end of file
- **WHEN** the lexer position equals `len(source)`
- **THEN** `lexer_advance` returns 0 without an out-of-bounds read

### Requirement: LSP diagnostic related info includes URI
`LSP_DiagnosticRelatedInfo.location` SHALL be an `LSP_Location` containing both `uri` and `range`, per the LSP specification.

#### Scenario: Related info navigates to correct file
- **WHEN** an LSP diagnostic includes related information
- **THEN** the `location` field contains a `uri` identifying the target file and a `range` identifying the target position

### Requirement: Cache readers propagate errors
`read_u32_le` and `read_u16_le` SHALL return `Option(u32)` and `Option(u16)` respectively, returning `nil` when insufficient data is available, instead of silently returning 0.

#### Scenario: Corrupt cache manifest
- **WHEN** a cache manifest file is truncated and `read_u32_le` encounters insufficient bytes
- **THEN** the function returns `nil` and the caller emits a "corrupt manifest" error

### Requirement: Shadowed name uses structured field
The `Diagnostic` struct SHALL include a `shadowed_name: Intern_ID` field set by `diag_shadow`. Unused analysis SHALL read this field instead of parsing diagnostic message strings.

#### Scenario: Shadowed name extracted from structured field
- **WHEN** a shadowing diagnostic is created for name `x`
- **THEN** `diag.shadowed_name` contains the intern ID for `"x"`, and unused analysis reads it directly without string parsing

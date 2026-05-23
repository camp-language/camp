# Diagnostics Delta Specification

## ADDED Requirements

### Requirement: Unused Binding Diagnostic
The diagnostic system SHALL provide a typed error variant for unused bindings, including the binding name and a hint suggesting the `_` prefix.

#### Scenario: Unused binding error
- **WHEN** the unused analysis detects a binding `count` that is never referenced
- **THEN** the diagnostic SHALL have category `Error`, title "UNUSED BINDING", the binding name `count`, and a hint suggesting to prefix with `_` if intentionally unused

### Requirement: Unused Record Field Diagnostic
The diagnostic system SHALL provide a typed error variant for unused record fields, including the field name and the source span of the record literal.

#### Scenario: Unused record field error
- **WHEN** the unused analysis detects a field `y` in a record literal that is never accessed locally
- **THEN** the diagnostic SHALL have category `Error`, title "UNUSED RECORD FIELD", the field name `y`, and a secondary span labeling the record literal

### Requirement: Unused Import Diagnostic
The diagnostic system SHALL provide a typed error variant for unused imports, including the import name and module name, with no suppression hint (imports are pure and cannot be `_`-prefixed).

#### Scenario: Unused import error
- **WHEN** an imported binding `bar` from `Module` is never referenced
- **THEN** the diagnostic SHALL have category `Error`, title "UNUSED IMPORT", the binding name `bar`, and the module name `Module`

### Requirement: Pointless Evaluation Diagnostic
The diagnostic system SHALL provide a typed warning variant for pointless evaluation, when a pure expression is discarded with `_ =`.

#### Scenario: Pointless pure discard warning
- **WHEN** a binding `_ = 42` or `_ = pureCompute()` is detected
- **THEN** the diagnostic SHALL have category `Warning`, title "POINTLESS EVALUATION", and a message indicating the expression is pure and its result is discarded

### Requirement: Contradictory Prefix Diagnostic
The diagnostic system SHALL provide a typed error variant for contradictory `_` and `$` prefixes, when a reassignable variable name includes both `_` and `$` prefixes.

#### Scenario: Contradictory prefix error
- **WHEN** a binding `_$x = 5` or `$_x = 5` is encountered
- **THEN** the diagnostic SHALL have category `Error`, title "CONTRADICTORY PREFIX", the binding name, and a message explaining that reassignable variables cannot be marked as unused

### Requirement: No-Op Assignment Diagnostic
The diagnostic system SHALL provide a typed error variant for no-op self-assignments.

#### Scenario: Self-assignment error
- **WHEN** a statement `$x = $x` is encountered
- **THEN** the diagnostic SHALL have category `Error`, title "NO-OP ASSIGNMENT", the variable name, and a message indicating the assignment has no effect

### Requirement: Unused Assignment Diagnostic
The diagnostic system SHALL provide a typed error variant for individual assignments to `$`-variables that are never consumed, including which assignment number and the specific reason.

#### Scenario: Overwrite before read error
- **WHEN** `$x = 1; $x = 2; print($x)` is compiled
- **THEN** the diagnostic SHALL have category `Error`, title "UNUSED ASSIGNMENT", the variable name, assignment number (1st), and a hint "value is overwritten before read"

#### Scenario: Final value never consumed error
- **WHEN** `$x = compute()` is the last assignment and `$x` is never read afterward
- **THEN** the diagnostic SHALL have category `Error`, title "UNUSED ASSIGNMENT", the variable name, and a hint "final value is never consumed"

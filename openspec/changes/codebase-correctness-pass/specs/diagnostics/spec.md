## MODIFIED Requirements

### Requirement: Unused binding diagnostics use Warning severity
The `UNUSED BINDING`, `UNUSED IMPORT`, `UNUSED ASSIGNMENT`, and `UNUSED RECORD FIELD` diagnostics SHALL use `.Warning` severity, not `.Error` severity. Programs with unused bindings SHALL compile successfully.

#### Scenario: Program with unused binding compiles
- **WHEN** a program defines `x = 42` and never uses `x`
- **THEN** the compiler emits a Warning diagnostic and the program compiles successfully (exit code 0)

#### Scenario: Program with unused import compiles
- **WHEN** a program imports `List` but never references it
- **THEN** the compiler emits a Warning diagnostic and the program compiles successfully (exit code 0)

### Requirement: Unused binding hint has matching backticks
The "Prefix with `_`" hint in `UNUSED BINDING` diagnostics SHALL have matching backticks around the suggested name: `` `_name` ``, not `` `_name ``.

#### Scenario: Hint has closing backtick
- **WHEN** the compiler emits an unused binding diagnostic for name `resume`
- **THEN** the hint reads `` Prefix with `_` to mark as intentionally unused: `_resume` ``

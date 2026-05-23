## MODIFIED Requirements

### Requirement: Unused binding diagnostic for top-level `_`-prefixed names
When a private top-level binding prefixed with `_` is never referenced, the compiler SHALL produce an error. The diagnostic SHALL NOT suggest prefixing with `_` as a remediation, since the binding already has that prefix and top-level bindings cannot be marked as unused.

#### Scenario: Top-level `_x` unused
- **GIVEN** a private module-level binding `_x = Ok(42)` that is never referenced
- **WHEN** the compiler checks for unused bindings
- **THEN** it SHALL produce an unused-binding error with a message stating top-level bindings cannot be exempted, and SHALL NOT include a hint suggesting `_` prefix

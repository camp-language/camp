## ADDED Requirements

### Requirement: Match guards
A match arm SHALL support an optional `if` guard after the pattern and before the fat arrow. The arm SHALL only match when both the pattern matches AND the guard expression evaluates to `True`.

#### Scenario: Guard filters matched pattern
- **WHEN** a match arm has pattern `n if n > 0` and the scrutinee value is `5`
- **THEN** the arm SHALL match because `n` binds to `5` and `5 > 0` evaluates to `True`

#### Scenario: Guard rejects matched pattern
- **WHEN** a match arm has pattern `n if n > 0` and the scrutinee value is `-1`
- **THEN** the arm SHALL NOT match because `n` binds to `-1` and `-1 > 0` evaluates to `False`

#### Scenario: Guard must be Bool-typed
- **WHEN** a match arm has a guard expression that does not have type `Bool`
- **THEN** the compiler SHALL produce a type error

### Requirement: Or-patterns in match arms
A match arm pattern SHALL support alternation via `|` between pattern alternatives. The arm SHALL match when ANY of the alternative patterns match.

#### Scenario: Multiple literal alternatives
- **WHEN** a match arm has pattern `1 | 2 | 3` and the scrutinee value is `2`
- **THEN** the arm SHALL match

#### Scenario: Or-pattern with variable binding
- **WHEN** a match arm has pattern `Ok(x) | Err(x)` and the scrutinee is `Err(42)`
- **THEN** the arm SHALL match and `x` SHALL be bound to `42`

#### Scenario: Or-pattern binders must have same type
- **WHEN** an or-pattern binds the same variable name in different alternatives with incompatible types
- **THEN** the compiler SHALL produce a type error

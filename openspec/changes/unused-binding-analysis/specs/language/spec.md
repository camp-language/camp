# Language Delta Specification

## MODIFIED Requirements

### Requirement: Naming Conventions
Types and tags SHALL use UpperCamelCase; functions and variables SHALL use lowercase identifiers; type and effect variables SHALL use lowercase. Bindings prefixed with a single underscore (`_name`) SHALL be recognized as intentionally unused and exempt from unused-binding analysis. Double underscores (`__name`) SHALL be reserved and SHALL NOT qualify as unused markers. Bare underscore (`_`) SHALL be a valid discard pattern.

#### Scenario: Type name casing
- GIVEN a type definition `UserId`
- WHEN the compiler checks the identifier
- THEN it SHALL accept UpperCamelCase and reject lowercase type names

#### Scenario: Function name casing
- GIVEN a function definition `map`
- WHEN the compiler checks the identifier
- THEN it SHALL accept lowercase and reject UpperCamelCase function names

#### Scenario: Single underscore prefix marks unused
- GIVEN a binding `_count = items.length`
- WHEN the compiler checks for unused bindings
- THEN it SHALL exempt `_count` from unused-binding errors

#### Scenario: Double underscore is reserved
- GIVEN a binding `__foo = 42`
- WHEN the compiler checks for unused bindings
- THEN it SHALL NOT exempt `__foo` (double underscore is reserved, not an unused marker)

#### Scenario: Bare underscore is a discard
- GIVEN a binding `_ = perform Op`
- WHEN the compiler checks for unused bindings
- THEN it SHALL treat `_` as an explicit discard and SHALL NOT produce an unused-binding error

## ADDED Requirements

### Requirement: Underscore Discard Semantics
A binding `_ = expr` SHALL evaluate the right-hand side for its effects and discard the result. The compiler SHALL emit a warning if the right-hand side is pure (no effects), since the evaluation serves no purpose.

#### Scenario: Discard with effectful expression
- GIVEN a binding `_ = perform Op`
- WHEN the compiler processes the binding
- THEN it SHALL evaluate the expression for effects and silently discard the result

#### Scenario: Discard with pure expression
- GIVEN a binding `_ = 42` or `_ = pureCompute()`
- WHEN the compiler processes the binding
- THEN it SHALL emit a warning about pointless evaluation

### Requirement: Contradictory Prefix Restriction
A binding name that combines `_` and `$` prefixes (in any order: `_$x` or `$_x`) SHALL be a compile error. The `_` prefix means "I intentionally ignore this value" and `$` means "each assignment's value matters" — these intents are contradictory.

#### Scenario: Underscore before dollar
- GIVEN a binding `_$x = 5`
- WHEN the compiler processes the binding
- THEN it SHALL produce a dedicated error stating that reassignable variables cannot be marked as unused

#### Scenario: Dollar before underscore
- GIVEN a binding `$_x = 5`
- WHEN the compiler processes the binding
- THEN it SHALL produce the same dedicated error

### Requirement: Top-Level Binding Unused Rules
Private top-level bindings that are never referenced SHALL produce a hard error. The `_` prefix SHALL NOT provide an exemption for top-level bindings. Public top-level bindings SHALL be exempt from unused checking because they may be consumed by external modules.

#### Scenario: Unused private top-level binding
- GIVEN a private module-level binding `helper = |x| x + 1` that is never referenced within the module
- WHEN the compiler checks for unused bindings
- THEN it SHALL produce an error

#### Scenario: Underscore prefix does not exempt top-level
- GIVEN a private module-level binding `_helper = |x| x + 1` that is never referenced
- WHEN the compiler checks for unused bindings
- THEN it SHALL still produce an error (top-levels cannot be `_`-exempted)

#### Scenario: Public top-level binding exempt
- GIVEN a public module-level binding `pub greet = |name| "Hello"` that is not referenced within the module
- WHEN the compiler checks for unused bindings
- THEN it SHALL NOT produce an error

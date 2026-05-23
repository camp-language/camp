## ADDED Requirements

### Requirement: Type parameters before pipe-delimited parameters
A lambda expression SHALL support declaring type parameters in angle brackets before the pipe-delimited parameter list, as in `<a>|x: a| -> a { x }`.

#### Scenario: Generic identity function
- **WHEN** a function is defined as `id = <a>|x: a| -> a { x }`
- **THEN** the compiler SHALL accept it as a generic function with type parameter `a`

#### Scenario: Type parameters followed by pipe
- **WHEN** the token sequence `<identifier>` appears before `|`
- **THEN** the parser SHALL interpret the angle brackets as type parameter declarations, not as a less-than comparison

#### Scenario: Multiple type parameters
- **WHEN** a function is defined as `f = <a, b>|x: a, y: b| -> a { x }`
- **THEN** the compiler SHALL accept it as a generic function with type parameters `a` and `b`

## ADDED Requirements

### Requirement: Inferred type parameters from annotations
Type parameters SHALL be inferred from lowercase type variables in function annotations. No explicit `<a>` syntax is needed — any lowercase type variable in the parameter or return type annotations is automatically generalized.

#### Scenario: Generic identity function
- **WHEN** a function is defined as `id = |x: a| -> a { x }`
- **THEN** the compiler SHALL accept it as a generic function with type parameter `a`

#### Scenario: Type variable in annotations
- **WHEN** a function uses a lowercase type variable like `a` in its parameter or return type annotation
- **THEN** the compiler SHALL treat `a` as an auto-generalized type parameter

#### Scenario: Multiple type variables
- **WHEN** a function is defined as `f = |x: a, y: b| -> a { x }`
- **THEN** the compiler SHALL accept it as a generic function with type parameters `a` and `b`

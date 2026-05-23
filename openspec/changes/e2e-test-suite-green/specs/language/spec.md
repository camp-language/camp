## MODIFIED Requirements

### Requirement: Primitive Types
The language SHALL provide fixed-size numeric types I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, and Bool. The boolean literals `True` and `False` SHALL have type `Bool` (a primitive type), not a tag union type.

#### Scenario: Integer literal default type
- **GIVEN** an unannotated integer literal in source code
- **WHEN** the compiler infers its type
- **THEN** the literal SHALL have type I64

#### Scenario: Float literal default type
- **GIVEN** an unannotated float literal in source code
- **WHEN** the compiler infers its type
- **THEN** the literal SHALL have type F64

#### Scenario: Explicit type override on literal
- **GIVEN** a binding with an explicit type annotation and a literal value
- **WHEN** the annotation specifies a different numeric type than the default
- **THEN** the literal SHALL have the annotated type

#### Scenario: Boolean literal type
- **GIVEN** an expression `True` or `False` in source code
- **WHEN** the compiler infers its type
- **THEN** the literal SHALL have type `Bool` (primitive), not a tag union type

#### Scenario: Boolean literal in if-condition
- **GIVEN** an expression `if True 1 else 0`
- **WHEN** the compiler typechecks the condition
- **THEN** the condition SHALL have type `Bool` and the expression SHALL typecheck without error

## ADDED Requirements

### Requirement: Inline type annotations in block scope
A binding inside a block SHALL support an inline type annotation using `name: Type = value` syntax.

#### Scenario: Typed binding in function body
- **GIVEN** a binding `i8_val: I8 = 127` inside a function body
- **WHEN** the compiler processes the binding
- **THEN** `i8_val` SHALL have type `I8`

#### Scenario: Type annotation mismatch in block
- **GIVEN** a binding `x: Str = 42` inside a function body
- **WHEN** the compiler typechecks the binding
- **THEN** the compiler SHALL produce a type mismatch error

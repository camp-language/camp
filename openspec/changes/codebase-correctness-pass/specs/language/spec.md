## MODIFIED Requirements

### Requirement: One nominal type per module
A module SHALL define at most one nominal type. The module name IS the type name. Defining a nominal type with a different name than the module produces a compiler error.

#### Scenario: Single nominal type in module
- **WHEN** a module `List.camp` defines `@List : <a> [Cons(a, List(a)) | Nil]`
- **THEN** the compiler accepts the definition

#### Scenario: Conflicting nominal type in module
- **WHEN** a module `List.camp` defines both `@List` and `@Queue`
- **THEN** the compiler emits an error indicating only one nominal type per module is allowed

### Requirement: Bool is a primitive type
`Bool` SHALL be a built-in primitive type. `True` and `False` SHALL be literal values of type `Bool`, not tag constructors. `Bool` SHALL NOT be defined as a newtype or type alias in user code.

#### Scenario: True and False are Bool literals
- **WHEN** the expression `True` appears in source code
- **THEN** it has type `Bool` (the primitive type), not a tag union `[True | False]`

#### Scenario: Bool is not user-definable
- **WHEN** a user writes `Bool : [True | False]`
- **THEN** the compiler rejects the definition because `Bool` is a reserved primitive

### Requirement: par blocks return heterogeneous tuples
`par { e1, e2, ..., en }` SHALL return a tuple `(T1, T2, ..., Tn)` where `Ti` is the type of `ei`. `par` SHALL NOT desugar to `Parallel!.all!`, which returns a homogeneous list. `par` and `Parallel!.all!` are separate, complementary mechanisms: `par` for fixed-arity heterogeneous parallel evaluation, `all!` for dynamic-arity homogeneous parallel evaluation.

#### Scenario: par with heterogeneous types
- **WHEN** `par { fetchUser(id), fetchOrders(id) }` is evaluated where `fetchUser` returns `User` and `fetchOrders` returns `List(Order)`
- **THEN** the result type is `(User, List(Order))`

#### Scenario: Parallel.all! with homogeneous types
- **WHEN** `Parallel!.all!([|| task1(), || task2(), || task3()])` is called where each task returns `I64`
- **THEN** the result type is `List(I64)`

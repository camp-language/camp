# Generics and Traits — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's generic type parameters and trait system: parametric polymorphism via monomorphization, structural trait verification with nominal opt-in, UFCS dispatch, trait inheritance, orphan rules, and constraint checking.

## Requirements

### Requirement: Generic Type Parameters

Functions and newtypes SHALL support type parameters declared in angle brackets before the parameter list. Type parameters SHALL be substituted with concrete types via monomorphization at compile time.

#### Scenario: Generic function declaration

- GIVEN a definition `add = <a>|x: a, y: a| -> a { x + y }`
- WHEN compiled
- THEN `add` SHALL be a generic function with type parameter `a`

#### Scenario: Generic function instantiation

- GIVEN a generic function `add = <a>|x: a, y: a| -> a`
- WHEN called as `add(1, 2)`
- THEN the type parameter `a` SHALL be instantiated as `I64` and the call SHALL type-check

#### Scenario: Different instantiations produce distinct types

- GIVEN `add(I64, I64)` and `add(Str, Str)`
- WHEN compiled
- THEN two specialized versions of `add` SHALL be generated — one for `I64` and one for `Str`

#### Scenario: Ambiguous type parameter rejected

- GIVEN a generic function `identity = <a>|x: a| -> a { x }`
- WHEN called as `identity()` with no argument
- THEN the compiler SHALL produce an error because `a` cannot be determined

### Requirement: Monomorphization

The compiler SHALL specialize every generic function and type at each concrete instantiation site. After monomorphization, no generic type variables SHALL remain in the program. Specialized functions SHALL be named with a `$` separator followed by the concrete type arguments.

#### Scenario: Monomorphization generates specialized functions

- GIVEN a generic function `identity = <a>|x: a| -> a { x }` called with `I64` and `Str`
- WHEN the compiler monomorphizes
- THEN two specialized functions SHALL exist: `identity$I64` and `identity$Str`

#### Scenario: Recursive generic instantiation terminates

- GIVEN a generic function `List.map = <a, b>|f: |a| -> b, list: List(a)| -> List(b)` whose body calls itself at a different type
- WHEN the compiler monomorphizes
- THEN the worklist-driven BFS SHALL discover all required instantiations and terminate — each unique (function, type-args) pair SHALL be specialized exactly once

#### Scenario: No generic code in output

- GIVEN a program that uses generic functions
- WHEN monomorphization completes
- THEN the resulting program SHALL contain no generic type variables — every function SHALL have concrete parameter and return types

### Requirement: Trait Declaration

Traits SHALL declare method signatures using structural types. The first parameter of each method SHALL represent `Self` — the implementing type. `Self` SHALL be a contextual keyword recognized only within trait method signatures.

#### Scenario: Trait with methods

- GIVEN a declaration `trait Display { display : Self -> Str }`
- WHEN the compiler processes it
- THEN the trait SHALL be registered with one method `display` whose first parameter is `Self`

#### Scenario: Self is contextual

- GIVEN the identifier `Self` used outside a trait method signature
- WHEN the compiler processes it
- THEN `Self` SHALL be treated as an ordinary identifier, not a keyword

### Requirement: Trait Structural Verification

When a type declares `is Trait`, the compiler SHALL verify that the type's methods match the trait's required signatures by shape. Structural conformance alone — without the `is` declaration — SHALL NOT satisfy the trait.

#### Scenario: Nominal opt-in required

- GIVEN a type whose methods match trait `Display` by shape but without an `is Display` declaration
- WHEN the type is used where `Display` is required
- THEN the compiler SHALL produce an error

#### Scenario: Structural verification upon opt-in

- GIVEN a type declared `is Display`
- WHEN the compiler verifies the declaration
- THEN it SHALL check that the type's methods match `Display`'s required signatures by shape

#### Scenario: Method signature mismatch

- GIVEN a type declared `is Display` but whose `display` method returns `I64` instead of `Str`
- WHEN the compiler verifies the declaration
- THEN it SHALL produce a type mismatch error

### Requirement: Trait Orphan Rule

An `is` declaration SHALL appear only in the module that defines the type or the module that defines the trait. Third-module implementations SHALL be rejected.

#### Scenario: Orphan implementation in third module

- GIVEN module A defines type `T`, module B defines trait `Foo`, and module C declares `T is Foo`
- WHEN the compiler processes module C
- THEN it SHALL produce an orphan rule violation error

#### Scenario: Valid implementation in type's module

- GIVEN module A defines type `T` and also declares `T is Foo`
- WHEN the compiler processes module A
- THEN the `is` declaration SHALL be accepted

#### Scenario: Valid implementation in trait's module

- GIVEN module B defines trait `Foo` and also declares `T is Foo` for a type `T` defined in another module
- WHEN the compiler processes module B
- THEN the `is` declaration SHALL be accepted

### Requirement: No Overlapping Instances

Each type SHALL have at most one `is` declaration per trait. A second `is` declaration for the same type and trait SHALL produce an error.

#### Scenario: Duplicate trait implementation

- GIVEN a type that declares `is Display` twice
- WHEN the compiler processes the second declaration
- THEN it SHALL produce an overlapping instance error

### Requirement: Trait Inheritance (Transitive)

Traits SHALL support single inheritance via `is`. When a type declares `is Ord` and `Ord is Eq`, the type SHALL automatically satisfy `Eq`. The compiler SHALL transitively check all inherited trait conformance.

#### Scenario: Inheritance implies parent conformance

- GIVEN a trait `Ord is Eq` and a type declared `is Ord`
- WHEN the compiler verifies conformance
- THEN the type SHALL also be required to implement `Eq` methods
- AND `is Ord` SHALL satisfy any context requiring `Eq`

#### Scenario: Missing parent trait methods

- GIVEN a trait `Ord is Eq` and a type declared `is Ord` that implements `compare` but not `eq`
- WHEN the compiler verifies conformance
- THEN it SHALL produce an error listing the missing `eq` method from trait `Eq`

#### Scenario: Inheritance chain

- GIVEN `trait A`, `trait B is A`, `trait C is B`, and a type declared `is C`
- WHEN the compiler verifies conformance
- THEN the type SHALL be required to implement methods from `A`, `B`, and `C`

### Requirement: Trait Constraints on Type Parameters

Type parameters SHALL support trait constraints using `is` syntax. When a constrained type variable is unified with a concrete type, the compiler SHALL immediately verify the constraint is satisfied.

#### Scenario: Constrained type parameter

- GIVEN a definition `format = <a is Display>|x: a| -> Str { x.display() }`
- WHEN compiled
- THEN `a` SHALL be constrained to types that satisfy `Display`

#### Scenario: Constraint satisfied at call site

- GIVEN `format` with constraint `<a is Display>` and a type `UserId is Display`
- WHEN `format(userId)` is called
- THEN the call SHALL type-check because `UserId` satisfies `Display`

#### Scenario: Constraint violated at call site

- GIVEN `format` with constraint `<a is Display>` and a type `I64` that does NOT `is Display`
- WHEN `format(42)` is called
- THEN the compiler SHALL produce an error: `I64` does not satisfy `Display`

#### Scenario: Multiple constraints

- GIVEN a definition `sort = <a is Ord>|list: List(a)| -> List(a) { ... }`
- WHEN the compiler processes the constraint
- THEN `a` SHALL be required to satisfy `Ord` (which transitively requires `Eq`)

### Requirement: UFCS Dispatch

Method calls SHALL use Uniform Function Call Syntax: `x.display()` SHALL desugar to a call to the trait's implementing function with `x` as the first argument. For concrete types, the dispatch SHALL resolve to a direct function call at monomorphization time.

#### Scenario: Trait method call via dot syntax

- GIVEN a value `x` of type `UserId is Display`
- WHEN `x.display()` is called
- THEN it SHALL resolve to the implementing function `UserId_display(x)`

#### Scenario: UFCS inside generic function

- GIVEN a generic function `format = <a is Display>|x: a| -> Str { x.display() }`
- WHEN monomorphized at `a = UserId`
- THEN `x.display()` SHALL resolve to `UserId_display(x)`

#### Scenario: Method not found

- GIVEN a type `I64` that does NOT `is Display`
- WHEN `x.display()` is called on a value of type `I64`
- THEN the compiler SHALL produce a "method not found" error

### Requirement: No Higher-Kinded Types

Type parameters SHALL always be kind `*`. Type constructor parameters SHALL NOT be supported.

#### Scenario: Higher-kinded type parameter rejected

- GIVEN a function signature using a type constructor parameter like `<f: * -> *>`
- WHEN the compiler processes it
- THEN it SHALL produce a syntax error

### Requirement: Static-Only Dispatch

All trait dispatch SHALL be resolved at monomorphization time via static function calls. There SHALL be no vtables, no dynamic dispatch, and no trait objects (existential types) in this implementation phase.

#### Scenario: No runtime dispatch

- GIVEN a trait method call `x.display()` where `x` has a known concrete type
- WHEN the compiler generates code
- THEN the call SHALL be a direct WASM `call` instruction to the implementing function — no `call_indirect` for trait dispatch

#### Scenario: Trait-constrained value in data structure

- GIVEN a `List` containing values of type `a is Display` where `a` is a type parameter
- WHEN monomorphized at `a = UserId`
- THEN the `List` SHALL be `List(UserId)` and all trait calls resolved statically

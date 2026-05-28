# Language Specification

## Purpose

Camp is a strictly-typed functional programming language that compiles to
WASM/WASI. This specification defines the behavioral requirements of the Camp
language — what programs SHALL do and what the compiler SHALL enforce — without
prescribing implementation strategy.

This spec covers core language semantics unique to Camp. Requirements that are
shared with or elaborated by other specs are referenced here and defined in
full in their authoritative spec:

- **Effects** (effect rows, handlers, effect safety, prelude effects): `docs/effects-spec.md`
- **Generics & Traits** (trait definitions, conformance, UFCS, type parameters, inheritance): `docs/generics-traits-spec.md`
- **String Interpolation** (Display trait, string literal kinds, interpolation escape): `docs/syntax-recipe.md`
- **Unused Analysis** (underscore/dollar prefix rules, discard semantics, contradictory prefix, top-level unused): `docs/syntax-recipe.md`
- **Parallelism** (par block syntax, Parallel!/Spawn!/Async! effects): `docs/syntax-recipe.md`
- **Modules** (visibility, unified namespace, import conflicts): `docs/modules-spec.md`

For the complete syntax reference (declarations, expressions, patterns, imports, effects, entry point), see `docs/syntax-recipe.md`.

## Requirements

### Requirement: Primitive Types
The language SHALL provide fixed-size numeric types I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, and Bool.

#### Scenario: Integer literal default type
- GIVEN an unannotated integer literal in source code
- WHEN the compiler infers its type
- THEN the literal SHALL have type I64

#### Scenario: Float literal default type
- GIVEN an unannotated float literal in source code
- WHEN the compiler infers its type
- THEN the literal SHALL have type F64

#### Scenario: Explicit type override on literal
- GIVEN a binding with an explicit type annotation and a literal value
- WHEN the annotation specifies a different numeric type than the default
- THEN the literal SHALL have the annotated type

### Requirement: Tag Union Construction
Tag variants SHALL be constructed with bare UpperCamelCase names and no prefix symbol (e.g., `Ok(42)`, `None`). Newtype construction SHALL use an `@`-prefixed name (e.g., `@UserId(42)`).

#### Scenario: Tag with payload
- GIVEN a tag name starting with an uppercase letter followed by a parenthesized payload
- WHEN the expression is evaluated
- THEN the result SHALL be a value of a tag union type containing that tag variant

#### Scenario: Tag without payload
- GIVEN a bare UpperCamelCase identifier with no parentheses
- WHEN the expression is evaluated
- THEN the result SHALL be a tag union value with no payload for that variant

#### Scenario: Case-based disambiguation of tags and functions
- GIVEN an identifier `Ok` (uppercase first letter) and an identifier `ok` (lowercase first letter)
- WHEN the compiler resolves each identifier
- THEN `Ok` SHALL be resolved as a tag and `ok` SHALL be resolved as a function or variable

### Requirement: Tag Union Types
Tag union types SHALL support closed, open, and fully open forms with consistent syntax.

#### Scenario: Closed tag union type
- GIVEN a type annotation `[Ok(a) | Err(e)]` with no `..`
- WHEN the compiler type-checks values of that type
- THEN the type SHALL accept exactly the listed tags and no others

#### Scenario: Open tag union type with rest variable
- GIVEN a type annotation `[Ok(a) | Err(e) | ..rest]`
- WHEN the compiler type-checks values of that type
- THEN the type SHALL accept at least the listed tags, with remaining tags captured as the row variable `rest`

#### Scenario: Fully open tag union type
- GIVEN a type annotation `[..]`
- WHEN the compiler type-checks values of that type
- THEN the type SHALL accept zero or more tags

### Requirement: Variant Set Inference
The type of a tag union SHALL be inferred from the tags that appear in a scope.

#### Scenario: Branches returning different tags
- GIVEN a function that returns `Ok(42)` in one branch and `Err("fail")` in another
- WHEN the compiler infers the return type
- THEN the inferred type SHALL be `[Ok(I64) | Err(Str)]`

#### Scenario: Adding a new tag variant widens the type
- GIVEN a function whose return type was inferred as `[Ok(I64) | Err(Str)]`
- WHEN a new branch returning `Timeout` is added
- THEN the inferred type SHALL widen to `[Ok(I64) | Err(Str) | Timeout]`

### Requirement: Nominal Tag Qualification
Tags belonging to a nominal type SHALL be module-qualified at construction (e.g., `Result.Ok(42)`), never `@`-prefixed. Newtypes SHALL use the `@` prefix at construction (e.g., `@UserId(42)`).

#### Scenario: Qualified tag construction
- GIVEN a nominal type `@Result` and a tag `Ok` belonging to it
- WHEN constructing a value from outside `Result` module
- THEN the construction SHALL use `Result.Ok(42)` unless the tag is imported unqualified

#### Scenario: Unqualified import of nominal tags
- GIVEN an import statement `import Result { [Ok, Err] }`
- WHEN constructing a value using `Ok`
- THEN `Ok(42)` SHALL be valid without the `Result.` qualifier

### Requirement: Record Types
Records SHALL be structural products with insignificant field order, supporting closed, open, and row-variable forms.

#### Scenario: Closed record type
- GIVEN a type annotation `{ name: Str, age: U64 }` with no `..`
- WHEN the compiler type-checks values
- THEN the type SHALL accept exactly those fields and no others

#### Scenario: Open record type with row variable
- GIVEN a type annotation `{ name: Str, ..rest }`
- WHEN the compiler type-checks values
- THEN the type SHALL accept any record with at least a `name: Str` field

#### Scenario: Field order insignificance
- GIVEN two record types `{ name: Str, age: U64 }` and `{ age: U64, name: Str }`
- WHEN the compiler compares them
- THEN they SHALL be considered the same type

#### Scenario: Record functional update
- GIVEN an expression `{ ..record, name: "new" }`
- WHEN evaluated
- THEN the result SHALL be a new record with all fields from `record` except `name`, which SHALL have the value `"new"`

### Requirement: Row Polymorphism
Functions SHALL accept any record that has the required fields, regardless of additional fields.

#### Scenario: Function accepting open record
- GIVEN a function with parameter type `{ name: Str, .. }`
- WHEN called with `{ name: "Alice", age: 30 }`
- THEN the call SHALL type-check successfully

### Requirement: Type Aliases
Type aliases SHALL create transparent structural shorthands using the `:` syntax (no `@` prefix). Type aliases SHALL unify with any structurally identical type. Type aliases SHALL NOT have `derives` or `is` clauses.

#### Scenario: Alias for a primitive
- GIVEN a definition `IntList : List(I64)`
- WHEN the compiler processes it
- THEN `IntList` SHALL be a transparent alias for `List(I64)`

#### Scenario: Alias for a record
- GIVEN a definition `Coords : { x: F64, y: F64 }`
- WHEN the compiler compares `Coords` with `{ x: F64, y: F64 }`
- THEN they SHALL unify as the same type

#### Scenario: Alias for a tag union with type parameters
- GIVEN a definition `Maybe(a) : [Just(a) | Nothing]`
- WHEN the compiler processes it
- THEN `Maybe` SHALL be a transparent alias parameterized by `a`

#### Scenario: Alias transparency
- GIVEN an alias `Alias : [Left(a) | Right(Str)]` and a structural type `[Left(a) | Right(Str)]`
- WHEN the compiler compares them
- THEN they SHALL unify as the same type

### Requirement: Nominal Types
Nominal types SHALL create a distinct type based on its name rather than its structure, using the `@` prefix at the definition site and `:` syntax. Nominal types provide encapsulation, trait implementations, and tag ownership. The `@` prefix SHALL appear at the definition site for all nominal types (e.g., `@UserId`, `@Result`). At construction/destruction, the `@` prefix SHALL be used for NEWTYPES only (e.g., `@UserId(42)`), NOT for tag variants (e.g., `Ok(42)`, `Result.Ok(42)`). The `@` prefix SHALL NOT appear in type annotations.

#### Scenario: Nominal type definition
- GIVEN a definition `@UserId : U64`
- WHEN the compiler processes it
- THEN `UserId` SHALL be a nominal type wrapping `U64`, distinct from `U64`

#### Scenario: Nominal type construction
- GIVEN a nominal type `@UserId : U64` defined in the current module
- WHEN constructing a value
- THEN `@UserId(42)` SHALL produce a value of type `UserId`, distinct from `U64`

#### Scenario: Nominal type destruction
- GIVEN a nominal type `@UserId : U64` and a value `uid: UserId`
- WHEN pattern matching `@UserId(n) => n`
- THEN `n` SHALL be bound to the inner `U64` value

#### Scenario: Nominal type in type annotations
- GIVEN a nominal type `@UserId : U64`
- WHEN writing a type annotation
- THEN the annotation SHALL use the plain name: `x : UserId`, NOT `x : @UserId`

#### Scenario: Nominal type nominal distinctness
- GIVEN nominal types `@UserId : U64` and `@OrderId : U64`
- WHEN the compiler compares `UserId` and `OrderId`
- THEN they SHALL NOT unify — they are distinct types despite wrapping the same inner type

#### Scenario: No implicit coercion between nominal type and inner type
- GIVEN a nominal type `@UserId : U64` and a function expecting `U64`
- WHEN a value of type `UserId` is passed without destructuring
- THEN the compiler SHALL produce an error

#### Scenario: Nominal type wrapping a record
- GIVEN a nominal type `@User : { name: Str, age: U64 }`
- WHEN constructing a value
- THEN `@User({ name: "Alice", age: 30 })` SHALL produce a value of type `User`

#### Scenario: Nominal type wrapping a tag union
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN constructing a value with the `Ok` tag
- THEN `Result.Ok(42)` SHALL be required — bare `Ok(42)` SHALL NOT resolve unless exposed via import

#### Scenario: One nominal type per module
- GIVEN a module named `Result`
- WHEN a nominal type `@Result` is defined within it
- THEN the definition SHALL be accepted; defining a nominal type with a different name SHALL produce a compiler error

### Requirement: Nominal Type Encapsulation
Nominal types SHALL be opaque outside their defining module unless their variants are explicitly exposed with `pub`. Non-tag-union nominal types SHALL always be opaque outside their defining module.

#### Scenario: Opaque by default
- GIVEN a nominal type `@UserId : U64` defined in module `UserId`
- WHEN another module imports `UserId` without importing variants
- THEN the other module SHALL NOT construct or destructure `@UserId` values; it SHALL only pass them and call functions on them

#### Scenario: Non-tag-union nominal type is always opaque
- GIVEN a nominal type `@UserId : U64` defined in module `UserId`
- WHEN another module imports `UserId`
- THEN the other module SHALL NOT construct or destructure `@UserId` values regardless of import list; the defining module SHALL provide constructor/destructor functions (e.g., `makeUserId : U64 -> UserId`)

#### Scenario: pub variants enable cross-module construction
- GIVEN a nominal type `@Result(a, e) : pub [Ok(a) | Err(e)]` defined in module `Result`
- WHEN another module imports `Result`
- THEN the other module SHALL be able to construct values via `Result.Ok(42)`

#### Scenario: pub variants with variant import enable unqualified access
- GIVEN a nominal type `@Result(a, e) : pub [Ok(a) | Err(e)]` and `import Result { [Ok, Err] }`
- WHEN constructing a value
- THEN `Ok(42)` SHALL be valid without the `Result.` qualifier

#### Scenario: Importing non-pub variants is an error
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]` (without `pub`)
- WHEN another module writes `import Result { [Ok, Err] }`
- THEN the compiler SHALL produce an error because the variants are not exposed

### Requirement: Nominal Type Tag Ownership
When a nominal type wraps a tag union, its tags SHALL be owned by that nominal type and module-qualified at construction (e.g., `Result.Ok(42)`). The `@` prefix is NOT used on tag variants — it is reserved for newtype construction (e.g., `@UserId(42)`).

#### Scenario: Qualified tag construction with @ prefix
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN constructing a value with the `Ok` tag
- THEN `Result.Ok(42)` SHALL be required — bare `Ok(42)` SHALL NOT resolve unless exposed via import

#### Scenario: Structural tags remain unqualified
- GIVEN a tag `Some(42)` that does NOT belong to any nominal type
- WHEN constructing a value
- THEN `Some(42)` SHALL be valid without any qualifier

#### Scenario: Tag ownership prevents collision
- GIVEN nominal types `@Result(a, e) : [Ok(a) | Err(e)]` and `@Option(a) : [Ok(a) | None]` in different modules
- WHEN both are in scope
- THEN the `Ok` tag SHALL be disambiguated by its owning type: `Result.Ok` vs `Option.Ok`

#### Scenario: Qualified tag in pattern matching
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN pattern matching a value of type `Result(I64, Str)`
- THEN `Result.Ok(n) => n` SHALL match the `Ok` tag and bind `n` to the inner `I64`

#### Scenario: Unqualified tag in pattern matching via import
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]` and `import Result { [Ok, Err] }`
- WHEN pattern matching
- THEN `Ok(n) => n` SHALL be valid and equivalent to `Result.Ok(n) => n`

### Requirement: Parameterized Nominal Types
Nominal types SHALL support type parameters, enabling generic nominal types.

#### Scenario: Parameterized nominal type declaration
- GIVEN a definition `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN the compiler processes the declaration
- THEN `Result` SHALL be a nominal type parameterized by `a` and `e`

#### Scenario: Parameterized nominal type instantiation
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN constructing `Result.Ok(42)` where the context expects `Result(I64, Str)`
- THEN the type parameters SHALL be inferred as `a = I64`, `e = Str`

#### Scenario: Different instantiations are distinct
- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN the compiler compares `Result(I64, Str)` and `Result(Str, I64)`
- THEN they SHALL NOT unify — different type arguments produce distinct types

### Requirement: Type Inference
The compiler SHALL perform principal type inference using bidirectional checking with effect row unification.

#### Scenario: Inferred types for local bindings
- GIVEN a binding `add = |x, y| x + y` with no type annotations
- WHEN the compiler infers the type
- THEN it SHALL produce a principal type including generic type variables and any constraints

### Requirement: Function Syntax
All functions SHALL use `|args| body` syntax as the sole function form. Lambda parameters are not limited to one — multiple parameters are separated by commas. Generic constraints via `where` clauses SHALL appear after the parameters and before the body.

#### Scenario: Named function definition
- GIVEN a binding `add = |x: Int, y: Int| -> Int { x + y }`
- WHEN compiled
- THEN it SHALL define a function named `add` with the specified parameter and return types

#### Scenario: Multi-parameter lambda
- GIVEN a binding `pair = |a, b| { { fst: a, snd: b } }`
- WHEN compiled
- THEN it SHALL define a function that accepts two parameters and returns a record

#### Scenario: Anonymous lambda
- GIVEN an expression `|x| x + 1`
- WHEN evaluated
- THEN it SHALL produce a function that adds 1 to its argument

#### Scenario: No fn or def keyword
- GIVEN source code using `fn` or `def` to declare a function
- WHEN the compiler parses it
- THEN it SHALL produce a syntax error

#### Scenario: Block body required for typed definitions
- GIVEN a function definition with a return type annotation
- WHEN the body is provided
- THEN the body SHALL be wrapped in `{ }` braces

#### Scenario: Where clause on function
- GIVEN a function `map = |f: a -> b, items: List(a)| where a is Eq, b is Ord -> List(b) { ... }`
- WHEN compiled
- THEN the `where` clause SHALL constrain the type parameters, appearing after the parameters and before the body

### Requirement: Effectful Function Naming
A function with a non-empty effect row SHALL be named with a `!` suffix; a function named without `!` SHALL have an empty effect row.

#### Scenario: Effectful function name enforcement
- GIVEN a function whose effect row is non-empty
- WHEN the function is named without a `!` suffix
- THEN the compiler SHALL produce an error

#### Scenario: Pure function name enforcement
- GIVEN a function whose effect row is empty
- WHEN the function is named with a `!` suffix
- THEN the compiler SHALL produce an error

### Requirement: Entry Point
The program entry point SHALL be a `pub` function named `main!` returning a value that implements the `Termination` trait (I64, {}, Result(a, e)). The effect row of `main!` SHALL include `Console!` and `Throw!([..])`.

#### Scenario: Main function definition
- GIVEN a program entry point `pub main! = || -[Console! | Throw!([..])]-> I64 { 0 }`
- WHEN the compiler processes it
- THEN the function SHALL be the entry point with effect row `[Console! | Throw!([..])]`

#### Scenario: Main returns any Termination type
- GIVEN `pub main! = || -[Console! | Throw!([..])]-> {} { {} }`
- WHEN the runtime executes the program
- THEN the runtime SHALL call `Termination.report` on the returned value

### Requirement: Naming Conventions
Types and tags SHALL use UpperCamelCase; functions and variables SHALL use lowercase identifiers; type and effect variables SHALL use lowercase. For underscore and dollar prefix rules (unused markers, discard semantics, contradictory prefixes, top-level unused rules), see `docs/syntax-recipe.md`.

#### Scenario: Type name casing
- GIVEN a type definition `UserId`
- WHEN the compiler checks the identifier
- THEN it SHALL accept UpperCamelCase and reject lowercase type names

#### Scenario: Function name casing
- GIVEN a function definition `map`
- WHEN the compiler checks the identifier
- THEN it SHALL accept lowercase and reject UpperCamelCase function names

### Requirement: Mutable Variable Syntax
Mutable bindings SHALL use a `$` prefix at declaration and at every use site, and SHALL be stack-local only.

#### Scenario: Mutable variable declaration
- GIVEN a statement `$total = 0` where `$total` does not exist in scope
- WHEN compiled
- THEN it SHALL declare a mutable binding named `$total`

#### Scenario: Mutable variable reassignment
- GIVEN an existing mutable binding `$total` in the same function scope
- WHEN `$total = $total + 1` is evaluated
- THEN the value of `$total` SHALL be updated

#### Scenario: Dollar prefix on immutable binding rejected
- GIVEN a statement `$x = 42` followed by no reassignment of `$x`
- WHEN the compiler checks the binding
- THEN it SHALL accept `$` as valid since the binding is declared mutable

#### Scenario: Mutable variable cannot escape function
- GIVEN a mutable binding `$x` defined inside a function
- WHEN a closure captures `$x` and escapes the function
- THEN the compiler SHALL produce error C1002 (MUTABLE CAPTURE)

#### Scenario: Mutable variable shadowing across scopes rejected
- GIVEN a mutable binding `$x` in an enclosing scope
- WHEN a new `$x` is declared in a nested scope
- THEN the compiler SHALL produce an error because shadowing is forbidden

### Requirement: Logic Operators
Boolean logic SHALL use `and` and `or` keywords; the operators `&&` and `||` SHALL NOT be valid.

#### Scenario: And keyword
- GIVEN an expression `True and False`
- WHEN evaluated
- THEN the result SHALL be `False`

#### Scenario: Symbol operator rejection
- GIVEN an expression using `&&` or `||`
- WHEN the compiler parses it
- THEN it SHALL produce a syntax error

### Requirement: Dot Lambda
A leading `.` SHALL create an anonymous function that applies a method/function/field chain to its argument. Three call syntaxes SHALL be supported: `.method(args)` for nominal dispatch, `.->func(args)` for lexical UFCS, and `.(field)(args)` for structural dispatch.

#### Scenario: Dot lambda with method call (nominal dispatch)
- GIVEN an expression `.foo(x)`
- WHEN the compiler desugars it
- THEN it SHALL be equivalent to `|a| a.foo(x)`

#### Scenario: Dot lambda with lexical UFCS
- GIVEN an expression `.->func(x)`
- WHEN the compiler desugars it
- THEN it SHALL be equivalent to `|a| a->func(x)`

#### Scenario: Dot lambda with structural dispatch
- GIVEN an expression `.(field)(x)`
- WHEN the compiler desugars it
- THEN it SHALL be equivalent to `|a| (a.field)(x)`

#### Scenario: Dot lambda with field access
- GIVEN an expression `.name`
- WHEN the compiler desugars it
- THEN it SHALL be equivalent to `|a| a.name`

#### Scenario: Dot lambda with chained access
- GIVEN an expression `.foo().bar(x)`
- WHEN the compiler desugars it
- THEN it SHALL be equivalent to `|a| a.foo().bar(x)`

#### Scenario: Dot lambda in expression position
- GIVEN a call `list.map(.name)`
- WHEN compiled
- THEN `.name` SHALL desugar to a lambda that extracts the `name` field

#### Scenario: Effect row propagation through dot lambda
- GIVEN a dot lambda `.read!()`
- WHEN the compiler determines its effect row
- THEN the desugared lambda SHALL carry the same effect row as `read!`

#### Scenario: Disambiguation from spread syntax
- GIVEN a token `..`
- WHEN the compiler parses it
- THEN it SHALL be interpreted as the spread operator, never as two dot lambdas

### Requirement: Inline Type Annotations
Type annotations SHALL be written inline with `:` on the binding, never as a separate declaration above it.

#### Scenario: Inline binding annotation
- GIVEN a statement `x: Int = 3`
- WHEN compiled
- THEN `x` SHALL have type `Int`

#### Scenario: Separate type declaration rejected
- GIVEN a type annotation `x : Int` on a separate line from the binding `x = 3`
- WHEN the compiler parses it
- THEN it SHALL produce a syntax error

### Requirement: No Shadowing
All shadowing SHALL be forbidden — a binding name SHALL NOT be reused in the same scope or any nested scope.

#### Scenario: Same-scope rebinding
- GIVEN two bindings `x = 1` then `x = 2` in the same scope
- WHEN the compiler checks the second binding
- THEN it SHALL produce an error

#### Scenario: Nested-scope shadowing
- GIVEN a binding `x = 1` in an outer scope and `x = 2` in a nested scope
- WHEN the compiler checks the nested binding
- THEN it SHALL produce an error

#### Scenario: Destructuring with conflicting name
- GIVEN a binding `name = "old"` in scope and a destructuring `{ name, age } = record`
- WHEN the compiler checks the destructuring
- THEN it SHALL produce an error because `name` already exists in scope

#### Scenario: Import name conflict
- GIVEN an existing binding `map` in scope and an import that exposes `map`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error

### Requirement: Unified Namespace
Each module SHALL have one namespace for functions, values, types, traits, effects, and aliases. For visibility rules and import conflict detection, see `docs/modules-spec.md`.

#### Scenario: Type and function name conflict
- GIVEN a module that defines both a type `Result` and a function `Result`
- WHEN the compiler processes the module
- THEN it SHALL produce an error

#### Scenario: UFCS disambiguation via unified namespace
- GIVEN a unified namespace containing function `method` and a record field also named `method`
- WHEN `x.method()` is called
- THEN it SHALL be resolved as a function call because the function and the field share one namespace

### Requirement: Visibility
The `pub` keyword SHALL mark module exports; all other definitions SHALL be private to the module. For full visibility enforcement rules, see `docs/modules-spec.md`.

#### Scenario: Public export
- GIVEN a definition `pub greet = |name| "Hello, ${name}!"`
- WHEN another module imports this module
- THEN `greet` SHALL be accessible

#### Scenario: Private definition inaccessible
- GIVEN a definition `helper = |x| x + 1` without `pub`
- WHEN another module attempts to import `helper`
- THEN the compiler SHALL produce an error

### Requirement: Raw Identifiers
Identifiers wrapped in backticks SHALL escape keyword conflicts and be usable as ordinary names.

#### Scenario: Keyword as identifier
- GIVEN a binding `` `do` = 42 ``
- WHEN compiled
- THEN `do` SHALL be usable as a variable name despite being a keyword

#### Scenario: Backtick style over r# prefix
- GIVEN source code using `r#type` as a raw identifier
- WHEN the compiler parses it
- THEN it SHALL produce a syntax error; only backtick-wrapped raw identifiers are valid

### Requirement: Destructive Read Guarantee
Perceus last-use optimization SHALL be a semantic guarantee: the compiler SHALL prove last-use and reuse allocations in-place, and programmers SHALL be able to reason about when reuse occurs.

#### Scenario: Last-use in-place reuse
- GIVEN a value that is consumed for the last time before being overwritten
- WHEN the compiler performs reuse analysis
- THEN it SHALL mutate the existing allocation in-place rather than allocating a new copy

#### Scenario: Mutable variable reuse
- GIVEN a mutable binding `$x` and a reassignment `$x = $x + 1` where `$x` is last-used on the right side
- WHEN the compiler determines reuse is safe
- THEN the allocation SHALL be updated in-place

### Requirement: Pattern Matching Exhaustiveness
Pattern matching SHALL require exhaustive coverage; the wildcard `_` SHALL match any remaining variants.

#### Scenario: Exhaustive match on closed union
- GIVEN a closed tag union `[Ok(a) | Err(e)]` and a match with cases for `Ok` and `Err`
- WHEN the compiler checks exhaustiveness
- THEN the match SHALL be accepted

#### Scenario: Non-exhaustive match rejected
- GIVEN a closed tag union `[Ok(a) | Err(e)]` and a match with only an `Ok` case
- WHEN the compiler checks exhaustiveness
- THEN it SHALL produce an error

#### Scenario: Wildcard catch-all
- GIVEN a match with explicit cases for some variants and `_ =>` as a final case
- WHEN the compiler checks exhaustiveness
- THEN the match SHALL be accepted

#### Scenario: Redundant wildcard warning
- GIVEN a match on a closed union where all variants are already covered explicitly and `_ =>` is present
- WHEN the compiler checks exhaustiveness
- THEN it SHALL produce a warning that the wildcard is unreachable

#### Scenario: Open union requires at least one handler
- GIVEN an open tag union type and a match expression
- WHEN the match has at least one case or `_ =>`
- THEN the match SHALL be accepted

### Requirement: Dual Error Model
The language SHALL provide two error mechanisms: the `Throw!` effect for exceptional errors and tag union returns for structural absence; there SHALL be no `?` operator. For full effect semantics, handler behavior, and prelude effect definitions, see `docs/effects-spec.md`.

#### Scenario: Throw! effect for exceptional errors
- GIVEN a function that calls `Throw!.raise!("error")`
- WHEN the compiler infers the effect row
- THEN the function's effect row SHALL include `Throw!([Str])`

#### Scenario: Tag union return for structural absence
- GIVEN a function `List.first` returning `Some(a) | None`
- WHEN the caller uses the result
- THEN the caller SHALL handle absence via pattern matching, not via `Throw!`

#### Scenario: No question mark operator
- GIVEN source code using `?` for error propagation
- WHEN the compiler parses it
- THEN it SHALL produce a syntax error

#### Scenario: Handler bridging Throw! to tag union
- GIVEN a handler `handle Throw! in { Ok(action()) } with { .raise!(resume, err) => Err(err) }`
- WHEN the handler executes
- THEN a thrown error SHALL be caught and returned as `Err(err)`

### Requirement: Consistent Dot-Dot Syntax
The `..` operator SHALL mean "and possibly more" consistently across type annotations, destructuring, and record update.

#### Scenario: Dot-dot in record type
- GIVEN `{ name: Str, .. }`
- WHEN the compiler interprets it
- THEN it SHALL mean a record with at least `name: Str`, possibly more fields

#### Scenario: Dot-dot in tag union type
- GIVEN `[Ok(a) | ..]`
- WHEN the compiler interprets it
- THEN it SHALL mean a tag union with at least `Ok(a)`, possibly more variants

#### Scenario: Dot-dot in destructuring
- GIVEN `{ name, .. } = record`
- WHEN the compiler interprets it
- THEN it SHALL extract `name` and ignore any additional fields

### Requirement: Effects, Handlers, and Prelude Effects
Effect row syntax, effect safety, effect polymorphism, parameterized effects with variant widening, one-shot continuations, deep handlers only (handler reinstalls on continuation), effect composition via aliases, and prelude effect definitions (Console!, Throw!, Parallel!, Spawn!, Async!, File!, Env!, Time!, Random!, Log!, Crypto.Random!) are defined in `docs/effects-spec.md`.

### Requirement: Traits, Generics, and UFCS
Trait definitions, nominal type trait conformance (`is`/`derives`), trait structural verification, the strict orphan rule (type must be local), UFCS dispatch, generic type parameters with `where` clause constraints, trait inheritance (`is` on trait definitions), and the prohibition on higher-kinded types are defined in `docs/generics-traits-spec.md`.

### Requirement: String Interpolation and Display
The Display trait, interpolated string literal kinds (plain, interpolated, raw, multiline), string interpolation escape (`\$`), and the Display constraint on interpolation holes are defined in `docs/syntax-recipe.md`.

### Requirement: Parallelism and par Blocks
The `par` block syntax (`par { e1, e2 }` and `par for x in xs { body }`), Parallel!/Spawn!/Async! effect operations, and parallel method sugar are defined in `docs/syntax-recipe.md`.

### Requirement: Unused Binding Analysis
Underscore prefix rules for unused markers, underscore discard semantics, contradictory underscore-dollar prefix restriction, and top-level binding unused rules are defined in `docs/syntax-recipe.md`.

## ADDED Requirements

### Requirement: Hybrid Prelude Architecture

The compiler SHALL inject built-in type constructors, tags, effect names, and operator functions in Odin code during prelude injection. Actual stdlib module logic (List.map, Iter.filter, etc.) SHALL live in Camp-language .camp files that are embedded in the compiler binary.

#### Scenario: Odin-injected type available in user code

- **GIVEN** the prelude injects `List` as a constructor with arity 1
- **WHEN** a user writes `x : List(I64)` without importing anything
- **THEN** the typechecker SHALL recognize `List` and `I64`

#### Scenario: .camp file provides module logic

- **GIVEN** a `stdlib/List.camp` file defining `map = <a, b>|f: |a| -> b, xs: List(a)| -> List(b) { ... }`
- **WHEN** a user writes `import List` and calls `List.map(f, xs)`
- **THEN** the compiler SHALL resolve `map` from the embedded stdlib module

### Requirement: Stdlib .camp Files Embedded in Compiler Binary

The compiler binary SHALL embed all stdlib .camp files at build time. At runtime, the module system SHALL resolve `import <name>` by checking the user's `src/` directory first, then the embedded stdlib directory second.

#### Scenario: Stdlib module resolved without file on disk

- **GIVEN** a user program that imports `List` with no `List.camp` in the project's `src/` directory
- **WHEN** the compiler resolves the import
- **THEN** it SHALL find `List` in the embedded stdlib and compile it

#### Scenario: Project-local module takes priority

- **GIVEN** a project with `src/List.camp` and the embedded stdlib also has `List.camp`
- **WHEN** the compiler resolves `import List`
- **THEN** it SHALL use the project-local `src/List.camp`, not the embedded one

### Requirement: Runtime WASM Primitives

The compiler SHALL inject WASM runtime functions for operations that cannot be written in Camp: memory allocation, list operations, string operations, file I/O, environment access, time, and random number generation.

#### Scenario: List allocation from Camp code

- **GIVEN** Camp code that constructs a list `[1, 2, 3]`
- **WHEN** compiled to WASM
- **THEN** the generated code SHALL call `camp_list_alloc` and `camp_list_push` runtime functions

#### Scenario: Console output from Camp code

- **GIVEN** Camp code that calls `Console!.println!("hello")`
- **WHEN** compiled to WASM with a Console! handler
- **THEN** the handler SHALL call `camp_print_str` which calls WASI `fd_write`

### Requirement: Prelude Type and Tag Injection

The prelude SHALL inject the following as Odin-injected type declarations:

**Types**: I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Bool, Str, Bytes, Unit, List, Iter, Map, Set, Handle, Ordering, Result, Option

**Tags**: True, False, Ok, Err, Some, None, Less, Equal, Greater, Nil, Cons

**Effect names**: Console!, Throw!, Async!, Parallel!, Spawn!, File!, Env!, Time!, Random!, Log!, Crypto.Random!

#### Scenario: All primitive types available without import

- **GIVEN** a Camp program with no imports
- **WHEN** the typechecker processes it
- **THEN** all primitive types (I8..U64, F32, F64, Bool, Str, Bytes, Unit) SHALL be in scope

#### Scenario: Collection constructors available without import

- **GIVEN** a Camp program with no imports
- **WHEN** the typechecker processes `x : List(I64)` or `m : Map(Str, I64)`
- **THEN** `List` and `Map` SHALL be recognized as type constructors

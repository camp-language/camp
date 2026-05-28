# Modules — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's module system: project discovery, multi-file compilation, import resolution, visibility enforcement, prelude injection, and incremental compilation with content-hash caching.

## Requirements
### Requirement: Project Discovery

The compiler SHALL discover the project root by walking up from the current working directory. If `camp.toml` is found, that directory SHALL be the project root. If no `camp.toml` is found but a `src/` directory containing `.camp` files is found, the project SHALL be treated as having an implicit empty manifest (legacy compatibility). All `.camp` files under `src/` SHALL be compiled as part of the project.

#### Scenario: Standard project with camp.toml

- GIVEN a directory with `camp.toml` at the root and `src/Main.camp`, `src/List.camp`, `src/Http/Server.camp`
- WHEN the compiler is invoked from any subdirectory
- THEN all three files SHALL be discovered and compiled using the `camp.toml` manifest

#### Scenario: Legacy project without camp.toml

- GIVEN a directory structure with `src/Main.camp` but NO `camp.toml`
- WHEN the compiler is invoked from the project root
- THEN the project SHALL compile with an implicit empty manifest (no dependencies)

#### Scenario: Neither camp.toml nor src/ found

- GIVEN a directory with no `camp.toml` and no `src/` subdirectory containing `.camp` files
- WHEN the compiler is invoked
- THEN it SHALL produce an error: "no Camp project found — expected camp.toml or src/ directory with .camp files"

### Requirement: File-to-Module Mapping

Each `.camp` file SHALL map to a module name derived from its path relative to `src/`. The `.camp` extension SHALL be stripped and path separators replaced with dots.

#### Scenario: Top-level module

- GIVEN a file at `src/List.camp`
- WHEN the compiler maps the file to a module name
- THEN the module name SHALL be `List`

#### Scenario: Nested directory module

- GIVEN a file at `src/Http/Server.camp`
- WHEN the compiler maps the file to a module name
- THEN the module name SHALL be `Http.Server`

#### Scenario: Module name conflict

- GIVEN files at `src/List.camp` and `src/List/Index.camp`
- WHEN the compiler maps both files
- THEN `src/List.camp` SHALL map to module `List` and `src/List/Index.camp` SHALL map to module `List.Index` — no conflict

### Requirement: Entry Point

The compiler SHALL use `src/Main.camp` as the default entry point. The entry point module SHALL define a `pub main!` function.

#### Scenario: Standard entry point

- GIVEN a file `src/Main.camp` containing `pub main! = || -[Console! | Throw!([..])]-> I64 { ... }`
- WHEN the compiler builds the project
- THEN `Main` SHALL be the entry point and `main!` SHALL be the program entry function

#### Scenario: Missing entry point

- GIVEN a project with no `src/Main.camp`
- WHEN the compiler is invoked
- THEN it SHALL produce an error: "entry point not found — expected src/Main.camp with pub main!"

#### Scenario: Entry point without main

- GIVEN a file `src/Main.camp` that does not define `main!`
- WHEN the compiler builds the project
- THEN it SHALL produce an error: "entry point module Main does not define pub main!"

### Requirement: Import Resolution

The compiler SHALL resolve imports by verifying that imported modules exist in the project and that requested names are exported by those modules.

#### Scenario: Qualified import

- GIVEN an import declaration `import List`
- WHEN the compiler resolves the import
- THEN the module `List` SHALL be accessible via qualified access `List.member` for all `pub` members of `List`

#### Scenario: Selective import

- GIVEN an import declaration `import List { map, filter }`
- WHEN the compiler resolves the import
- THEN `map` and `filter` SHALL be accessible unqualified AND `List.map` and `List.filter` SHALL also be accessible

#### Scenario: Importing nominal type variants

- GIVEN an import declaration `import Result { [Ok, Err], other_fn }`
- WHEN the compiler resolves the import
- THEN `Ok` and `Err` SHALL be accessible unqualified for construction and pattern matching, AND `Result.Ok` SHALL also be accessible; the `[Ok, Err]` syntax signals nominal type variant exposure

#### Scenario: Exposing nominal variants requires pub on type definition

- GIVEN a nominal type `@Result(a, e) : [Ok(a) | Err(e)]` (without `pub`) and `import Result { [Ok, Err] }`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error because the variants are not publicly exposed on the type definition

#### Scenario: Importing effect operations

- GIVEN an import declaration `import Console { Console!, println!, readline! }`
- WHEN the compiler resolves the import
- THEN `Console!` and its operations `println!` and `readline!` SHALL be accessible unqualified; the `!` is part of the actual name

#### Scenario: Aliased import

- GIVEN an import declaration `import Http.Server as S`
- WHEN the compiler resolves the import
- THEN `S.member` SHALL resolve to `Http.Server.member` for all `pub` members

#### Scenario: Module not found

- GIVEN an import declaration `import Nonexistent`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error: "module 'Nonexistent' not found"

#### Scenario: Importing a non-exported name

- GIVEN an import declaration `import List { helper }` where `helper` is not `pub` in `List`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error: "'helper' is not exported from module 'List'"

#### Scenario: Qualified access to private member

- GIVEN code in module A that references `List.helper` where `helper` is not `pub` in `List`
- WHEN the compiler resolves the reference
- THEN it SHALL produce an error: "'helper' is not exported from module 'List'"

### Requirement: Import Conflict Detection

An import that brings a name into unqualified scope that already exists SHALL be an error.

#### Scenario: Import conflicts with local binding

- GIVEN a local binding `map = 42` and an import `import List { map }`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error: "'map' imported from List conflicts with existing binding — use qualified access List.map"

#### Scenario: Two imports bringing in the same name

- GIVEN `import List { map }` and `import Dict { map }`
- WHEN the compiler resolves the imports
- THEN it SHALL produce an error: "'map' is ambiguous — imported from both List and Dict; use qualified access"

### Requirement: Cyclic Dependency Detection

The module dependency graph SHALL be acyclic. If a cycle is detected, the compiler SHALL produce an error listing the cycle.

#### Scenario: Direct cycle

- GIVEN module A imports B and module B imports A
- WHEN the compiler builds the module graph
- THEN it SHALL produce an error: "cyclic dependency: A → B → A"

#### Scenario: Indirect cycle

- GIVEN module A imports B, B imports C, and C imports A
- WHEN the compiler builds the module graph
- THEN it SHALL produce an error: "cyclic dependency: A → B → C → A"

### Requirement: Visibility Enforcement

The `pub` keyword SHALL mark declarations as exported from their defining module. All declarations without `pub` SHALL be private — accessible only within the defining module.

#### Scenario: Public function accessible

- GIVEN module `List` defines `pub map = ...`
- WHEN another module imports `List`
- THEN `List.map` SHALL be accessible

#### Scenario: Private function inaccessible

- GIVEN module `List` defines `helper = ...` (no `pub`)
- WHEN another module references `List.helper`
- THEN the compiler SHALL produce an error: "'helper' is not exported from module 'List'"

#### Scenario: Private function accessible within defining module

- GIVEN module `List` defines `helper = ...` (no `pub`)
- WHEN code within `List` references `helper`
- THEN it SHALL resolve successfully

#### Scenario: Newtype with pub tags

- GIVEN a `pub` nominal type `@Result(a, e) : [Ok(a) | Err(e)]`
- WHEN another module imports `Result { [Ok, Err] }`
- THEN `Ok(42)` SHALL be valid without the `Result.` qualifier

### Requirement: Unified Namespace per Module

Each module SHALL have one namespace for functions, values, types, traits, effects, nominal types, and aliases. A module SHALL NOT define both a type and a function with the same name.

#### Scenario: Type and function name conflict within module

- GIVEN a module that defines both a nominal type `Result` and a function `Result`
- WHEN the compiler processes the module
- THEN it SHALL produce an error: "name 'Result' is already defined in this module"

### Requirement: Prelude Injection

Every Camp file SHALL implicitly import builtin types and operations before processing user imports. The compiler SHALL inject these into the type checker environment directly — no source file required.

#### Scenario: Builtin types available by default

- GIVEN a Camp file with no explicit imports
- WHEN the compiler typechecks the file
- THEN `Bool`, `I64`, `U64`, `F64`, `Str`, `True`, `False` SHALL be in scope

#### Scenario: Prelude types are nominal

- GIVEN the builtin `Bool` type
- WHEN the compiler processes `True and False`
- THEN `Bool` SHALL be a primitive type with literal values `True` and `False`

#### Scenario: Prelude opt-out

- GIVEN a file containing `import Camp {}`
- WHEN the compiler processes the file
- THEN no builtin types or operations SHALL be in implicit scope

### Requirement: Per-File Content Hash Caching

The compiler SHALL cache per-file compilation results keyed by content hash. Parse and canonicalization results SHALL be cacheable by the file's SHA256 content hash. Typecheck results SHALL be cacheable by the file's content hash combined with the sorted content hashes of all imported modules.

#### Scenario: Unchanged file reuses cache

- GIVEN a file `List.camp` whose content has not changed since last compilation
- WHEN the compiler runs again
- THEN the parsed and canonicalized forms SHALL be loaded from cache without re-processing

#### Scenario: Changed file invalidates cache

- GIVEN a file `List.camp` whose content has changed since last compilation
- WHEN the compiler runs again
- THEN the file SHALL be re-parsed and re-canonicalized

#### Scenario: Dependency change invalidates typecheck cache

- GIVEN a file `Main.camp` that imports `List.camp`, and `List.camp` has changed
- WHEN the compiler runs again
- THEN `Main.camp`'s parse and canonicalization cache SHALL be reused BUT its typecheck SHALL be re-run

#### Scenario: Cache location

- GIVEN a Camp compiler invocation
- WHEN the compiler stores cached results
- THEN they SHALL be stored under `$XDG_CACHE_HOME/camp/` (defaulting to `~/.cache/camp/`)

### Requirement: Separate Front-End, Whole-Program Back-End

Phases 1–3 (parse, canonicalize, typecheck) SHALL be per-file and cacheable. Module graph combination SHALL link all per-file results. Phases 5–9 (effect lower through codegen) SHALL be whole-program.

#### Scenario: Parallel front-end processing

- GIVEN a project with 10 `.camp` files
- WHEN the compiler processes the front-end
- THEN all 10 files MAY be parsed and canonicalized in parallel

#### Scenario: Whole-program back-end

- GIVEN all per-file typecheck results are available
- WHEN the compiler begins lowering
- THEN all modules' IR SHALL be combined into a single whole-program IR before code generation

### Requirement: Cross-Module Type Compatibility

Types SHALL unify across module boundaries. Structural types (records, tag unions) SHALL unify by shape regardless of which module defines them. Nominal types SHALL only unify with themselves.

#### Scenario: Structural record unification across modules

- GIVEN module A returns `{ name: Str, age: U64 }` and module B expects `{ name: Str, age: U64 }`
- WHEN the compiler checks cross-module compatibility
- THEN the types SHALL unify successfully

#### Scenario: Nominal type distinctness across modules

- GIVEN module A defines `@UserId : U64` and module B defines `@OrderId : U64`
- WHEN the compiler checks cross-module compatibility
- THEN `UserId` SHALL NOT unify with `OrderId`

### Requirement: WASM Name Namespace Collisions

When combining multiple modules' IR into a whole-program IR, function names SHALL be qualified to avoid collisions. The WASM export for `List.map` SHALL use a mangled name such that it does not collide with `Dict.map`.

#### Scenario: Two modules define the same function name

- GIVEN module `List` defines `pub map = ...` and module `Dict` defines `pub map = ...`
- WHEN the compiler generates WASM
- THEN the two `map` functions SHALL have distinct WASM names (e.g. `List__map` and `Dict__map`)

### Requirement: Runtime Deduplication

The runtime helper functions (`camp_alloc`, `camp_dup`, `camp_drop`, `camp_print_str`, `camp_exit`) SHALL be emitted exactly once in the final WASM binary, regardless of how many modules are compiled.

#### Scenario: Multiple modules, single runtime

- GIVEN a project with 5 modules
- WHEN the compiler generates the WASM binary
- THEN runtime helper functions SHALL appear exactly once

For the complete syntax reference, see `docs/syntax-recipe.md`.

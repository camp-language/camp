# Compiler Behavioral Specification

## Purpose

Define the behavioral requirements for the Camp compiler: a source-to-WASM/WASI pipeline that enforces type and effect safety, preserves deterministic memory semantics via Perceus reference counting, and never crashes unexpectedly.

For string interpolation compilation (AST nodes, typechecking, desugaring, lexer tokens, parsing), see `openspec/specs/string-interpolation/spec.md`. For unused binding analysis rules, see `openspec/specs/unused-analysis/spec.md`.

## Requirements

### Requirement: Source-to-WASM Compilation

The compiler SHALL accept Camp source text and produce valid WASM/WASI modules.

#### Scenario: Compile a simple program

- **WHEN** Camp source `"main! = || -> I64 { 42 }"` is compiled
- **THEN** the compiler SHALL produce a valid WASM/WASI module that exits with code 42

### Requirement: No Silent Crashes

The compiler SHALL never crash unexpectedly. All impossible or invalid internal states SHALL be reported as `InternalCompilerError` diagnostics rather than causing panics, segfaults, or silent miscompilation.

#### Scenario: Internal error on impossible state

- **WHEN** a compiler phase encounters an IR node combination that should be impossible after a preceding validation pass
- **THEN** it SHALL emit an `InternalCompilerError` diagnostic with source span and continue or terminate gracefully — it SHALL NOT crash

### Requirement: Match Pattern Typechecking

The compiler SHALL typecheck match patterns against their scrutinee types. Pattern variables SHALL be bound into the type environment with correct types. Pattern structure (tags, records, literals) SHALL be unified against the scrutinee type. Exhaustiveness SHALL be checked for closed tag unions.

#### Scenario: Match pattern with wrong tag

- **WHEN** Camp source contains a non-exhaustive match on a `Bool` type matching only `True`
- **THEN** the compiler SHALL report a non-exhaustive match diagnostic listing `False` as a missing tag

### Requirement: Closure Capture

The compiler SHALL correctly capture free variables in closures. A closure SHALL close over all variables referenced in its body that are not defined locally. Each captured variable SHALL be stored in the closure's environment record and accessible at runtime.

#### Scenario: Closure captures free variable

- **WHEN** Camp source defines `make_adder = |n| { |x| x + n }`
- **THEN** the resulting closure record SHALL contain `n` in its environment and `fn_idx` SHALL point to a real function index in the WASM table

### Requirement: Higher-Order Calls

The compiler SHALL use WASM `call_indirect` for all calls where the callee is not a direct name reference. Each closed-over function SHALL receive an entry in the WASM element table. The closure record SHALL carry `fn_idx` and `env_ptr` fields used by `call_indirect`.

#### Scenario: Higher-order function call

- **WHEN** Camp source defines `apply = |f, x| { f(x) }`
- **THEN** the call to `f` SHALL use `call_indirect` with the closure's `fn_idx` and `env_ptr`

### Requirement: Perceus Reference Counting

The compiler SHALL preserve variable reads during Perceus RC insertion. `IR_Var` nodes SHALL NOT be replaced by `IR_Dup` or `IR_Drop`. Instead, `dup` and `drop` SHALL be inserted around variable uses: `dup` before non-last uses, `drop` at scope end, and `drop` of the binding when a variable has zero uses.

#### Scenario: Perceus preserves variable reads

- **WHEN** an `IR_Let` binding `x` is used twice in its body
- **THEN** the first use of `x` SHALL be preceded by `dup(x)` and the `IR_Var(x)` node SHALL be preserved — it SHALL NOT be replaced by `IR_Dup`

### Requirement: CPS Transformation

The compiler SHALL generate continuation functions for every effectful sub-expression during CPS transformation. A `let y = f(x) in body` where `f` is effectful SHALL become `f(x, fun(y) { body })`. Both branches of an `if` under a continuation SHALL tail-call the same continuation. Pure expressions SHALL be transformed without introducing continuations.

#### Scenario: CPS generates continuations

- **WHEN** Camp source contains `y = Foo!.get!() in y + 1` (within a handler block)
- **THEN** CPS transformation SHALL create a continuation function `fun(y) { y + 1 }` and pass it as an extra argument to the `perform`

### Requirement: Effect Lowering Evidence

The compiler SHALL provide an evidence argument for every handled `perform`. When no handler is found on the evidence stack (`ev_var == NO_NAME`), the compiler SHALL emit an `InternalCompilerError` diagnostic — unhandled performs must be caught by the typechecker before effect lowering runs. The lowered perform SHALL NOT silently omit the evidence argument.

#### Scenario: Missing evidence is a compiler error

- **WHEN** an `IR_Perform` with `ev_var == NO_NAME` is processed during effect lowering
- **THEN** it SHALL emit an `InternalCompilerError` diagnostic and lower to `IR_Literal_Int{0}` rather than silently omitting the evidence argument

### Requirement: Sound Generalization

The compiler SHALL check that all children of `Inferred_Type` structures are at or below the generalization level before generalizing a type variable. A type variable SHALL NOT be promoted to `LEVEL_GENERIC` if any child `Type_Var_ID` within its `Inferred_Type` link has a level greater than the generalization level.

#### Scenario: Generalization rejects unsound child levels

- **WHEN** a type variable at level 2 is linked to an `Inferred_Type` containing a child type variable at level 3
- **AND** generalization runs at level 2
- **THEN** the type variable SHALL NOT be promoted to `LEVEL_GENERIC` because the child exceeds the generalization level

### Requirement: Crash Semantics

The compiler SHALL preserve crash semantics through all compilation phases. `CExpr_Crash` SHALL lower to `IR_Crash`, which SHALL traverse all mid-end passes, and SHALL codegen to `Wasm_Unreachable`.

#### Scenario: Crash node traverses mid-end

- **WHEN** Camp source contains a `crash` expression
- **THEN** the crash expression SHALL survive as `IR_Crash` through closure_convert, effect_lower, cps, and rc, and codegen to `Wasm_Unreachable`

### Requirement: Diagnostics

The compiler SHALL report a diagnostic for every error condition. No error SHALL be silently swallowed. All diagnostics SHALL include sufficient context (source span, relevant names) for the programmer to locate and fix the error.

#### Scenario: Diagnostic includes source context

- **WHEN** the compiler encounters a type error in source code
- **THEN** it SHALL emit a diagnostic containing the source span and relevant names, enabling the programmer to locate and fix the error

### Requirement: Deterministic Output

The compiler SHALL produce deterministic output for identical inputs. Given the same source text and compiler version, the output WASM module SHALL be byte-identical across invocations.

#### Scenario: Deterministic compilation

- **WHEN** the same Camp source file is compiled twice
- **THEN** the WASM binaries SHALL be byte-identical

### Requirement: Monomorphization

The compiler SHALL specialize all generic functions at each concrete type instantiation before lowering. The monomorphization pass SHALL operate after typechecking on a typed IR representation. It SHALL use a worklist-driven BFS algorithm: each call site with concrete type arguments seeds a specialization; specialization of bodies may discover further generic calls, which are added to the worklist. After monomorphization, no generic type variables SHALL remain in the program. For the monomorphization guarantee (no generic code in output, each unique (function, type-args) pair specialized exactly once), see `openspec/specs/generics-traits/spec.md`.

#### Scenario: Generic function specialized at concrete type

- **WHEN** a generic function `identity = |x: a| -> a { x }` is called with `I64` and `Str`
- **THEN** monomorphization SHALL produce two specialized functions with concrete types — no generic type variable `a` shall remain

#### Scenario: Recursive generic instantiation terminates

- **WHEN** a generic function's body calls another generic function at a different type
- **THEN** the worklist BFS SHALL discover the new instantiation, add it to the worklist, and terminate once all reachable instantiations are specialized — each unique (function, type-args) pair specialized exactly once

#### Scenario: Ambiguous type parameter produces error

- **WHEN** a generic function's type parameter cannot be determined from any call site
- **THEN** the compiler SHALL produce an error reporting the ambiguous type parameter

### Requirement: Typed IR Between Typecheck and Lower

The compiler SHALL produce a typed IR (TFile) after typechecking, before monomorphization and lowering. Every expression node in the typed IR SHALL carry its inferred `Type_Var_ID` and effect row `Type_Var_ID`. The typed IR SHALL enable deep-clone-and-substitute monomorphization and provide lower with direct type access.

#### Scenario: Typed IR carries type information

- **WHEN** the compiler converts a typechecked canonical AST to typed IR
- **THEN** every TExpr node SHALL include `type_id` and `eff_id` fields populated from the typechecker's inference results

### Requirement: Unused Binding Analysis Pass

The compiler SHALL run an unused binding analysis pass after typechecking and before lowering. The pass SHALL detect unused bindings, unused record fields, unused imports, pointless evaluations, contradictory prefixes, no-op assignments, and unused assignments. The pass SHALL emit appropriate diagnostics for each detected issue. For the full unused analysis rules, see `openspec/specs/unused-analysis/spec.md`.

#### Scenario: Unused binding analysis in pipeline

- **WHEN** the compiler processes a Camp source file
- **THEN** it SHALL run the unused binding analysis after typechecking and before lowering, emitting diagnostics for any detected issues

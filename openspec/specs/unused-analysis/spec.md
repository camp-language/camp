# Domain Specification: Unused Analysis

### Requirement: Unused Immutable Binding Detection
The compiler SHALL emit a hard error when an immutable binding (e.g., `x = expr`) is never read in any code path, unless the binding name is prefixed with `_` (bare `_` or `_name` form).

#### Scenario: Unused immutable binding
- **WHEN** a binding `count = items.length` is defined and `count` is never referenced
- **THEN** the compiler SHALL produce an error indicating the binding is unused

#### Scenario: Unused binding with underscore prefix exempted
- **WHEN** a binding `_count = items.length` is defined and `_count` is never referenced
- **THEN** the compiler SHALL NOT produce an unused-binding error

#### Scenario: Bare wildcard binding exempted
- **WHEN** a binding `_ = perform Op` is defined
- **THEN** the compiler SHALL NOT produce an unused-binding error for `_`

#### Scenario: Double underscore is not an unused marker
- **WHEN** a binding `__foo = 42` is defined and `__foo` is never referenced
- **THEN** the compiler SHALL produce an unused-binding error (double underscore is reserved, not an unused marker)

### Requirement: Pointless Evaluation Warning
The compiler SHALL emit a warning when a `_ = expr` binding discards a pure expression, since the evaluation serves no purpose.

#### Scenario: Discarding a pure expression
- **WHEN** a binding `_ = 42` or `_ = pureCompute()` is defined
- **THEN** the compiler SHALL emit a warning about pointless evaluation

#### Scenario: Discarding an effectful expression is valid
- **WHEN** a binding `_ = perform Op` or `_ = Console.println!("hi")` is defined
- **THEN** the compiler SHALL NOT emit a warning (the effect justifies the expression)

### Requirement: Contradictory Underscore-Dollar Prefix Error
The compiler SHALL emit a dedicated error when a reassignable variable name combines `_` and `$` prefixes (e.g., `_$x` or `$_x`), since `_` means "ignore this value" and `$` means "each value matters."

#### Scenario: Underscore before dollar prefix
- **WHEN** a binding `_$x = 5` is encountered
- **THEN** the compiler SHALL produce a dedicated error stating that reassignable variables cannot be marked as unused

#### Scenario: Dollar before underscore prefix
- **WHEN** a binding `$_x = 5` is encountered
- **THEN** the compiler SHALL produce the same dedicated error as `_$x`

### Requirement: Reassignable Variable Per-Assignment Tracking
Each assignment to a `$`-variable SHALL be tracked as a distinct value that MUST be consumed. An assignment that is overwritten before any possible read SHALL be an error.

#### Scenario: Overwrite before read
- **WHEN** `$x = 1; $x = 2; print($x)` is compiled
- **THEN** the compiler SHALL produce an error indicating the first assignment (value `1`) was overwritten before being read

#### Scenario: Path-insensitive possible use
- **WHEN** `$x = 1; if cond { print($x) }; $x = 2; print($x)` is compiled
- **THEN** the compiler SHALL NOT produce an error for the first assignment, because a code path exists where it could be read

#### Scenario: Final assignment must be consumed
- **WHEN** `$x = compute()` is the last assignment to `$x` in a scope and `$x` is never read afterward
- **THEN** the compiler SHALL produce an error indicating the final value is never consumed

#### Scenario: Self-assignment is a no-op error
- **WHEN** `$x = $x` is encountered (assigning a variable to itself)
- **THEN** the compiler SHALL produce a dedicated no-op assignment error

### Requirement: Loop Structural Dead Value Exemption
The exit assignment (last assignment in a loop body) of a `$`-variable SHALL be exempt from the "must be consumed after the loop" rule IF the `$`-variable has essential reads within the loop body. An essential read is one that transitively reaches an observable effect (effectful call, perform, return, or escape).

#### Scenario: Loop counter with effectful use — exempt
- **WHEN** `$count = 0; for item in items.iter() { $count = $count + 1; Console.println!($count) }` is compiled and `$count` is not read after the loop
- **THEN** the compiler SHALL NOT produce an error, because the `$`-var has essential reads (effectful call) in the loop body

#### Scenario: Loop counter with pure-only use — error
- **WHEN** `$count = 0; for item in items.iter() { if matches(item) { $count = $count + 1 } }` is compiled and `$count` is not read after the loop
- **THEN** the compiler SHALL produce an error, because the `$`-var has no essential reads (the `$count + 1` read is non-essential — consumed only by self-reassignment)

#### Scenario: Unused reassignable variable in loop — error
- **WHEN** `$temp = 0; for item in items.iter() { $temp = compute(item) }` is compiled and `$temp` is never read
- **THEN** the compiler SHALL produce an error for each assignment, because the `$`-var has no reads at all

#### Scenario: Overwrite before read inside loop — error (except exit)
- **WHEN** `$x = 0; for item in items.iter() { $x = 1; Console.println!($x); $x = 2 }` is compiled
- **THEN** the compiler SHALL produce an error for the non-exit `$x = 2` assignments (overwritten before read by next iteration), but the final iteration's `$x = 2` SHALL be exempt as the exit assignment

### Requirement: Unused Pattern Match Binder Detection
Each sub-binding introduced by a pattern match SHALL be independently checked for unused-ness. Bindings not prefixed with `_` that are never referenced SHALL produce an error.

#### Scenario: Unused pattern binder
- **WHEN** `match expr { Some(x) => Ok(0) }` is compiled and `x` is never referenced in the arm body
- **THEN** the compiler SHALL produce an unused-binding error for `x`

#### Scenario: Unused pattern binder with underscore prefix
- **WHEN** `match expr { Some(_x) => Ok(0) }` is compiled
- **THEN** the compiler SHALL NOT produce an unused-binding error for `_x`

#### Scenario: Wildcard pattern in match
- **WHEN** `match expr { Some(_) => Ok(0) }` is compiled
- **THEN** the compiler SHALL NOT produce an unused-binding error (bare `_` is a discard)

### Requirement: Unused Destructuring Sub-Binding Detection
Each sub-binding in a destructuring pattern SHALL be independently checked. Bindings not prefixed with `_` that are never referenced SHALL produce an error. Underscore holes (`_`) in destructuring positions SHALL be valid discards.

#### Scenario: Unused destructured field
- **WHEN** `{ name, age } = record` is compiled and `age` is never referenced
- **THEN** the compiler SHALL produce an unused-binding error for `age`

#### Scenario: Underscore hole in destructuring
- **WHEN** `{ name, _ } = record` is compiled
- **THEN** the compiler SHALL NOT produce an error (the `_` hole is an explicit discard)

#### Scenario: Underscore-prefixed field in destructuring
- **WHEN** `{ name, _age } = record` is compiled and `_age` is never referenced
- **THEN** the compiler SHALL NOT produce an error

### Requirement: Unused Iteration Variable Detection
Iteration variables in `for` loops SHALL be checked like immutable bindings. An iteration variable that is never referenced in the loop body and is not `_`-prefixed SHALL produce an error.

#### Scenario: Unused iteration variable
- **WHEN** `for item in items.iter() { Console.println!("processing") }` is compiled and `item` is never referenced
- **THEN** the compiler SHALL produce an unused-binding error for `item`

#### Scenario: Underscore-prefixed iteration variable
- **WHEN** `for _item in items.iter() { Console.println!("processing") }` is compiled
- **THEN** the compiler SHALL NOT produce an error

### Requirement: Unused Top-Level Binding Detection
Private top-level bindings that are never referenced SHALL produce a hard error. The `_` prefix SHALL NOT provide an exemption for top-level bindings. Public top-level bindings SHALL be exempt from unused checking.

#### Scenario: Unused private top-level binding
- **WHEN** a private binding `helper = |x| x + 1` is defined at module scope and never referenced
- **THEN** the compiler SHALL produce an unused-binding error

#### Scenario: Underscore prefix does not exempt top-level
- **WHEN** a private binding `_helper = |x| x + 1` is defined at module scope and never referenced
- **THEN** the compiler SHALL still produce an unused-binding error (top-level bindings cannot be `_`-exempted)

#### Scenario: Public top-level binding exempt
- **WHEN** a public binding `pub greet = |name| "Hello, ${name}!"` is defined at module scope and not referenced within the module
- **THEN** the compiler SHALL NOT produce an error (public bindings may be consumed externally)

### Requirement: Unused Import Detection
Import bindings that are never referenced SHALL produce a hard error. The `_` prefix SHALL NOT provide an exemption for imports, since imports are always pure.

#### Scenario: Unused named import
- **WHEN** `import Module { foo, bar }` is compiled and `bar` is never referenced
- **THEN** the compiler SHALL produce an unused-import error for `bar`

#### Scenario: Underscore prefix does not exempt imports
- **WHEN** `import Module { foo, _bar }` is compiled and `_bar` is never referenced
- **THEN** the compiler SHALL still produce an unused-import error

#### Scenario: Unused whole-module import
- **WHEN** `import Module as M` is compiled and `M` is never referenced
- **THEN** the compiler SHALL produce an unused-import error

### Requirement: Unused Record Field Detection
Record literal fields that are never accessed in the local scope SHALL produce a hard error, unless the record escapes the scope. When a record escapes (passed as fn argument, returned, or used in perform), all its fields SHALL be considered used.

#### Scenario: Unused field in local record
- **WHEN** `r = { x: 1, y: expensive() }; print(r.x)` is compiled and `r.y` is never accessed
- **THEN** the compiler SHALL produce an unused-record-field error for `y`

#### Scenario: Record passed to function — all fields used
- **WHEN** `r = { x: 1, y: expensive() }; process(r)` is compiled
- **THEN** the compiler SHALL NOT produce an unused-field error, because `r` escapes via the function call

#### Scenario: Record returned — all fields used
- **WHEN** `fn make() = { x: 1, y: 2 }` is compiled
- **THEN** the compiler SHALL NOT produce an unused-field error, because the record escapes via return

#### Scenario: Record used in perform — all fields used
- **WHEN** `r = { x: 1, y: 2 }; perform Op(r)` is compiled
- **THEN** the compiler SHALL NOT produce an unused-field error, because `r` escapes via perform

#### Scenario: Transitive escape through alias
- **WHEN** `r = { x: 1, y: 2 }; n = r; process(n)` is compiled and only `r.x` is accessed locally
- **THEN** the compiler SHALL NOT produce an unused-field error, because the alias `n` escapes

#### Scenario: Match is local access, not escape
- **WHEN** `r = { x: 1, y: 2, z: 3 }; match r { { x, y } => ... }` is compiled and `z` is never accessed
- **THEN** the compiler SHALL produce an unused-record-field error for `z` (match is local inspection)

#### Scenario: Discard does not count as field use
- **WHEN** `r = { x: 1, y: 2 }; _ = r.y; print(r.x)` is compiled
- **THEN** the compiler SHALL produce an unused-record-field error for `y` (discarding a pure field access does not count as using it)

### Requirement: Nested Record Field Checking
Record field unused checking SHALL be recursive. If an outer record escapes, all nested record literals within it SHALL also have their fields considered used (escape propagates inward).

#### Scenario: Unused nested field
- **WHEN** `r = { meta: { a: 1, b: 2 }, data: 3 }; print(r.meta.a); print(r.data)` is compiled and `meta.b` is never accessed
- **THEN** the compiler SHALL produce an unused-record-field error for `b`

#### Scenario: Outer escape propagates inward
- **WHEN** `r = { meta: { a: 1, b: 2 }, data: 3 }; process(r)` is compiled
- **THEN** the compiler SHALL NOT produce an error for any field, because `r` escapes

### Requirement: Record Spread Semantics for Unused Checking
In a record spread (`{ ...r, z: 3 }`), the source record `r` SHALL be exempt from field checking (spread transfers all fields). The result record's fields SHALL be checked individually.

#### Scenario: Spread source exempt
- **WHEN** `r = { x: 1, y: 2 }; r2 = { ...r, z: 3 }; print(r2.z)` is compiled and `r2.x`, `r2.y` are never accessed
- **THEN** the compiler SHALL NOT produce an error for `r` (source is exempt), but SHALL produce unused-field errors for `r2.x` and `r2.y`

### Requirement: Unreachable Code Skips Unused Checking
Unused binding analysis SHALL be skipped entirely in unreachable code. A separate error SHALL handle unreachable code detection.

#### Scenario: Binding after return
- **WHEN** `return 42; x = 5` is compiled and `x` is never referenced
- **THEN** the compiler SHALL NOT produce an unused-binding error for `x` (unreachable code is not checked for unused bindings)

### Requirement: Shadowing Error Priority
When both a shadowing error and an unused-binding error apply to the same binding, the shadowing error SHALL take priority. Only the shadowing error SHALL be reported.

#### Scenario: Shadowed unused binding
- **WHEN** `x = 1; x = 2` is compiled (shadowing is forbidden in Camp)
- **THEN** the compiler SHALL produce a shadowing error and SHALL NOT also produce an unused-binding error for the first `x`

### Requirement: Transitive Unused Detection
Unused binding errors SHALL be reported only for the immediately unused binding. If a binding `x` is used only by another binding `y`, and `y` is unused, only `y` SHALL be flagged. The programmer fixes iteratively.

#### Scenario: Chain of unused bindings
- **WHEN** `x = compute(); y = transform(x)` is compiled and `y` is never referenced
- **THEN** the compiler SHALL produce an unused-binding error only for `y`, not for `x`

### Requirement: Type Annotation No Exemption
A type annotation on a binding SHALL NOT exempt it from unused checking. An unused binding with a type annotation SHALL still produce an error.

#### Scenario: Unused binding with type annotation
- **WHEN** `x: ComplexType = expr` is compiled and `x` is never referenced
- **THEN** the compiler SHALL produce an unused-binding error

For the complete syntax reference, see `docs/syntax-recipe.md`.

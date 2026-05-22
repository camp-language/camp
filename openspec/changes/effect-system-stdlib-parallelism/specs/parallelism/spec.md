## MODIFIED Requirements

### Requirement: Parallel Effect for Data Parallelism

The `Parallel!` effect SHALL provide `map!`, `for_each!`, `filter!`, `reduce!`, `all!`, and `any!` operations that express data-parallel intent. The handler SHALL choose the execution strategy (sequential, thread pool, SIMD). All operations SHALL use effect-polymorphic row propagation for inner function effects.

#### Scenario: Parallel map preserves order

- Given `Parallel!.map!([1, 2, 3], |x| x * 2)` with any handler
- When the operation completes
- Then the result SHALL be `[2, 4, 6]` in input order regardless of execution order

#### Scenario: Parallel any returns first success

- Given `Parallel!.any!([|| Throw!.throw!(A), || 42, || Throw!.throw!(B)])`
- When the handler executes tasks
- Then the result SHALL be `42` and remaining tasks SHALL be cancelled

### Requirement: Parallel Effect Row Propagation

The `Parallel!` effect SHALL propagate inner function effects through its operations into the caller's effect row using effect polymorphism.

#### Scenario: Pure parallel map

- Given `Parallel!.map!(items, |x| x + 1)` where the function is pure
- Then the effect row SHALL be `-[Parallel!]->` only

#### Scenario: Effectful parallel map

- Given `Parallel!.map!(items, |x| Throw!.throw!(x))` where the function throws
- Then the effect row SHALL be `-[Parallel! | Throw!(e)]->`

### Requirement: Parallel Method Sugar

`List(a)` SHALL provide `par_map!`, `par_filter!`, `par_reduce!`, and `par_for_each!` methods that desugar to `Parallel!` effect operations at canonicalization.

#### Scenario: Method sugar desugars correctly

- Given `records.par_map!(|r| process!(r))`
- When canonicalization runs
- Then it SHALL be equivalent to `Parallel!.map!(records, |r| process!(r))` with `Parallel!` in the effect row

### Requirement: par Block Syntax

The `par { e1, e2, e3 }` block SHALL desugar to `Parallel!.all!([|| e1, || e2, || e3])` and return a tuple of each expression's result type. The `par for x in xs { body }` block SHALL desugar to `Parallel!.for_each!(xs, |x| body)`.

#### Scenario: par block returns typed tuple

- Given `par { compute_alpha!(), compute_beta!() }` where alpha returns `Int` and beta returns `Str`
- When the block executes
- Then the result type SHALL be `(Int, Str)` — a tuple preserving each expression's type

### Requirement: Spawn Effect for Task Parallelism

The `Spawn!` effect SHALL provide `spawn!`, `join!`, and `cancel!` operations for running independent computations on separate execution contexts (OS threads, WASM instances, WASM agents).

#### Scenario: Spawn and join

- Given `h = Spawn!.spawn!(|| fibonacci(40))`
- When `Spawn!.join!(h)` is called
- Then the result SHALL be the return value of `fibonacci(40)`

#### Scenario: Spawn join re-throws errors

- Given `h = Spawn!.spawn!(|| Throw!.throw!(ParseError))`
- When `Spawn!.join!(h)` is called
- Then `Throw!(ParseError)` SHALL be propagated in the caller's context

### Requirement: Async Effect for I/O Concurrency

The `Async!` effect SHALL provide cooperative I/O concurrency via a single-threaded event loop integrated with `wasi:io/poll`. Operations include `yield!`, `spawn!`, `join!`, and `cancel!`.

#### Scenario: Concurrent file reads

- Given 100 files read concurrently via `Async!.spawn!`/`Async!.join!`
- When I/O operations overlap via `wasi:io/poll`
- Then total time SHALL be bounded by the slowest file, not the sum of all files

### Requirement: Graceful Degradation

The runtime SHALL detect available parallelism capabilities and fall back gracefully: WASM threads → multi-instance → sequential. The user's code SHALL remain the same regardless of strategy.

#### Scenario: Fallback to sequential

- Given a single-threaded WASM runtime without multi-instance support
- When a program uses `Parallel!` or `Spawn!` effects
- Then the sequential handler SHALL execute correctly — `Parallel!.map!` runs one element at a time, `Spawn!.spawn!` runs the thunk immediately

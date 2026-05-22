# Domain Specification: Parallelism

## Purpose

Provide Camp with three complementary concurrency/parallelism mechanisms — `Async!` for I/O concurrency, `Parallel!` for data parallelism, and `Spawn!` for task parallelism — all expressed as algebraic effects (type aliases with `!` names) with handler-selected execution strategies, ensuring programs are correct and portable regardless of runtime capabilities.

## Requirements

### Requirement: Parallel Effect for Data Parallelism

The `Parallel!` effect SHALL provide `map!`, `for_each!`, `filter!`, `reduce!`, `all!`, and `any!` operations that express data-parallel intent. The handler SHALL choose the execution strategy (sequential, thread pool, SIMD).

#### Scenario: Parallel map preserves order

- Given `Parallel!.map!([1, 2, 3], |x| x * 2)` with any handler
- When the operation completes
- Then the result SHALL be `[2, 4, 6]` in input order regardless of execution order

#### Scenario: Parallel filter preserves order

- Given `Parallel!.filter!([1, 2, 3, 4], |x| x > 2)` with any handler
- When the operation completes
- Then the result SHALL be `[3, 4]` preserving input order

#### Scenario: Parallel reduce requires associativity

- Given `Parallel!.reduce!([1, 2, 3, 4], 0, |a, b| a + b)` with a parallel handler
- When the handler splits work into chunks
- Then the result SHALL equal sequential left-fold ONLY if the function is associative

#### Scenario: Parallel any returns first success

- Given `Parallel!.any!([|| Throw!.throw!(A), || 42, || Throw!.throw!(B)])`
- When the handler executes tasks
- Then the result SHALL be `42` and remaining tasks SHALL be cancelled

#### Scenario: Parallel all returns all results in order

- Given `Parallel!.all!([|| compute_a(), || compute_b()])`
- When both computations complete
- Then results SHALL be returned in input order as a `List`

### Requirement: Parallel Effect Row Propagation

The `Parallel!` effect SHALL propagate inner function effects through its operations into the caller's effect row.

#### Scenario: Pure parallel map

- Given `Parallel!.map!(items, |x| x + 1)` where the function is pure
- Then the effect row SHALL be `-[Parallel!]->` only

#### Scenario: Effectful parallel map

- Given `Parallel!.map!(items, |x| Throw!.throw!(x))` where the function throws
- Then the effect row SHALL be `-[Parallel! | Throw!(e)]->`

#### Scenario: Async-effectful parallel map

- Given `Parallel!.map!(urls, |url| Http!.get!(url))` where the function does async I/O
- Then the effect row SHALL be `-[Parallel! | Async! | Http! | Throw!(HttpError)]->`

### Requirement: Parallel Method Sugar

`List(a)` SHALL provide `par_map!`, `par_filter!`, `par_reduce!`, and `par_for_each!` methods that desugar to `Parallel!` effect operations at canonicalization.

#### Scenario: Method sugar desugars correctly

- Given `records.par_map!(|r| process!(r))`
- When canonicalization runs
- Then it SHALL be equivalent to `Parallel!.map!(records, |r| process!(r))` with `Parallel!` in the effect row

#### Scenario: Method chaining

- Given `records.par_map!(|r| process!(r)).par_filter!(|r| r.is_valid())`
- When executed
- Then each method SHALL desugar to a `Parallel!` operation and the effect row SHALL accumulate `Parallel!`

### Requirement: par Block Syntax

The `par { e1, e2, e3 }` block SHALL desugar to `Parallel!.all!([|| e1, || e2, || e3])` and return a tuple of each expression's result type. The `par for x in xs { body }` block SHALL desugar to `Parallel!.for_each!(xs, |x| body)`.

#### Scenario: par block returns typed tuple

- Given `par { compute_alpha!(), compute_beta!() }` where alpha returns `Int` and beta returns `Str`
- When the block executes
- Then the result type SHALL be `(Int, Str)` — a tuple preserving each expression's type

#### Scenario: par for desugars to for_each

- Given `par for r in records { process_record!(r) }`
- When canonicalization runs
- Then it SHALL be equivalent to `Parallel!.for_each!(records, |r| process_record!(r))`

### Requirement: for_each! Side Effect Order Not Guaranteed

`Parallel!.for_each!` SHALL NOT guarantee side effect ordering across parallel handlers.

#### Scenario: Unordered side effects with thread-pool handler

- Given `items.par_for_each!(|x| Console!.println!(x))` with a thread-pool handler
- When the handler runs items in parallel
- Then the order of printed lines SHALL NOT be guaranteed to match input order

### Requirement: reduce! Short-Circuit on Error

If `f` throws in `Parallel!.map!`, the entire operation SHALL short-circuit and propagate the first error.

#### Scenario: Error in parallel map

- Given `Parallel!.map!(items, |x| parse_int!(x))` where one item fails parsing
- When the handler encounters the first `Throw!`
- Then the handler SHALL propagate the error and MAY cancel remaining work

### Requirement: Spawn Effect for Task Parallelism

The `Spawn!` effect SHALL provide `spawn!`, `join!`, and `cancel!` operations for running independent computations on separate execution contexts (OS threads, WASM instances, WASM agents).

#### Scenario: Spawn and join

- Given `h = Spawn!.spawn!(|| fibonacci(40))`
- When `Spawn!.join!(h)` is called
- Then the result SHALL be the return value of `fibonacci(40)`

#### Scenario: Spawn join re-throws errors

- Given `h = Spawn!.spawn!(|| throw!(ParseError))`
- When `Spawn!.join!(h)` is called
- Then `Throw!(ParseError)` SHALL be propagated in the caller's context

#### Scenario: Spawn cancel

- Given `h = Spawn!.spawn!(|| long_computation())`
- When `Spawn!.cancel!(h)` is called
- Then the computation SHALL be signaled to stop (best-effort)

### Requirement: Spawn Is Non-Blocking

`Spawn!.spawn!(thunk)` SHALL return immediately with a `Handle(a)`. The thunk SHALL start executing in the background. The caller continues without waiting.

#### Scenario: Spawn returns immediately

- Given `h = Spawn!.spawn!(|| heavy_work!())`
- When the spawn! operation completes
- Then `h` SHALL be a `Handle(a)` and the caller SHALL continue immediately

### Requirement: Handle Is One-Shot and Opaque

A `Handle(a)` SHALL be consumed by exactly one `join!` or `cancel!`. Double-join SHALL be a runtime error. The handle SHALL be opaque — users cannot inspect its internals.

#### Scenario: Double join is an error

- Given `h = Spawn!.spawn!(|| 42)` followed by `Spawn!.join!(h)` then `Spawn!.join!(h)`
- When the second `join!` is called
- Then it SHALL produce a runtime error

### Requirement: Structured Concurrency for Spawn

Every `Spawn!.spawn!` SHALL be followed by exactly one `Spawn!.join!` or `Spawn!.cancel!` before the enclosing handler exits. Unjoined spawns SHALL produce a compiler warning and the handler SHALL automatically cancel outstanding handles on exit.

#### Scenario: Unjoined spawn warning

- Given a `Spawn!` handler block that creates a handle without joining or cancelling
- When the handler block exits
- Then the compiler SHALL emit a warning and the handler SHALL cancel the outstanding handle

### Requirement: Spawn join! Propagates Thunk Effects

`Spawn!.join!` SHALL propagate the spawned thunk's effects into the caller's effect row.

#### Scenario: Thunk effects appear in caller's row

- Given `h = Spawn!.spawn!(|| -[Throw(ParseError)]-> Int { parse_int!(input) })`
- When `Spawn!.join!(h)` is called
- Then the effect row SHALL include `Spawn!` and `Throw!(ParseError)`

### Requirement: Async Effect for I/O Concurrency

The `Async!` effect SHALL provide cooperative I/O concurrency via a single-threaded event loop integrated with `wasi:io/poll`. Operations include `yield!`, `spawn!`, `join!`, and `cancel!`.

#### Scenario: Concurrent file reads

- Given 100 files read concurrently via `Async!.spawn!`/`Async!.join!`
- When I/O operations overlap via `wasi:io/poll`
- Then total time SHALL be bounded by the slowest file, not the sum of all files

### Requirement: Async Is Single-Threaded

The `Async!` runtime SHALL run all coroutines on one WASM thread. It SHALL NOT use multi-threaded async.

#### Scenario: No cross-thread synchronization needed

- Given the `Async!` runtime uses cooperative coroutines on one thread
- Then no mutexes, atomics, or cross-thread channels SHALL be required for async scheduling

### Requirement: WASI I/O Poll Bridge

The `Async!` runtime SHALL use `wasi:io/poll` for readiness-based I/O polling. When coroutines block on I/O, the runtime SHALL subscribe to the relevant WASI pollable, call `poll-list`, and resume coroutines when their I/O is ready.

#### Scenario: File read with poll bridge

- Given a coroutine calls `File!.read!(handle)`
- When the WASI stream returns a short read (would-block)
- Then the runtime SHALL call `handle.subscribe()` to get a pollable, add the coroutine to the blocked map, and resume it when the pollable is ready

### Requirement: Structured Concurrency for Async

Every `Async!.spawn!` SHALL be followed by `Async!.join!` or `Async!.cancel!` before the `Async!` handler exits. The handler SHALL cancel outstanding handles on exit.

#### Scenario: Handler cleanup on exit

- Given an `Async!` handler with an unjoined spawned task
- When the handler block exits
- Then the handler SHALL cancel the outstanding handle automatically

### Requirement: Sleep via Poll Timeout

`Time.sleep!(ms)` SHALL be implemented via `wasi:io/poll-list` with a timeout, not via a separate timer mechanism.

#### Scenario: Sleep during concurrent I/O

- Given `Time.sleep!(1000)` while other coroutines are blocked on I/O
- When the poll-list call returns
- Then the sleep coroutine SHALL resume after 1000ms even if I/O becomes ready earlier

### Requirement: Multi-Instance Parallelism Fallback

When WASM threads are not available, the runtime SHALL support multi-instance parallelism (N WASM stores on N OS threads) with closure serialization across instance boundaries.

#### Scenario: Parallel execution via multi-instance

- Given a wasmtime runtime without WASM threads support
- When `--threads=4` is specified
- Then the runtime SHALL create 4 WASM stores on 4 OS threads and distribute work via a thread-safe queue

### Requirement: WASM Threads Optimization

When WASM threads are available, the runtime SHALL use in-process parallelism with SharedArrayBuffer and atomic operations, eliminating closure serialization overhead.

#### Scenario: In-process parallel execution

- Given a WASM runtime with WASM threads support
- When `--threads=4` is specified
- Then the runtime SHALL use a single WASM module with shared memory, atomic work queue, and per-thread heap regions

### Requirement: Graceful Degradation

The runtime SHALL detect available parallelism capabilities and fall back gracefully: WASM threads → multi-instance → sequential. The user's code SHALL remain the same regardless of strategy.

#### Scenario: Fallback to sequential

- Given a single-threaded WASM runtime without multi-instance support
- When a program uses `Parallel!` or `Spawn!` effects
- Then the sequential handler SHALL execute correctly — `Parallel!.map!` runs one element at a time, `Spawn!.spawn!` runs the thunk immediately

#### Scenario: Runtime detection

- Given the Camp runtime starts
- When it attempts to create a shared `Memory` object
- Then if successful, it SHALL use WASM threads; if not, it SHALL try multi-instance; if that fails, it SHALL use sequential

### Requirement: Thread Count Configuration

The number of threads SHALL be configurable via `--threads=N` CLI flag (highest priority), `CAMP_THREADS` environment variable (medium), or `num_cpus()` runtime detection (lowest/default).

#### Scenario: CLI flag overrides env var

- Given `--threads=4` is specified and `CAMP_THREADS=8` is set
- When the runtime initializes
- Then it SHALL use 4 threads

### Requirement: No Shared Mutable State Enforced

The typechecker SHALL enforce that functions passed to `Parallel!` operations cannot capture `$`-prefixed mutable bindings from enclosing scopes. This SHALL fall out from Camp's existing stack-local mutation rules — no new enforcement needed.

#### Scenario: Mutable capture across parallel boundary

- Given `$counter = 0` in an enclosing scope and `items.par_map!(|x| { $counter = $counter + 1; x })`
- When the typechecker processes the closure
- Then it SHALL produce an error because `$counter` is captured across a parallel boundary

## MODIFIED Requirements

### Requirement: Async Effect for I/O Concurrency

The `Async!` effect SHALL provide cooperative I/O concurrency via a multithreaded work-stealing scheduler integrated with `wasi:io/poll`. Operations include `yield!`, `spawn!`, `join!`, and `cancel!`. `Async!` tasks MAY run on any worker in the scheduler pool.

#### Scenario: Concurrent file reads

- **GIVEN** 100 files read concurrently via `Async!.spawn!`/`Async!.join!`
- **WHEN** I/O operations overlap via `wasi:io/poll`
- **THEN** total time SHALL be bounded by the slowest file, not the sum of all files

#### Scenario: Async task runs on any worker

- **GIVEN** a scheduler with 4 workers
- **WHEN** `Async!.spawn!(thunk)` is called
- **THEN** the thunk MAY be executed on any of the 4 workers, not necessarily the spawning worker

### Requirement: Async Is Single-Threaded

~~The `Async!` runtime SHALL run all coroutines on one WASM thread. It SHALL NOT use multi-threaded async.~~

**REMOVED** — `Async!` now uses the multithreaded work-stealing scheduler. See `async-scheduler` capability for the new requirement.

### Requirement: WASI I/O Poll Bridge

The `Async!` runtime SHALL use `wasi:io/poll` for readiness-based I/O polling via a centralized I/O driver on Worker 0. When coroutines block on I/O, the runtime SHALL subscribe to the relevant WASI pollable, register it in a shared wait map, and resume coroutines when their I/O is ready. The I/O driver SHALL batch all pending pollables into a single `wasi:io/poll.poll-list` call.

#### Scenario: File read with poll bridge

- **GIVEN** a coroutine calls `File!.read!(handle)`
- **WHEN** the WASI stream returns a short read (would-block)
- **THEN** the runtime SHALL call `handle.subscribe()` to get a pollable, add the coroutine to the shared wait map, and resume it when the pollable is ready

#### Scenario: I/O driver batches multiple pollables

- **GIVEN** 50 coroutines are blocked on 50 different I/O pollables
- **WHEN** Worker 0 runs the I/O driver
- **THEN** Worker 0 SHALL submit all 50 pollables in a single `poll-list` call

### Requirement: Structured Concurrency for Async

Every `Async!.spawn!` SHALL be followed by `Async!.join!` or `Async!.cancel!` before the `Async!` handler exits. The handler SHALL cancel outstanding handles on exit. Cancellation SHALL be guaranteed delivery, not best-effort — a cancelled task SHALL observe cancellation within one cooperative budget cycle (128 effect operations).

#### Scenario: Handler cleanup on exit

- **GIVEN** an `Async!` handler with an unjoined spawned task
- **WHEN** the handler block exits
- **THEN** the handler SHALL cancel the outstanding handle automatically and the cancelled task SHALL observe cancellation at its next `perform` or `yield!` site

### Requirement: Sleep via Poll Timeout

~~`Time.sleep!(ms)` SHALL be implemented via `wasi:io/poll-list` with a timeout, not via a separate timer mechanism.~~

**MODIFIED** — `Time.sleep!(ms)` SHALL be implemented via a hierarchical timer wheel. The timer wheel's next expiry SHALL determine the timeout for `wasi:io/poll.poll-list`. Each sleep inserts a timer into the wheel; no per-sleep WASI pollable is created.

#### Scenario: Sleep during concurrent I/O

- **GIVEN** `Time.sleep!(1000)` while other coroutines are blocked on I/O
- **WHEN** the timer wheel's next expiry is 1000 ms and the `poll-list` call returns before 1000 ms (I/O ready)
- **THEN** the sleep timer SHALL NOT fire until 1000 ms have elapsed; the next `poll-list` call SHALL use the remaining sleep time as its timeout

#### Scenario: Timer wheel cancellation on task cancel

- **GIVEN** a sleeping task that is cancelled before its timer expires
- **WHEN** the cancellation handler runs
- **THEN** the timer SHALL be removed from the timer wheel in O(1) and the task SHALL NOT be woken at the original expiry time

## ADDED Requirements

### Requirement: Handle Type Carries Effect Row

The `Handle` type SHALL be parameterized by both the result type and the spawned thunk's effect row: `Handle(a, e)`. When `join!` is called, the effect row `e` SHALL propagate into the caller's effect row via row composition.

#### Scenario: Handle carries throw effect

- **GIVEN** `h = Spawn!.spawn!(|| -[Throw!(ParseError)]-> Int { parse!(input) })`
- **WHEN** the typechecker infers the type of `h`
- **THEN** `h` SHALL have type `Handle(Int, Throw!([ParseError]))`

#### Scenario: Join propagates effect row

- **GIVEN** `Spawn!.join!(h)` where `h : Handle(Int, Throw!([ParseError]))`
- **WHEN** the typechecker processes the `join!` call
- **THEN** the caller's effect row SHALL include `Spawn! | Throw!([ParseError])`

### Requirement: Cancellation Is Guaranteed Delivery

`cancel!` SHALL set an atomic cancellation flag in the task header. Every effect `perform` site and `yield!` call SHALL check this flag. If the flag is set, the task SHALL exit with a `Cancelled` result within one budget cycle. This replaces the previous "best-effort" semantics.

#### Scenario: Cancelled task stops producing side effects

- **GIVEN** a task that calls `Console!.println!` in a loop and is cancelled
- **WHEN** the task observes the cancellation flag at its next `perform` site
- **THEN** the task SHALL exit immediately without performing further `println!` operations

#### Scenario: Cancelled Spawn task releases resources

- **GIVEN** a spawned task holding a file handle that is cancelled
- **WHEN** the task observes cancellation
- **THEN** the task SHALL exit and its Perceus reference counting SHALL deallocate the file handle

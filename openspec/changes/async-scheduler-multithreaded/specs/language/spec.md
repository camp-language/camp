## ADDED Requirements

### Requirement: Handle Type Parameterized by Effect Row

The `Handle` type SHALL accept two type parameters: `Handle(a, e)` where `a` is the result type and `e` is the spawned thunk's effect row. A `Handle(a, e)` value SHALL be consumed by exactly one `join!` or `cancel!` call. The `e` parameter SHALL propagate through `join!` into the caller's effect row.

#### Scenario: Handle type inference

- **GIVEN** `h = Async!.spawn!(|| -[Console!]-> Int { Console!.println!("hi"); 42 })`
- **WHEN** the typechecker infers the type of `h`
- **THEN** `h` SHALL have type `Handle(Int, Console!)`

#### Scenario: Handle consumption by join

- **GIVEN** `h : Handle(Int, Console!)` and the code `x = Async!.join!(h); y = Async!.join!(h)`
- **WHEN** the typechecker processes the second `join!`
- **THEN** the typechecker SHALL emit an error because the handle has already been consumed

### Requirement: Cooperative Budget at Yield and Perform Points

Every effect `perform` site and `Async!.yield!` call SHALL decrement the current task's cooperative budget. When the budget reaches zero, the task SHALL be re-enqueued at the tail of the local queue with a fresh budget of 128. This guarantees that no task can execute more than 128 effect operations without yielding to the scheduler.

#### Scenario: Budget exhaustion at perform site

- **GIVEN** a task that has performed 127 effect operations since its last resume
- **WHEN** the task performs its 128th effect operation (any `perform`)
- **THEN** the budget SHALL reach zero, the task SHALL be re-enqueued, and the scheduler SHALL select the next task

#### Scenario: Explicit yield always yields

- **GIVEN** a task calls `Async!.yield!()`
- **WHEN** the yield operation is executed
- **THEN** the task SHALL always yield to the scheduler (be re-enqueued), regardless of remaining budget

### Requirement: Cancellation Flag Check at Perform Sites

Every effect `perform` site SHALL check the current task's atomic cancellation flag before executing the effect. If the flag is set, the task SHALL exit with a `Cancelled` result immediately, without executing the effect operation.

#### Scenario: Cancellation observed before perform

- **GIVEN** a task whose cancellation flag has been set by another worker
- **WHEN** the task reaches its next `perform` site
- **THEN** the task SHALL observe the flag and exit immediately without executing the performed effect

#### Scenario: No cancellation flag overhead on normal path

- **GIVEN** a task whose cancellation flag is not set
- **WHEN** the task reaches a `perform` site
- **THEN** the cancellation check SHALL add at most one atomic load instruction to the normal execution path

### Requirement: Structured Concurrency — Unjoined Spawn Warning

The compiler SHALL emit a warning when a `Handle(a, e)` value produced by `spawn!` is not consumed by `join!` or `cancel!` on all control flow paths within the enclosing `Async!` or `Spawn!` handler scope. This warning indicates a potential resource leak.

#### Scenario: Warning for discarded handle

- **GIVEN** `Async!.spawn!(|| work!())` where the resulting handle is not bound to a variable
- **WHEN** the typechecker processes the handler scope exit
- **THEN** the compiler SHALL emit a warning: "spawned handle not consumed — consider joining or cancelling"

#### Scenario: No warning for bound and joined handle

- **GIVEN** `h = Async!.spawn!(|| work!()); result = Async!.join!(h)`
- **WHEN** the typechecker processes the handler scope exit
- **THEN** the compiler SHALL NOT emit a warning

#### Scenario: Warning for handle joined on some paths but not others

- **GIVEN** code that joins a handle in the `then` branch but not the `else` branch
- **WHEN** the typechecker analyzes the control flow
- **THEN** the compiler SHALL emit a warning: "handle may leak on some control flow paths"

### Requirement: Multi-Threaded Execution Mode

When `--threads=N` (N > 1) is specified and WASM threads are available, the generated WASM module SHALL use shared memory with atomics. The `_start` function SHALL initialize the scheduler with N workers. Worker 0 SHALL run the main scheduler loop. Additional workers SHALL be started via the `camp_worker_entry` export, which the host SHALL call from N-1 additional OS threads.

#### Scenario: Multi-worker initialization

- **GIVEN** `--threads=4` and WASM threads support
- **WHEN** the WASM module starts
- **THEN** Worker 0 SHALL run `_start` (which initializes the scheduler and enters the worker loop), and the host SHALL call `camp_worker_entry(worker_id=1)`, `camp_worker_entry(worker_id=2)`, `camp_worker_entry(worker_id=3)` from 3 additional OS threads

#### Scenario: Single-worker fallback

- **GIVEN** `--threads=1`
- **WHEN** the WASM module starts
- **THEN** Worker 0 SHALL run the entire scheduler (no `camp_worker_entry` calls)

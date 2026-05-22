## ADDED Requirements

### Requirement: Work-Stealing Scheduler Core

The scheduler SHALL consist of N worker agents (OS threads / WASM agents), each with a local run queue (fixed-capacity ring buffer), a LIFO slot (atomic single-task slot), and access to a shared global inject queue. Workers SHALL execute tasks from their LIFO slot first, then local queue, then global queue (every 61 ticks for fairness), then steal from other workers, then park.

#### Scenario: Worker processes LIFO slot before local queue

- **GIVEN** a worker with a task in its LIFO slot and tasks in its local queue
- **WHEN** the worker searches for the next task
- **THEN** the worker SHALL execute the LIFO slot task first

#### Scenario: Global queue checked every 61 ticks

- **GIVEN** a worker that has processed 60 consecutive tasks from its local queue
- **WHEN** the worker searches for the next task on the 61st tick
- **THEN** the worker SHALL check the global inject queue before checking its local queue

#### Scenario: Worker parks when no work available

- **GIVEN** a worker with an empty LIFO slot, empty local queue, empty global queue, and no stealable work
- **WHEN** the worker completes its search
- **THEN** the worker SHALL park via `memory.atomic.wait32` until notified

### Requirement: Work-Stealing with Steal-Half

When a worker has no local work, it SHALL attempt to steal half of the tasks from a randomly chosen victim worker's local queue. The stolen tasks SHALL be transferred to the stealing worker's local queue, with the first stolen task returned for immediate execution.

#### Scenario: Steal half from victim with tasks

- **GIVEN** Worker A has an empty local queue and Worker B has 10 tasks in its local queue
- **WHEN** Worker A attempts to steal from Worker B
- **THEN** Worker A SHALL transfer 5 tasks to its local queue and execute 1 task immediately, leaving Worker B with 5 tasks

#### Scenario: Steal from empty victim falls through

- **GIVEN** Worker A has an empty local queue and Worker B has an empty local queue
- **WHEN** Worker A attempts to steal from Worker B
- **THEN** the steal SHALL return no task and Worker A SHALL proceed to the next search step

### Requirement: Stealable LIFO Slot

The LIFO slot SHALL be implemented as an atomic swappable cell. Any worker SHALL be able to steal the task from another worker's LIFO slot. When a worker places a task in its own LIFO slot, the task SHALL be available for stealing by other workers.

#### Scenario: LIFO slot task stolen by another worker

- **GIVEN** Worker A has placed a task in its LIFO slot and Worker B is searching for work
- **WHEN** Worker B attempts to steal from Worker A's LIFO slot
- **THEN** Worker B SHALL atomically swap the LIFO slot to empty and receive the task

#### Scenario: LIFO slot bypass for fairness

- **GIVEN** a worker with tasks in both its LIFO slot and local queue
- **WHEN** the worker's tick counter reaches a multiple of 61
- **THEN** the worker SHALL bypass the LIFO slot and pop from the local queue instead

### Requirement: Spinning Thread Protocol

The scheduler SHALL track the number of "spinning" workers (workers actively searching for work). A new worker SHALL only be unparked when there is idle capacity AND no workers are currently spinning. When the last spinning worker finds work, it SHALL unpark an additional worker to maintain at least one spinner.

#### Scenario: No unnecessary unpark when spinner exists

- **GIVEN** 1 worker is spinning and 2 workers are parked
- **WHEN** a new task is submitted to the global queue
- **THEN** the scheduler SHALL NOT unpark an additional worker because a spinner already exists

#### Scenario: Unpark when no spinner exists

- **GIVEN** 0 workers are spinning and 2 workers are parked
- **WHEN** a new task is submitted to the global queue
- **THEN** the scheduler SHALL unpark one worker and mark it as spinning

### Requirement: Thread Parking via WASM Atomics

Workers SHALL park using `memory.atomic.wait32` on a shared notification address with an epoch-based lost-wakeup prevention protocol. Workers SHALL be unparked using `memory.atomic.notify`.

#### Scenario: Park with lost-wakeup prevention

- **GIVEN** a worker is about to park and the notification epoch is 5
- **WHEN** the worker loads the epoch, checks for work (none found), and calls `wait32`
- **THEN** if another worker incremented the epoch to 6 between the load and the wait, the `wait32` SHALL return immediately (epoch mismatch)

#### Scenario: Notify one worker

- **GIVEN** 3 workers are parked on the notification address
- **WHEN** a task is submitted and `notify` is called with count=1
- **THEN** exactly 1 worker SHALL be woken

### Requirement: Handle Table with Atomic Status Transitions

The scheduler SHALL maintain a shared handle table where each entry has an atomic status field transitioning through: Pending → Completed → Joined, or Pending → Cancelled → Joined. Status transitions SHALL use atomic compare-and-swap to serialize concurrent operations.

#### Scenario: Concurrent complete and cancel

- **GIVEN** a handle in Pending status
- **WHEN** the completing worker and the cancelling worker both attempt status transitions simultaneously
- **THEN** exactly one CAS SHALL succeed; the other SHALL observe the updated status and handle accordingly

#### Scenario: Double join is a runtime error

- **GIVEN** a handle that has already transitioned to Joined status
- **WHEN** a second `join!` is called on the same handle
- **THEN** the runtime SHALL produce a runtime error (trap)

### Requirement: Guaranteed Cancellation Delivery

`cancel!` SHALL set an atomic cancellation flag in the task header. Every effect `perform` site and `yield!` call SHALL check this flag. If the flag is set, the task SHALL exit with a `Cancelled` result within the current budget cycle. The worst-case latency before a cancelled task observes cancellation SHALL be bounded by the cooperative budget (128 operations).

#### Scenario: Cancelled task observes cancellation at perform site

- **GIVEN** a task is running and its cancellation flag is set by another worker
- **WHEN** the task reaches its next `perform` site
- **THEN** the task SHALL observe the cancellation flag and exit with a `Cancelled` result immediately

#### Scenario: Cancellation delivered within budget cycle

- **GIVEN** a cancelled task that is currently executing between two `perform` sites
- **WHEN** the task performs up to 128 more operations
- **THEN** the task SHALL reach the next `perform` or `yield!` site and observe cancellation

### Requirement: Cooperative Budget System

Each task SHALL be assigned a budget of 128 operations per scheduler quantum. The budget SHALL decrement at every effect `perform` and `yield!` site. When the budget reaches zero, the task SHALL be re-enqueued at the tail of the local queue with a fresh budget. No task SHALL execute more than 128 effect operations without yielding.

#### Scenario: Budget exhaustion triggers yield

- **GIVEN** a task that has performed 127 effect operations since its last resume
- **WHEN** the task performs its 128th effect operation
- **THEN** the budget SHALL reach zero and the task SHALL be re-enqueued at the tail of the local queue

#### Scenario: Budget reset on resume

- **GIVEN** a task that was re-enqueued due to budget exhaustion
- **WHEN** the scheduler resumes the task
- **THEN** the task's budget SHALL be reset to 128

### Requirement: Hierarchical Timer Wheel

The scheduler SHALL maintain a single shared hierarchical timer wheel with 4 levels (64 slots each). Timer insertion and cancellation SHALL be O(1). The timer wheel's next expiry SHALL determine the timeout for `wasi:io/poll.poll-list`. Worker 0 SHALL advance the timer wheel after each poll cycle.

#### Scenario: Sleep via timer wheel

- **GIVEN** a task calls `Time.sleep!(1000)` (1000 ms)
- **WHEN** the scheduler inserts the timer
- **THEN** the task SHALL be suspended and the timer wheel's next expiry SHALL be at most 1000 ms from now

#### Scenario: Timer expiry wakes task

- **GIVEN** a timer expires in the timer wheel
- **WHEN** Worker 0 advances the wheel
- **THEN** the associated task SHALL be moved to the appropriate worker's local queue and that worker SHALL be notified

#### Scenario: Timer cancellation

- **GIVEN** a timer has been inserted for `Time.sleep!(5000)` and the task is cancelled before 5000 ms
- **WHEN** the cancellation handler removes the timer
- **THEN** the timer SHALL be removed from the wheel in O(1) and the task SHALL NOT be woken at the 5000 ms mark

### Requirement: WASI I/O Poll Bridge

Worker 0 SHALL drive I/O polling. When any task blocks on I/O, the I/O registration (WASI pollable + task) SHALL be placed in a shared wait map. Worker 0 SHALL batch all pending pollables into a single `wasi:io/poll.poll-list` call with the timer wheel timeout. On completion, tasks SHALL be dispatched to the originating worker's local queue.

#### Scenario: Concurrent file reads

- **GIVEN** 100 tasks each read a different file concurrently via `Async!.spawn!` / `Async!.join!`
- **WHEN** the I/O operations overlap via `wasi:io/poll`
- **THEN** total time SHALL be bounded by the slowest file, not the sum of all files

#### Scenario: I/O completion dispatched with affinity

- **GIVEN** a task on Worker 3 blocked on I/O and Worker 0's poll cycle detects its pollable is ready
- **WHEN** Worker 0 dispatches the completion
- **THEN** the task SHALL be enqueued on Worker 3's local queue (affinity) and Worker 3 SHALL be notified

#### Scenario: Short read with retry

- **GIVEN** a task calls `File!.read!(handle)` and `wasi:io/input-stream.read` returns a short read
- **WHEN** the runtime detects the incomplete read
- **THEN** the runtime SHALL buffer the partial result, call `handle.subscribe()` to get a pollable, register it in the wait map, and suspend the task until the pollable is ready, then retry the read

### Requirement: Zero-Duration Poll Safety

When the timer wheel has a zero-duration timer (e.g., `Time.sleep!(0)` or `Async!.yield!()`), the scheduler SHALL NOT call `wasi:io/poll.poll-list` with timeout=0. Instead, the timer task SHALL be enqueued immediately and the scheduler SHALL yield to the host before the next iteration.

#### Scenario: Zero-duration sleep does not starve host

- **GIVEN** a task calls `Time.sleep!(0)` in a tight loop
- **WHEN** the scheduler processes the zero-duration timer
- **THEN** the scheduler SHALL enqueue the task immediately without calling `poll-list` with timeout=0

### Requirement: Error Propagation Through Join

When a spawned task throws, the error SHALL be caught at the spawn boundary and stored in the handle's result slot with a tag distinguishing "normal result" from "thrown error". When `join!` is called on a handle with a thrown error, `join!` SHALL re-throw the error via `Throw!.throw!` in the caller's context.

#### Scenario: Spawned task throws, join re-throws

- **GIVEN** a task spawned with `Spawn!.spawn!(|| Throw!.throw!(NotFound))` producing `Handle(a, Throw!([NotFound]))`
- **WHEN** `Spawn!.join!(handle)` is called
- **THEN** `Throw!.throw!(NotFound)` SHALL be performed in the caller's context and the caller's effect row SHALL include `Throw!([NotFound])`

#### Scenario: Error propagation type-checked

- **GIVEN** a function that calls `Spawn!.join!(handle)` where `handle` has type `Handle(Int, Throw!([ParseError]))`
- **WHEN** the typechecker processes the `join!` call
- **THEN** the function's effect row SHALL include `Throw!([ParseError])` and the compiler SHALL emit an error if the caller does not handle `Throw!`

### Requirement: Structured Concurrency — Handler Exit Cleanup

When an `Async!` or `Spawn!` handler scope exits, the runtime SHALL iterate the handle table and cancel all handles still in `Pending` status that were created within the exiting handler's scope. This guarantees no resource leaks from unjoined spawns.

#### Scenario: Unjoined spawn auto-cancelled on handler exit

- **GIVEN** an `Async!` handler that spawned a task but did not call `join!` or `cancel!`
- **WHEN** the handler scope exits
- **THEN** the runtime SHALL cancel the outstanding handle automatically

#### Scenario: Joined handle not cancelled on handler exit

- **GIVEN** an `Async!` handler that spawned a task and called `join!`
- **WHEN** the handler scope exits
- **THEN** the runtime SHALL NOT attempt to cancel the already-joined handle

### Requirement: Structured Concurrency — Compiler Warning

The compiler SHALL emit a warning when a `spawn!` result (a `Handle(a, e)` value) is not consumed by `join!` or `cancel!` on all control flow paths within the handler scope. This warning SHALL be promoted to an error in a future version.

#### Scenario: Warning for unjoined spawn

- **GIVEN** a handler that calls `h = Async!.spawn!(thunk)` but never calls `Async!.join!(h)` or `Async!.cancel!(h)`
- **WHEN** the typechecker processes the handler scope exit
- **THEN** the compiler SHALL emit a warning: "handle may leak — consider joining or cancelling"

#### Scenario: No warning for properly joined spawn

- **GIVEN** a handler that calls `h = Async!.spawn!(thunk)` and then `Async!.join!(h)`
- **WHEN** the typechecker processes the handler scope exit
- **THEN** the compiler SHALL NOT emit a warning

### Requirement: Per-Agent Heap Regions

Each WASM agent SHALL allocate from its own heap region in shared memory using a non-atomic bump allocator. Values crossing thread boundaries SHALL be deep-copied from the sending agent's heap into the receiving agent's heap. Immutable data-segment values (constants, string literals) SHALL be shared by pointer without copying.

#### Scenario: Task stolen to another agent gets deep-copied environment

- **GIVEN** a task with a closure environment allocated on Worker 1's heap
- **WHEN** Worker 2 steals the task
- **THEN** the closure environment SHALL be deep-copied into Worker 2's heap region

#### Scenario: String literal shared without copy

- **GIVEN** a task that references a string literal from the data segment
- **WHEN** the task is stolen to another worker
- **THEN** the string literal SHALL NOT be copied — both workers reference the same data segment pointer

### Requirement: Graceful Degradation

The runtime SHALL detect available parallelism capabilities and fall back gracefully: WASM threads (shared memory + atomics) → multi-instance (N WASM stores on N OS threads) → sequential (single worker). The user's Camp code SHALL remain the same regardless of strategy.

#### Scenario: WASM threads available

- **GIVEN** a WASM runtime that supports shared memory and atomic instructions
- **WHEN** `--threads=4` is specified
- **THEN** the runtime SHALL use 4 WASM agents sharing one Memory object with atomic work queues

#### Scenario: WASM threads not available, multi-instance fallback

- **GIVEN** a WASM runtime that does not support shared memory
- **WHEN** `--threads=4` is specified
- **THEN** the runtime SHALL create 4 WASM stores on 4 OS threads with closure serialization for cross-instance task distribution

#### Scenario: Single-threaded fallback

- **GIVEN** a runtime that does not support multi-instance
- **WHEN** a program uses `Async!` or `Parallel!` effects
- **THEN** the sequential handler SHALL execute correctly with `--threads=1`

### Requirement: Thread Count Configuration

The number of workers SHALL be configurable via `--threads=N` CLI flag (highest priority), `CAMP_THREADS` environment variable (medium priority), or `num_cpus()` runtime detection (lowest priority / default).

#### Scenario: CLI flag overrides env var

- **GIVEN** `--threads=4` is specified and `CAMP_THREADS=8` is set
- **WHEN** the runtime initializes
- **THEN** it SHALL use 4 workers

#### Scenario: Default to CPU count

- **GIVEN** no `--threads` flag and no `CAMP_THREADS` env var
- **WHEN** the runtime initializes on a machine with 8 logical cores
- **THEN** it SHALL use 8 workers

### Requirement: Unified Scheduler Serves Three Effects

The `Async!`, `Spawn!`, and `Parallel!` effects SHALL all map to the same work-stealing scheduler. Their handlers install different evidence records but share the same local queues, global queue, handle table, wait map, join map, and timer wheel.

#### Scenario: Async task uses Spawn internally

- **GIVEN** a task spawned via `Async!.spawn!` that internally calls `Spawn!.spawn!`
- **WHEN** the inner spawn is executed
- **THEN** the inner task SHALL be enqueued on the same scheduler and any worker MAY execute it

#### Scenario: Parallel chunk uses same scheduler

- **GIVEN** `Parallel!.map!` distributes chunks via `Spawn!.spawn!`
- **WHEN** the chunk tasks are spawned
- **THEN** they SHALL be enqueued on the same scheduler and work-stealing SHALL distribute them across workers

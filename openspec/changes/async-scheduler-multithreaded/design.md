## Context

Camp currently has three concurrency effects (`Async!`, `Spawn!`, `Parallel!`) with stub runtime functions — no scheduler actually exists. The spec mandates single-threaded `Async!`, which makes the language unviable for production workloads. The compiler emits `Wasm_Unreachable` for `IR_Handle` and `IR_Perform` nodes. The IR has no atomic nodes, no resume node, and the codegen has only 5 runtime functions (alloc, dup, drop, print_str, exit). The existing `parallelism/design.md` describes a phased approach (Phase 1: single-threaded async, Phase 3: multi-instance spawn, Phase 5: WASM threads) that defers multithreading to late stages — this is backwards for a language that needs to be viable.

**Current state of runtime**: `RUNTIME_FUNC_COUNT :: 5`. No WASI I/O integration. No scheduler codegen. No atomic operations. `Handle(a)` type exists in the prelude but has no runtime backing.

**Prior art studied**:
- **Tokio** (Rust): Multi-threaded work-stealing scheduler with LIFO slot + local queue (cap 256) + global inject queue. Cooperative budget (128 ops/tick). Per-worker I/O driver via mio/epoll. Hierarchical timer wheel. Stealable LIFO slot (PR #7431) fixes latency bubbles. "Making the Tokio Scheduler 10x Faster" (Carl Lerche, 2019).
- **Go GMP**: G (goroutine), M (OS thread), P (processor with local run queue). Steal-half from victim. Spinning thread protocol for efficient wake/sleep. Global queue checked every 61 ticks. Netpoller integration. "Go 1.5 scheduler design" (Dmitry Vyukov).
- **Koka**: Async implemented as effect handler library — `async/await` handler passes `resume` as the callback to `initiate`. Evidence passing for O(1) dispatch. "Structured Asynchrony with Algebraic Effects" (Leijen, 2017).
- **WASI Preview 2**: Poll-based I/O via `wasi:io/poll.poll-list`. No push notifications. Composability gap — only one component can block at a time.
- **WASI Preview 3 (future)**: Component Model async with `waitable-set.wait/poll`, callback-based stackless ABI, host-managed event loop.
- **WASM stack switching (future)**: `cont.new`/`resume`/`suspend` for first-class continuations. Not yet standardized.

## Goals / Non-Goals

**Goals:**

- A unified multithreaded work-stealing scheduler serving `Async!`, `Spawn!`, and `Parallel!` from a single runtime
- N WASM agents sharing work via local queues, global queue, and steal-half
- Guaranteed cancellation delivery (not best-effort) within one cooperative budget cycle
- Type-system-enforced error propagation: `Handle(a, e)` carries effect row, `join!` propagates `e`
- Structured concurrency: unjoined handles auto-cancelled on handler exit; compiler warning → error progression
- Hierarchical timer wheel for O(1) sleep/timeout with batch expiry
- Cooperative budget (128 ops/tick) for bounded tail latency
- WASI I/O bridge: Worker 0 drives `wasi:io/poll.poll-list`, other workers focus on CPU work
- Graceful degradation: WASM threads → multi-instance → sequential
- Migration path to WASI Preview 3 (API-identical, only runtime functions change)

**Non-Goals:**

- Preemptive scheduling (WASM cannot preempt; budget is the strongest cooperative guarantee)
- SIMD auto-vectorization for `Parallel!.map!` (future work)
- Shared tables/globals across WASM agents (not supported by WASM threads proposal)
- Ownership-transfer optimization for values crossing thread boundaries (v1 uses deep copy)
- Work-stealing with Chase-Lev deque (fixed ring buffer with steal-half is simpler and well-proven)
- Per-worker I/O driver (WASI `poll-list` is centralized; Worker 0 drives it)

## Decisions

### D1: Unified scheduler, not three separate runtimes

**Decision**: `Async!`, `Spawn!`, and `Parallel!` all map to the same work-stealing scheduler. Their handlers install different evidence records but share the same queues, handle table, and timer wheel.

**Rationale**: Separate runtimes cannot compose — an `Async!.spawn!` task cannot use `Spawn!` internally if they're on different thread pools. A single scheduler allows any task to use any effect. Tokio doesn't have separate runtimes for `tokio::spawn` vs `tokio::task::spawn_blocking`; it's one pool with different task type hints.

**Alternatives considered**:
- Three separate schedulers: Simpler to implement initially, but fails composition. A task spawned with `Async!` that internally does `Spawn!.spawn!` would deadlock or require cross-runtime bridging.
- Two schedulers (async + parallel): Still has the composition problem and doubles the runtime complexity.

### D2: Work-stealing with steal-half, LIFO slot, and spinning protocol

**Decision**: Each worker has a local queue (ring buffer, cap 256) + LIFO slot (atomic swap). Idle workers steal half from a random victim's local queue. The spinning protocol (from Go) avoids thundering-herd wakeups: only unpark a worker when no spinning workers exist.

**Rationale**: This is the combined best-of from Tokio and Go, both battle-tested in production:
- **Steal-half** (Tokio, Go): Taking half balances load without causing cache thrashing (steal-all) or high contention (steal-one).
- **LIFO slot** (Tokio): A freshly woken task is likely in the spawning worker's L1 cache. Critical for message-passing patterns. Must be stealable (Tokio PR #7431) to prevent latency bubbles.
- **Spinning protocol** (Go): `nmspinning` counter avoids both under-utilization (no spinner when work arrives) and over-waking (thundering herd). The protocol: unpark only when `idle_P > 0 AND nmspinning == 0`.
- **Global queue every 61 ticks** (Go): Prime number prevents resonance patterns. Ensures injected tasks (I/O completions, external spawns) aren't starved by local-only work.

**Alternatives considered**:
- Chase-Lev deque: Theoretically elegant (formal linearizability proof), but Tokio moved away from it because it supports unbounded growth (allocation in hot path), single-task steal (high contention), and adds complexity vs. the fixed ring buffer.
- Random work-stealing without LIFO: Simpler but loses the cache-locality benefit for message-passing patterns (request/response fan-out).
- No spinning protocol: Either under-utilization (workers sleep too eagerly) or thundering herd (all workers wake on every notification).

### D3: `Handle(a, e)` carries effect row

**Decision**: The handle type parameterized by both the result type and the thunk's effect row: `Handle(a, e)`. When `join!` is called, `e` propagates into the caller's effect row.

```camp
effect Spawn! {
  spawn! : |thunk: || -[e]-> a| -[Spawn!]-> Handle(a, e)
  join!  : |handle: Handle(a, e)| -[Spawn! | e]-> a
  cancel! : |handle: Handle(a, e)| -[Spawn!]-> {}
}
```

**Rationale**: Without `e` on the handle, `join!` cannot statically propagate the thunk's effects. If `spawn!(|| -[Throw!(ParseError)]-> Int { parse!(input) })` produces `Handle(Int)`, then `join!` has no way to require `Throw!(ParseError)` in the caller's effect row. The effect row must be carried for correctness.

**Alternatives considered**:
- `Handle(a)` without `e`: Simpler, but `join!` cannot propagate thunk effects. Would require either (a) restricting spawned thunks to pure functions (too restrictive), or (b) a dynamic effect check at `join!` time (defeats the purpose of static effect rows).
- `JoinHandle(a, e)` separate from `Handle(a)`: Adds API surface for no benefit — `join!` always needs `e`.

### D4: Guaranteed cancellation, not best-effort

**Decision**: `cancel!` sets an atomic cancellation flag in the task header. Every `perform` and `yield!` site checks the flag. If set, the task exits with a `Cancelled` result immediately. The worst-case latency before a cancelled task observes cancellation is one budget cycle (128 operations).

**Rationale**: Best-effort cancellation is incorrect. If a cancelled task continues running, it:
1. Wastes CPU resources that could serve other tasks
2. May produce side effects (console output, file writes) that violate program invariants
3. May throw errors that propagate to unexpected handlers
4. Creates race conditions where the cancelled task's result overwrites the cancellation

Cooperative cancellation at yield/perform points is the strongest guarantee achievable without WASM preemption. Camp's effect system is an advantage here: every `perform` is a yield point, so the check is naturally placed where control returns to the scheduler.

**Implementation**: The cancellation check adds ~6 WASM instructions at each `IR_Perform` site:

```odin
// In CPS transform, before each perform:
// i32.atomic.load(cancel_flag_ptr)
// i32.eqz
// br_if .continue_normal
// call $camp_sched_complete(handle_id, CANCELLED_TAG, 0)
// return
```

**Alternatives considered**:
- Best-effort (current spec): Incorrect for a correctness-first language.
- Host-assisted cancellation via WASI Preview 3: Not available yet. When it arrives, it provides stronger guarantees (the host can refuse to resume a cancelled task), but cooperative cancellation is the correct design for WASI Preview 2.
- Asynchronous cancellation (POSIX `pthread_cancel`): Not available in WASM. Unsafe in any case (cancellation during heap allocation = use-after-free).

### D5: Hierarchical timer wheel for sleep/timeout

**Decision**: A 4-level hierarchical hashed timer wheel in shared memory. Level 0: 64 slots × 1 ms granularity (64 ms span). Level 1: 64 slots × 64 ms (4 s span). Level 2: 64 slots × 4 s (4 min span). Level 3: 64 slots × 4 min (4 hr span). Worker 0 advances the wheel after each `wasi:io/poll.poll-list` call.

**Rationale**: Timer wheels provide O(1) insert and O(1) amortized expiry — superior to per-timer WASI `subscribe_duration` calls. The wheel's next expiry naturally sets the `poll-list` timeout. Timer cancellation is O(1) (remove from linked list) vs. a WASI host call. Batch expiry processes all expired timers in one pass.

Additionally, WASI `subscribe_duration` with zero-duration waits can starve the host's async runtime (Wasmtime issue #13040). The timer wheel avoids this by controlling the timeout directly.

**Alternatives considered**:
- Per-timer WASI pollable: Each `sleep!` creates a `subscribe_duration` pollable and registers it in the wait map. Simpler but slower (host call per timer) and has the zero-duration starvation bug.
- Sorted linked list: O(1) insert but O(n) advance (must scan for expired timers).
- Red-black tree: O(log n) insert and O(log n) expiry. Over-engineered for the use case.
- Hashed timing wheel (single level): O(1) for short timeouts but O(n) for long timeouts that span multiple wheel revolutions.

### D6: Cooperative budget (128 ops/tick)

**Decision**: Each task gets 128 operations per "tick" (scheduler quantum). The budget decrements at every `perform` and `yield!`. When exhausted, the task is re-enqueued at the tail of the local queue with a fresh budget. The budget is instrumented during CPS transformation.

**Rationale**: Without preemption, a CPU-bound task that never awaits will starve all other tasks on its worker. Tokio uses the same budget mechanism (128 ops) based on empirical testing with Noria and HTTP workloads. In Camp, every effect `perform` is a natural yield point, so the budget is more effective than in Rust (where `.await` is the only yield point).

**Correctness guarantee**: No task can execute more than 128 effect operations without yielding to the scheduler. This bounds worst-case tail latency.

**Alternatives considered**:
- No budget: A CPU-bound infinite loop freezes one worker permanently, reducing throughput to (N-1)/N.
- Smaller budget (32): More responsive but higher scheduling overhead for I/O-heavy workloads.
- Larger budget (1024): Lower overhead but longer latency spikes.
- Preemption via WASM stack switching: Not yet available. When `cont.suspend` is standardized, it could provide true preemption, but the budget mechanism is still useful as a cooperative first line of defense.

### D7: Per-agent heap regions with deep-copy crossing

**Decision**: Each WASM agent allocates from its own heap region in shared memory (bump allocator, non-atomic). Values crossing thread boundaries are deep-copied into the receiving agent's heap. Immutable data-segment values are shared by pointer (read-only, no refcounting).

**Rationale**: Per-agent heaps avoid:
1. Cross-thread refcounting (Perceus `camp_dup`/`camp_drop` are non-atomic — must not be called from multiple agents)
2. Allocator contention (no global lock on `camp_alloc`)
3. False sharing (values aren't adjacent in memory across agents)

Deep copy is the only correct option for v1. Ownership transfer (increment refcount to 1, pass pointer) requires careful memory ordering and is deferred to future optimization.

**Alternatives considered**:
- Global shared heap: Requires atomic refcounting on every `camp_dup`/`camp_drop`, destroying Perceus's deterministic deallocation guarantee and adding overhead to every allocation.
- Ownership transfer: Faster but requires (a) atomic refcount operations, (b) careful synchronization to prevent the sender from decrementing after transfer, and (c) handling of cycles. Too complex for v1.
- Immix-style region allocation: More advanced but requires runtime support not available in WASM.

### D8: Worker 0 drives I/O, other workers focus on CPU

**Decision**: Worker 0 runs the I/O driver (collects pollables from the shared wait map, calls `wasi:io/poll.poll-list` with timer-wheel timeout, dispatches completions). When Worker 0 has local work, it processes tasks first and polls I/O when idle. Other workers never call `poll-list`.

**Rationale**: WASI `poll-list` blocks the calling thread. Multiple workers calling it concurrently creates redundant wakeups. One driver batching all pollables is more efficient and simpler. This matches Tokio's approach where idle workers naturally cover I/O polling.

**I/O registration flow**: When a task on Worker 3 blocks on I/O, the I/O registration (pollable + task) is placed in the shared wait map. Worker 0 picks it up on its next poll cycle. When the I/O completes, the task is returned to Worker 3's local queue (affinity) or the global queue.

**Alternatives considered**:
- Per-worker I/O driver: Would require each worker to poll independently, wasting CPU when most pollables belong to one worker. Tokio uses per-worker drivers because epoll supports per-fd registration, but WASI `poll-list` takes a batch of all pollables — centralization is natural.
- Dedicated I/O thread: Adds a thread that only does I/O. Wastes a core when I/O is light. Worker 0 does double duty more efficiently.

### D9: WASM atomics for thread coordination (SeqCst only)

**Decision**: All atomic operations use WASM's sequentially consistent ordering (`SeqCst`). No Acquire/Release reasoning needed.

**Rationale**: WASM only supports `SeqCst` atomics. This is actually a correctness advantage — on platforms with weaker orderings (ARM, RISC-V), subtle bugs arise from incorrect Acquire/Release pairs. WASM's `SeqCst`-only atomics eliminate an entire class of bugs. The performance cost is negligible because the host runtime (wasmtime, browser) handles the underlying memory model.

**Thread parking**: `memory.atomic.wait32` on a notification address (with epoch check for lost-wakeup prevention). `memory.atomic.notify` to wake one or all workers.

```wasm
;; Park worker
i32.atomic.load notification_addr  ;; load current epoch
local.set $epoch
;; double-check for work (avoid lost wakeup)
call $has_work
br_if $skip_park
i32.atomic.wait32 notification_addr $epoch -1  ;; -1 = infinite timeout
;; (returns 0 = woken, 1 = spurious, 2 = timeout)

;; Unpark one worker
i32.atomic.rmw.add notification_addr 1
memory.atomic.notify notification_addr 1
```

### D10: Structured concurrency — phased enforcement

**Decision**: Three-phase enforcement:
1. **Phase 1 (runtime)**: Handler exit iterates the handle table and auto-cancels all `Pending` handles in its scope. Prevents resource leaks.
2. **Phase 2 (compiler warning)**: Typechecker flags any `spawn!` where the resulting handle is not consumed by `join!` or `cancel!` on all control flow paths within the handler scope.
3. **Phase 3 (compiler error)**: Unjoined spawns are a type error. `Handle(a, e)` is a linear type — it must be consumed exactly once.

**Rationale**: Phase 1 is the safety net (correct by construction at runtime). Phase 2 catches mistakes early (developer experience). Phase 3 is the correct end state (no runtime overhead for enforcement).

**Phase 2 typechecker logic**:

```camp
// After handle Async!/Spawn! block exits:
//   Collect all Handle(a, e) values created by spawn! in this scope
//   For each handle, verify it is consumed by join!/cancel! on ALL paths
//   If not consumed: emit warning "handle may leak — consider joining or cancelling"
//   If consumed on some paths but not others: emit warning "handle may leak on error path"
```

### D11: Error propagation through `join!` via result-slot tagging

**Decision**: The handle table's result slot uses a 2-word format: `(tag: u32, value: u32)`. Tag 0 = normal result, tag 1 = thrown error. When a spawned task throws, the error is caught at the spawn boundary, stored with tag 1, and `join!` re-throws via `Throw!.throw!` in the caller's context.

**Rationale**: Error propagation across task boundaries must work for both same-thread `Async!` and cross-thread/cross-instance `Spawn!`. The result-slot tag is the serialization format that works in both cases. For multi-instance mode, the tag + error value are serialized across the host boundary.

**Correctness through the type system**: `Handle(a, e)` carries `e`, which includes `Throw!(ErrType)` if the thunk can throw. `join!` propagates `e` into the caller's effect row. If the caller doesn't handle `Throw!`, they get a compile-time error. This is correct by construction — no runtime surprise exceptions.

### D12: Migration path to WASI Preview 3

**Decision**: The `Async!`/`Spawn!`/`Parallel!` effect APIs remain identical. Only the `camp_sched_*` runtime functions change internally. When Preview 3 is available:
- `camp_sched_block_io` uses `waitable-set.wait` instead of `wasi:io/poll.poll-list`
- `camp_sched_timer_insert` uses `subscribe_duration` + `waitable-set.wait`
- The worker loop returns to the host event loop (callback ABI) instead of driving `poll-list` internally
- `camp_sched_yield` returns to the host (callback returns "yield" code)

**Rationale**: Effects express intent; handlers choose strategy. The user code and handler evidence records are unchanged. Only the runtime codegen adapts to the host's capabilities. This is the core advantage of the effect-handler architecture.

## Risks / Trade-offs

### R1: Cooperative budget cannot guarantee fairness under CPU-bound tasks

**Risk**: A task that performs 127 budget-free operations between each `perform` can run for an unbounded time. The budget only decrements at effect `perform` sites, not at every function call.

**Mitigation**: (1) The budget is instrumented at *every* `perform`, which in Camp includes all I/O operations and `yield!`. (2) Future: WASM stack switching (`cont.suspend`) enables true preemption by the host. (3) For CPU-bound work, users should use `Spawn!.spawn!` (which blocks on `join!` and doesn't starve the scheduler) or explicitly call `Async!.yield!()` in hot loops.

### R2: Deep-copy overhead for cross-thread values

**Risk**: When a task is stolen by Worker 2, its closure environment must be deep-copied from Worker 1's heap into Worker 2's heap. For large environments, this is O(n) in environment size.

**Mitigation**: (1) The compiler minimizes closure environments (only captured variables, not the entire scope). (2) Immutable data-segment values (string literals, constants) are shared by pointer without copying. (3) Future: ownership transfer optimization (increment refcount to 1, pass pointer). (4) The steal-half algorithm means stolen tasks have already-executed ancestors in the victim's cache — their environments are typically small.

### R3: Single I/O driver (Worker 0) is a bottleneck under heavy I/O

**Risk**: If 10,000 I/O-bound tasks are all waiting on Worker 0's poll cycle, Worker 0 becomes a serialization point for I/O dispatch.

**Mitigation**: (1) Worker 0 processes tasks from its local queue *before* polling I/O, so it's not exclusively an I/O thread. (2) I/O completions are dispatched to the originating worker's local queue, spreading the dispatch work. (3) The wait map is in shared memory — any worker can register a new pollable without going through Worker 0. (4) Future: per-worker I/O driver if WASI adds per-fd polling.

### R4: Timer wheel accuracy depends on `poll-list` call frequency

**Risk**: If Worker 0 is busy processing CPU tasks and doesn't call `poll-list` for 100ms, all timers during that window are delayed.

**Mitigation**: (1) The budget system ensures Worker 0 yields to the scheduler frequently. (2) The worker loop prioritizes: LIFO → local → global (every 61 ticks) → steal → I/O poll → park. Worker 0 will reach the I/O poll step within bounded time. (3) The MAX_BATCHES limit on task processing before polling ensures I/O is checked regularly.

### R5: WASM threads availability varies across runtimes

**Risk**: Not all WASM runtimes support shared memory + atomics. The multi-instance fallback adds significant complexity (closure serialization, host-managed thread pool).

**Mitigation**: (1) Runtime detection at startup (try creating shared Memory; fallback). (2) The unified scheduler API is identical regardless of backend — the `camp_sched_*` functions have different internal implementations for threads vs. multi-instance, but the handler evidence records are the same. (3) Sequential fallback always works for development/testing.

### R6: `Handle(a, e)` increases type complexity

**Risk**: Adding `e` to Handle makes type signatures more verbose and may increase type inference complexity.

**Mitigation**: (1) Effect inference already handles row variables — `e` is just another row variable. (2) Most handles will have `e` inferred from the thunk's effect row. (3) The correctness benefit (static enforcement of error propagation through `join!`) outweighs the verbosity cost.

## Migration Plan

### For existing Camp programs

- **Programs without `Async!`/`Spawn!`/`Parallel!`**: No change. The scheduler is not initialized.
- **Programs with `Async!` in `main!`**: `_start` now initializes the multithreaded scheduler (defaulting to `--threads=num_cpus()`). Single-threaded mode available via `--threads=1`. The effect API is unchanged.
- **Programs with `Handle(a)`**: Must be updated to `Handle(a, e)`. This is a breaking change but mechanically straightforward — add the effect row parameter.
- **Programs relying on "best-effort" cancellation**: Must be updated to handle guaranteed cancellation (tasks now actually stop). This is a behavior change but a correctness improvement.

### Deployment strategy

1. **Phase 1**: Implement scheduler with `--threads=1` default (single-worker mode). All existing tests pass.
2. **Phase 2**: Enable `--threads=N` with WASM threads. E2E tests for multi-worker correctness.
3. **Phase 3**: Multi-instance fallback. E2E tests for environments without WASM threads.
4. **Phase 4**: Update spec requirements. Publish breaking change notice for `Handle(a, e)` and guaranteed cancellation.

### Rollback

If the multithreaded scheduler causes regressions, `--threads=1` reverts to single-worker mode (equivalent to the old single-threaded design but with the unified scheduler architecture). The effect APIs are identical — no code changes needed.

## Open Questions

### O1: Should the timer wheel live in shared memory or on Worker 0's stack?

**Options**: (a) Shared memory — all workers can insert timers. (b) Worker 0 local — only Worker 0 inserts; other workers route timer requests via the global queue.

**Preference**: Shared memory with atomic operations on the timer slot linked lists. This allows any worker to insert a timer (e.g., `Time.sleep!` called from Worker 3) without going through Worker 0. The overhead is one atomic CAS per insert.

### O2: Should `Parallel!.any!` use early-termination or first-success semantics?

**Current spec**: "Execute tasks; return first successful result; cancel remaining." This means `any!` waits for at least one success even if some tasks fail. If all tasks fail, the last error propagates.

**Alternative**: Return as soon as any task completes (success or failure). Let the caller decide via the type system.

**Preference**: Keep current spec (first-success with cancellation). This is the most useful semantic — `any!` is for redundancy (try multiple mirrors, return whichever responds first).

### O3: Maximum handle count and what happens when exhausted

**Current plan**: MAX_HANDLES = 4096, configurable via `--handles=N`. When exhausted, `spawn!` performs `Throw!.throw!(HandleLimit)`.

**Open question**: Should this be a `Throw!` or a trap? `Throw!` is composable (caller can catch it). A trap is simpler but not recoverable.

**Preference**: `Throw!` for composability. The caller can catch `HandleLimit` and decide what to do (e.g., wait for existing handles to complete, then retry).

### O4: Budget value — should 128 be configurable?

**Preference**: Fixed at 128 for v1. Make it configurable via `--budget=N` only if benchmarks show a different value is significantly better for real workloads. Tokio uses 128 and it's well-tested.

### O5: Should `Async!.yield!()` always yield or only when budget is exhausted?

**Preference**: Always yield. `yield!` is an explicit request to reschedule. The budget system provides implicit yielding; `yield!` provides explicit yielding. Both are needed. However, `yield!` still decrements the budget — if budget was already 0, the yield is a no-op (already yielded).

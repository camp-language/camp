## Why

Camp has no working async scheduler — the current `camp_async_*` runtime functions are stubs (camp-68m, P0 blocker). More fundamentally, the existing spec mandates a single-threaded event loop for `Async!`, which makes Camp unviable for production use: any real server, CLI tool, or data pipeline needs multithreaded I/O concurrency. Meanwhile, `Spawn!` and `Parallel!` have separate runtime stubs but no unified scheduling strategy, leading to three disconnected runtimes that cannot compose. The language needs a single, correct, multithreaded work-stealing scheduler that serves all three concurrency effects, with guaranteed cancellation delivery, type-system-enforced error propagation through `join!`, and structured concurrency that prevents resource leaks.

## What Changes

- **Unified multithreaded work-stealing scheduler** replacing the three separate stub runtimes for `Async!`, `Spawn!`, and `Parallel!`. N WASM agents (OS threads) share local queues, a global inject queue, a shared handle table, and a single timer wheel. Worker 0 drives I/O polling; all workers participate in work-stealing.
- **BREAKING: `Async!` becomes multithreaded.** The spec requirement "Async! runtime SHALL run all coroutines on one WASM thread" is removed. `Async!` tasks run on any worker in the pool.
- **BREAKING: `Handle(a)` becomes `Handle(a, e)`.** The handle type now carries the spawned thunk's effect row `e`, so `join!` can propagate thunk effects into the caller's effect row by construction.
- **BREAKING: Cancellation is guaranteed delivery, not best-effort.** `cancel!` sets an atomic cancellation flag; tasks observe cancellation at every yield/perform point within one budget cycle (128 operations). Best-effort cancellation is incorrect for a correctness-first language.
- **BREAKING: Timer wheel replaces `wasi:io/poll-list` timeout for sleep.** `Time.sleep!` uses a hierarchical hashed timer wheel (O(1) insert/cancel, batch expiry) instead of creating a WASI pollable per sleep.
- **LIFO slot per worker** for cache-locality optimization (stolen from Tokio's design), with stealable atomic swap to prevent latency bubbles.
- **Cooperative budget system** (128 operations per tick) for fairness without preemption, instrumented at every effect `perform` site.
- **Structured concurrency enforcement progression**: runtime auto-cancel on handler exit (now) → compiler warning for unjoined spawns (near) → compiler error (correct).
- **Work-stealing algorithm**: steal-half from victim's local queue (same as Tokio and Go), with spinning thread protocol from Go to avoid thundering-herd wakeups.
- **Multi-instance fallback**: When WASM threads are unavailable, the scheduler degrades to N WASM stores on N OS threads with closure serialization.
- **Spec updates** for `parallelism`, `effects`, and `language` domains reflecting the unified scheduler, `Handle(a, e)`, guaranteed cancellation, and multithreaded `Async!`.

## Capabilities

### New Capabilities

- `async-scheduler`: The unified multithreaded work-stealing scheduler — local queues, global inject queue, LIFO slots, handle table, wait map, join map, timer wheel, cooperative budget, spinning protocol, thread parking via `memory.atomic.wait32`/`notify`, and the worker loop that ties them together.

### Modified Capabilities

- `parallelism`: `Async!` becomes multithreaded; `Handle(a)` becomes `Handle(a, e)`; cancellation becomes guaranteed delivery; timer wheel replaces poll-timeout sleep; unified scheduler replaces separate `Async!`/`Spawn!`/`Parallel!` runtimes.
- `effects`: `Handle(a, e)` type parameter carries effect row; `join!` propagates thunk effects via row composition; error re-throw on `join!` uses result-slot tag to distinguish normal results from thrown errors.
- `language`: `Handle(a, e)` type syntax; structured concurrency enforcement (warning → error); cooperative budget semantics at yield/perform points.

## Impact

**Compiler codegen (`src/codegen.odin`)**: New runtime functions for scheduler init, spawn, join, cancel, yield, block_io, timer_insert/cancel, worker_loop, park/notify. Shared memory flag on WASM memory declaration. `camp_worker_entry` export. Effectful `_start` integration.

**Compiler pipeline (`src/effect_lower.odin`, `src/cps.odin`)**: Budget decrement instrumentation at every `IR_Perform` site. Cancellation flag check at yield/perform sites. `Handle(a, e)` type parameter threading through evidence records.

**Typechecker (`src/typecheck.odin`)**: `Handle(a, e)` type with effect row parameter. Effect row propagation through `join!`. Unjoined spawn warning.

**Runtime (`src/runtime.odin`)**: ~15 new runtime function body emitters (scheduler core, I/O bridge, timer wheel, atomics).

**IR (`src/ir.odin`)**: Atomic IR nodes (`IR_Atomic_Load`, `IR_Atomic_Store`, `IR_Atomic_RMW`, `IR_Atomic_Fence`, `IR_Wait`, `IR_Notify`). `IR_Resume` node for one-shot continuation invocation.

**Specs**: Breaking requirement changes in `parallelism/spec.md`, `effects/spec.md`, `language/spec.md`. New `async-scheduler/spec.md` for the unified scheduler capability.

**Host integration (Odin CLI)**: Thread pool manager for multi-instance fallback. Closure serialization format. Runtime detection (WASM threads → multi-instance → sequential).

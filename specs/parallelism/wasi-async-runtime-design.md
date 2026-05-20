# WASI Async Runtime Design Specification

> *"The runtime's job is to make I/O concurrency invisible to the programmer."*

## Table of Contents

1. [Overview](#1-overview)
2. [Design Philosophy](#2-design-philosophy)
3. [Coroutine Scheduler](#3-coroutine-scheduler)
4. [WASI I/O Poll Bridge](#4-wasi-io-poll-bridge)
5. [Effect-to-WASI Mapping](#5-effect-to-wasi-mapping)
6. [Sleep and Yield](#6-sleep-and-yield)
7. [Structured Concurrency for Async](#7-structured-concurrency-for-async)
8. [WASM Codegen for Async Runtime](#8-wasm-codegen-for-async-runtime)
9. [Component Model Async Migration](#9-component-model-async-migration)
10. [Implementation Plan](#10-implementation-plan)
11. [References](#11-references)

---

## 1. Overview

This spec defines how Camp's `Async` effect integrates with WASI's I/O polling mechanism to provide cooperative I/O concurrency. The runtime provides an `Async` handler that:

1. Manages a queue of ready coroutines
2. Integrates with `wasi:io/poll` to wait for I/O readiness
3. Resumes coroutines when their I/O operations complete
4. Enforces structured concurrency (every spawned task must be joined/cancelled)

The design targets WASI Preview 2 (the current stable version), with a migration path to WASI Preview 3's component model async when it becomes available.

---

## 2. Design Philosophy

### 2.1 Single-Threaded Event Loop

Camp's `Async` runtime is a single-threaded event loop — all coroutines run on one WASM thread. This matches WASM's single-threaded execution model and is the same approach used by JavaScript, Python's asyncio, and Rust's tokio (single-threaded runtime).

**Why not multi-threaded async?**: Multi-threaded async runtimes require synchronization primitives (mutexes, channels) that add complexity and overhead. Camp's pure-functional, no-shared-mutable-state model doesn't need them. If you need true parallelism, use `Spawn` — not `Async`.

### 2.2 Poll-Driven I/O

WASI Preview 2 provides `wasi:io/poll` — a readiness-based polling mechanism. The runtime:

1. Runs ready coroutines until they block on I/O
2. Collects all blocked I/O subscriptions
3. Calls `wasi:io/poll-list` to wait for any to become ready
4. Resumes the coroutines whose I/O is ready
5. Repeat

This is the standard `select`/`poll`/`epoll` event loop pattern.

### 2.3 Stackless Coroutines

Camp's coroutines are stackless state machines (compiled via CPS transform). Each coroutine is a struct containing:
- Current state (which continuation to call)
- Live variables (values alive across yield points)
- Handle metadata (for structured concurrency tracking)

**Memory per coroutine**: ~100-300 bytes (state machine struct), compared to ~2-8 KB for a green thread with a growable stack.

---

## 3. Coroutine Scheduler

### 3.1 Data Structures

```
┌────────────────────────────────────────────────────────┐
│  Coroutine Scheduler                                   │
│                                                        │
│  Ready Queue:                                          │
│    [coroutine_3, coroutine_7, coroutine_12, ...]        │
│    Coroutines ready to run (FIFO)                     │
│                                                        │
│  Blocked Map:                                          │
│    pollable_0 → [coroutine_5, coroutine_8]             │
│    pollable_1 → [coroutine_9]                          │
│    pollable_2 → [coroutine_1]                          │
│    Maps WASI pollables to waiting coroutines           │
│                                                        │
│  Active Handles:                                       │
│    handle_1 → { status: running, coroutine: 5 }       │
│    handle_2 → { status: completed, result: 42 }       │
│    handle_3 → { status: cancelled }                    │
│    Tracks spawned coroutines for structured concurrency│
│                                                        │
│  Join Waiters:                                         │
│    handle_2 → [coroutine_3]                            │
│    Maps handles to coroutines waiting on join!         │
└────────────────────────────────────────────────────────┘
```

### 3.2 Scheduler Loop

```
loop:
  1. If ready_queue is empty and blocked_map is empty:
     → All work is done. Exit scheduler.

  2. If ready_queue is empty:
     → All coroutines are waiting on I/O.
     → Collect all pollables from blocked_map.
     → Call wasi:io/poll-list(pollables, timeout=None).
     → For each ready pollable:
         Move its coroutines from blocked_map to ready_queue.

  3. Dequeue a coroutine from ready_queue.
  4. Resume the coroutine (call its continuation).
  5. The coroutine either:
     a. Completes → store result in handle, wake join waiters
     b. Yields → add back to ready_queue
     c. Performs I/O → add to blocked_map with its pollable
     d. Joins a handle → if handle is complete, get result;
        if not, add to join_waiters
     e. Spawns a new coroutine → add to ready_queue
     f. Throws → propagate error, wake join waiters with error
  6. Go to step 1.
```

### 3.3 Fairness

- **Round-robin scheduling**: Coroutines are dequeued in FIFO order. No priority, no preemption.
- **Yield-based cooperaation**: A coroutine runs until it yields or blocks on I/O. For CPU-bound work, the coroutine should call `Async.yield!()` periodically.
- **No starvation guarantee**: A coroutine that never yields or blocks will run indefinitely. This is a deliberate tradeoff — preemptive scheduling requires runtime support that WASM doesn't provide.

---

## 4. WASI I/O Poll Bridge

### 4.1 `wasi:io/poll` Interface

```wit
interface poll {
  resource pollable {
    // A handle to something that can be polled for readiness
  }

  // Block until one or more pollables are ready
  // Returns indices of ready pollables
  poll-list: function(in: list<pollable>, timeout: option<timestamp>) -> list<u32>

  // Wait on a single pollable
  poll-one: function(in: pollable, timeout: option<timestamp>) -> result<void, error>
}
```

### 4.2 Stream Subscription

WASI streams provide `subscribe()` methods that return `pollable` handles:

```wit
interface io {
  resource input-stream {
    // Read data; may return fewer bytes than requested (short read)
    read: function(len: u64) -> result<list<u8>, error>
    // Returns a pollable that becomes ready when data is available
    subscribe: function() -> pollable
  }

  resource output-stream {
    // Write data; may accept fewer bytes than provided (short write)
    write: function(contents: list<u8>) -> result<_, error>
    // Returns a pollable that becomes ready when writing can proceed
    subscribe: function() -> pollable
  }
}
```

### 4.3 Integration Pattern

When a Camp coroutine calls `File.read!(handle)`:

```
1. Call wasi:io/input-stream.read(len)
2. If result is Ok(data) and data.len > 0:
   → Read succeeded. Return data to coroutine.
3. If result is Ok(data) and data.len == 0 (short read / would-block):
   → Call handle.subscribe() → get pollable
   → Add (pollable, coroutine) to blocked_map
   → Suspend coroutine (return to scheduler loop)
   → When pollable is ready, resume coroutine and retry read
4. If result is Err(e):
   → Throw the WASI error as a Camp Throw effect
```

### 4.4 Short Read/Write Handling

WASI streams may return fewer bytes than requested. The runtime handles this transparently:

- **Short read**: Buffer the received bytes, subscribe for more, continue reading until the requested length is filled or EOF.
- **Short write**: Buffer the unsent bytes, subscribe for readiness, continue writing until all bytes are sent or an error occurs.

This is the same pattern as Rust's `tokio::io::AsyncReadExt::read_exact` — the runtime handles partial I/O so the Camp programmer doesn't have to.

---

## 5. Effect-to-WASI Mapping

| Camp Effect | Camp Operation | WASI System Call | Notes |
|-------------|---------------|-----------------|-------|
| `Console` | `print!(msg)` | `wasi:io/output-stream.write(stdout, msg)` | Write to fd=1 |
| `Console` | `printerr!(msg)` | `wasi:io/output-stream.write(stderr, msg)` | Write to fd=2 |
| `Console` | `readln!()` | `wasi:io/input-stream.read(stdin)` + `subscribe()` | Read from fd=0 |
| `File` | `open!(path)` | `wasi:filesystem.path-open(path, read_write)` | Open file |
| `File` | `read!(handle)` | `wasi:io/input-stream.read(handle)` + `subscribe()` | Async file read |
| `File` | `write!(handle, data)` | `wasi:io/output-stream.write(handle, data)` + `subscribe()` | Async file write |
| `File` | `close!(handle)` | `wasi:io/resource.drop(handle)` | Close file |
| `Env` | `args!()` | `wasi:cli/environment.get-arguments()` | Get CLI args |
| `Env` | `get_env!(name)` | `wasi:cli/environment.get-environment(name)` | Get env var |
| `Time` | `now!()` | `wasi:clocks/wall-clock.now()` | Current time |
| `Time` | `sleep!(ms)` | `wasi:io/poll.poll-list([], timeout=ms)` | Sleep via poll timeout |
| `Random` | `int!(min, max)` | `wasi:random/random.get-random-bytes(8)` | Random bytes → int |
| `Async` | `yield!()` | (no WASI call; reschedule coroutine) | Cooperative yield |
| `Async` | `spawn!(thunk)` | (no WASI call; enqueue coroutine) | Create coroutine |
| `Async` | `join!(handle)` | (no WASI call; check/suspend) | Wait for completion |
| `Async` | `cancel!(handle)` | (no WASI call; mark cancelled) | Cancel coroutine |

---

## 6. Sleep and Yield

### 6.1 `Time.sleep!(ms)`

`Time.sleep!(ms)` is implemented via `wasi:io/poll-list` with a timeout:

```
Time.sleep!(ms):
  1. Create a dummy pollable (or use an empty pollables list)
  2. Call wasi:io/poll-list([], timeout=ms)
  3. Return to caller
```

When no other I/O is pending, `poll-list` blocks for the specified timeout. When other I/O is pending, the timeout is still respected — the poll returns when either I/O is ready OR the timeout expires.

### 6.2 `Async.yield!()`

`Async.yield!()` is a cooperative reschedule — no WASI call needed:

```
Async.yield!():
  1. The coroutine handler receives the yield! perform
  2. Add the current coroutine back to the ready queue (at the end)
  3. Resume the handler (which returns to the scheduler loop)
  4. The scheduler picks up the next ready coroutine
```

This gives other coroutines a chance to run before the yielding coroutine resumes.

---

## 7. Structured Concurrency for Async

### 7.1 Spawn Must Be Joined

Every `Async.spawn!(thunk)` must be followed by `Async.join!(handle)` or `Async.cancel!(handle)` before the `Async` handler exits.

### 7.2 Handler Enforcement

When the `Async` handler block is about to exit:

1. Check if all spawned handles have been joined or cancelled
2. If any are outstanding:
   - **Warning**: Emit a compiler warning (or runtime warning in debug builds)
   - **Cleanup**: Cancel all outstanding handles automatically
3. This prevents leaked coroutines that would otherwise never complete

### 7.3 Nested Async Handlers

Nested `Async` handlers create separate coroutine scopes. A coroutine spawned inside an inner handler cannot be joined in an outer handler — it belongs to the inner scope.

```camp
handle Async in {
  -- Outer scope
  h1 = Async.spawn!(|| {
    handle Async in {
      -- Inner scope
      h2 = Async.spawn!(|| { work() })
      Async.join!(h2)  -- h2 must be joined in this inner scope
    } with { ... }
  })
  Async.join!(h1)  -- h1 must be joined in this outer scope
} with { ... }
```

---

## 8. WASM Codegen for Async Runtime

### 8.1 Runtime Functions

The Camp runtime (embedded in the generated WASM module) provides these functions for the `Async` handler:

| Function | Signature | Purpose |
|----------|-----------|---------|
| `camp_async_init` | `() -> void` | Initialize scheduler data structures |
| `camp_async_enqueue` | `(coro_fn: i32, coro_env: i32) -> i32` | Enqueue a coroutine; returns handle ID |
| `camp_async_dequeue` | `() -> (fn: i32, env: i32)` | Dequeue next ready coroutine |
| `camp_async_block` | `(pollable: i32, coro_fn: i32, coro_env: i32) -> void` | Block coroutine on pollable |
| `camp_async_complete` | `(handle: i32, result: i32) -> void` | Mark handle completed with result |
| `camp_async_join_wait` | `(handle: i32, coro_fn: i32, coro_env: i32) -> void` | Suspend coroutine until handle completes |
| `camp_async_cancel` | `(handle: i32) -> void` | Cancel a handle |
| `camp_async_run` | `() -> void` | Main scheduler loop |

### 8.2 Memory Layout

```
┌──────────────────────────────────────────────────┐
│  Camp WASM Linear Memory                         │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │ Heap (camp_alloc region)                  │   │
│  │ - Application data                        │   │
│  │ - Coroutine state machine structs         │   │
│  │ - String/list/refcounted data             │   │
│  ├──────────────────────────────────────────┤   │
│  │ Async Scheduler Data                      │   │
│  │ - Ready queue (ring buffer)               │   │
│  │ - Blocked map (pollable → coro list)      │   │
│  │ - Handle table (ID → status/result)      │   │
│  │ - Join waiters (handle → coro list)       │   │
│  ├──────────────────────────────────────────┤   │
│  │ Stack (WASM stack)                        │   │
│  │ - Current coroutine's local variables     │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### 8.3 `_start` Function with Async Main

When `main!` has `Async` in its effect row:

```wasm
(func $start
  ;; Initialize async scheduler
  (call $camp_async_init)

  ;; Create main coroutine from user's main! function
  (call $camp_async_enqueue
    (i32.const <main_fn_table_idx>)
    (i32.const 0))  ;; no environment

  ;; Run the scheduler loop
  (call $camp_async_run)

  ;; Get the result from the main coroutine
  ;; (exit code)
  (call $camp_exit
    (call $camp_async_get_result
      (i32.const 0))))  ;; handle 0 = main
```

---

## 9. Component Model Async Migration

### 9.1 Current: Poll-Based (WASI Preview 2)

- I/O operations: synchronous read/write with short-read/write handling
- Blocking: `wasi:io/poll-list` with pollable subscriptions
- Coroutines: CPS-compiled state machines managed by Camp's scheduler
- Scheduler: Camp's own round-robin event loop

### 9.2 Future: Component Model Async (WASI Preview 3)

When wasmtime implements the component model async ABI:

| Current | Future | Change |
|---------|--------|--------|
| Camp's scheduler loop | Host-managed event loop | Camp doesn't manage scheduling |
| `wasi:io/poll-list` | `future<T>` / `stream<T>` | WASI provides async primitives |
| CPS-compiled coroutines | Stackless component async (callback ABI) | Runtime handles stack management |
| `camp_async_*` runtime functions | Component model async lowering/lifting | Standardized ABI |

### 9.3 Migration Path

The migration from poll-based to component model async is a **runtime change**, not a language change. Camp's `Async` effect API (`spawn!`, `join!`, `yield!`, `cancel!`) stays the same. Only the handler implementation changes:

```
Phase 1 handler:
  Async.yield!() → reschedule in Camp's scheduler loop
  Async.spawn!(thunk) → enqueue in Camp's ready queue
  Async.join!(handle) → check Camp's handle table

Phase 2 handler (component model):
  Async.yield!() → component yield (return to host)
  Async.spawn!(thunk) → component async-lift (create new async task)
  Async.join!(handle) → component async-lower (await on task)
```

**The user's code does not change.** Only the handler and runtime are replaced. This is the benefit of the effect-handler model — the language semantics are stable while the execution strategy evolves.

### 9.4 Timeline

| Milestone | ETA | Status |
|-----------|-----|--------|
| Stack-switching in wasmtime (x86_64) | 2026 H2 | WIP |
| Component model async in wasmtime | 2027 | Design exists, not implemented |
| WASI Preview 3 release | 2027+ | Depends on component model async |
| Camp migration to component model async | After wasmtime support | Requires codegen changes |

**Strategy**: Build the poll-based handler now (Phase 1). When component model async is available, add a second handler that uses it. The user selects the handler at the call site or via the runtime.

---

## 10. Implementation Plan

### Phase 1: I/O Concurrency via WASI Poll

| Step | Description | Scope | Depends On |
|------|-------------|-------|------------|
| 1a | Async scheduler data structures (ready queue, blocked map, handle table) | ~200 Odin | — |
| 1b | Scheduler loop: dequeue, resume, block, complete | ~150 Odin | 1a |
| 1c | `camp_async_*` runtime functions (WASM codegen) | ~300 Odin | 1a, 1b |
| 1d | WASI poll bridge: subscribe, poll-list, resume on readiness | ~150 Odin | 1b |
| 1e | Short read/write handling for WASI streams | ~100 Odin | 1d |
| 1f | `Time.sleep!` via poll timeout | ~50 Odin | 1d |
| 1g | `Async.yield!` (reschedule without WASI call) | ~30 Odin | 1b |
| 1h | Structured concurrency enforcement | ~80 Odin | 1a |
| 1i | Effect-to-WASI mapping: Console, File, Env, Time, Random | ~200 Odin | 1d |
| 1j | E2E tests: concurrent file reads, concurrent HTTP requests | ~150 Camp | 1i |

**Total estimated scope**: ~1,410 lines

**Exit criterion**: A Camp program can concurrently read 100 files using `Async.spawn!`/`Async.join!` with `wasi:io/poll`. I/O operations overlap — the total time is bounded by the slowest file, not the sum of all files.

---

## 11. References

| Resource | URL | Relevance |
|----------|-----|-----------|
| WASI I/O | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:io/poll`, `wasi:io/streams` — the I/O primitives |
| WASI CLI | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:cli/environment` — args, env vars |
| WASI Clocks | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:clocks/wall-clock` — time operations |
| WASI Random | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:random/random` — random generation |
| WASI Filesystem | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:filesystem` — file operations |
| Component Model Concurrency | https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md | Future async ABI design |
| Tokio (Rust) | https://tokio.rs | Reference for single-threaded async runtime design |
| Python asyncio | https://docs.python.org/3/library/asyncio.html | Reference for poll-based event loop |

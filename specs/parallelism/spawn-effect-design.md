# Spawn Effect Design Specification

> *"True parallelism requires true isolation."*

## Table of Contents

1. [Overview](#1-overview)
2. [Spawn vs Async](#2-spawn-vs-async)
3. [Effect Definition](#3-effect-definition)
4. [Handle Type](#4-handle-type)
5. [Structured Concurrency](#5-structured-concurrency)
6. [Effect Row Composition](#6-effect-row-composition)
7. [Implementation Strategy](#7-implementation-strategy)
8. [Multi-Instance Architecture](#8-multi-instance-architecture)
9. [WASM Threads Architecture](#9-wasm-threads-architecture)
10. [Fallback Strategy](#10-fallback-strategy)
11. [Implementation Plan](#11-implementation-plan)
12. [Open Questions](#12-open-questions)
13. [References](#13-references)

---

## 1. Overview

The `Spawn` effect provides task-parallelism for Camp — running independent computations on separate execution contexts (OS threads, WASM instances, or WASM agents). It is Camp's mechanism for CPU-bound parallel execution that uses multiple cores.

**Key distinction**: `Spawn` is for **parallelism** (simultaneous execution on separate cores). `Async` is for **concurrency** (overlapping I/O operations on one thread). `Parallel` is for **data parallelism** (applying one function across a collection).

### The Three Layers

```
┌──────────────────────────────────────────────────────────┐
│  Spawn: "Run THIS computation on a separate core"        │
│  Use case: independent CPU-heavy tasks                   │
│  Example: Spawn.spawn!(|| { matrix_multiply(a, b) })    │
│  Execution: truly parallel (separate OS thread/instance) │
├──────────────────────────────────────────────────────────┤
│  Parallel: "Apply THIS function across ALL elements"     │
│  Use case: data-parallel collection processing           │
│  Example: records.par_map!(|r| process!(r))              │
│  Execution: sequential or thread-pool (handler choice)   │
├──────────────────────────────────────────────────────────┤
│  Async: "Overlap THESE I/O operations"                   │
│  Use case: concurrent file/network I/O                    │
│  Example: Async.spawn!(|| { File.read!("data.txt") })    │
│  Execution: cooperative coroutines on one thread          │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Spawn vs Async

| Property | `Async` | `Spawn` |
|----------|---------|---------|
| **Purpose** | I/O concurrency | CPU parallelism |
| **Execution** | Cooperative coroutines on one thread | Separate OS threads / WASM instances |
| **Memory model** | Shared linear memory (same instance) | Isolated memory (separate instances) or shared read-only |
| **Scheduling** | Cooperative (yield-based) | Truly parallel (OS scheduler) |
| **Overhead per task** | ~100 bytes (state machine) | ~1-8 MB (WASM instance) or ~100 bytes (WASM thread) |
| **Best for** | Many I/O-bound tasks | Few CPU-heavy tasks |
| **Interaction with host** | `wasi:io/poll` | OS threads or WASM thread-spawn |
| **Effect row meaning** | "This code interleaves with other coroutines" | "This code runs on a separate core" |

**Why separate effects**: Combining them would conflate two different execution strategies. A function that does `Async.spawn!` expects cooperative scheduling; a function that does `Spawn.spawn!` expects true parallelism. The effect row communicates the intent clearly to both the programmer and the runtime.

---

## 3. Effect Definition

```camp
effect Spawn {
  -- Start an independent computation on a separate execution context
  spawn! : <a>|thunk: || -> a| -[Spawn]-> Handle(a)

  -- Wait for a spawned computation to complete, get its result
  join! : <a>|handle: Handle(a)| -[Spawn]-> a

  -- Cancel a spawned computation (best-effort)
  cancel! : <a>|handle: Handle(a)| -[Spawn]-> {}
}
```

### 3.1 Operation Semantics

| Operation | Semantic | Notes |
|-----------|---------|-------|
| `spawn!` | Creates a new execution context, starts `thunk` in it, returns a `Handle(a)` immediately | The caller continues without waiting. `thunk` runs in parallel. |
| `join!` | Blocks the current execution context until the spawned computation completes, then returns its result | If the computation threw, `join!` re-throws the error in the caller's context. |
| `cancel!` | Signals the spawned computation to stop. Best-effort — the computation may not stop immediately | The Handle becomes invalid after cancel. Joining a cancelled handle returns `None` or throws. |

### 3.2 `spawn!` Is Non-Blocking

`Spawn.spawn!(thunk)` returns immediately with a `Handle(a)`. The thunk starts executing in the background. The caller continues. This is different from `Async.spawn!` where the coroutine starts but may not run until the scheduler picks it up.

### 3.3 `join!` Re-Throws Errors

If the spawned computation throws an error (via `Throw.throw!`), `join!` re-throws that error in the caller's context:

```camp
-- Spawned computation that may fail:
result = Spawn.spawn!(|| -[Throw(ParseError)]-> Int {
  parse_int!(input)
})

-- join! propagates the error:
value = Spawn.join!(result)
-- If the spawned computation threw ParseError,
-- join! throws ParseError here.
```

The effect row of `join!` includes `Throw(e)` when the spawned thunk's effect row includes `Throw(e)`.

---

## 4. Handle Type

```camp
-- Handle(a) represents a spawned computation that will produce a value of type a
-- It is opaque — the user cannot inspect its internals
Handle(a) : Type
```

### 4.1 Handle Properties

- **Opaque**: The user cannot access the Handle's internal state (thread ID, result slot, etc.)
- **One-shot**: A Handle can be `join!`ed or `cancel!`ed at most once. Double-join is a runtime error.
- **Move semantics**: A Handle is consumed by `join!` or `cancel!`. It cannot be used after.
- **No send**: A Handle cannot be passed to another spawned computation (it belongs to the spawning context).

### 4.2 Handle Lifecycle

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Created  │────▶│  Pending │────▶│Completed │
│ (spawn!)  │     │(running)  │     │(result   │
└──────────┘     └──────┬───┘     │ ready)   │
                        │          └──────┬───┘
                        │                 │
                   ┌────▼────┐       ┌────▼────┐
                   │Cancelled │       │  Joined │
                   │(cancel!) │       │(join!)  │
                   └─────────┘       └─────────┘
```

---

## 5. Structured Concurrency

### 5.1 Every Spawn Must Be Resolved

Every `Spawn.spawn!` must be followed by exactly one `Spawn.join!` or `Spawn.cancel!` before the enclosing handler exits. This is **structured concurrency** — following Rust's scoped threads and Swift's structured concurrency model.

### 5.2 Compiler Enforcement (Future)

The compiler emits a **warning** (future: error) for unjoined spawns:

```camp
handle Spawn in {
  h = Spawn.spawn!(|| { heavy_work!() })
  -- WARNING: h is never joined or cancelled
  42
} with { ... }
```

### 5.3 Handler-Level Enforcement

The `Spawn` handler tracks outstanding handles. When the handler block exits:

1. Check if all handles have been joined or cancelled
2. If not, emit a warning or error (configurable)
3. Cancel any outstanding handles automatically (resource safety)

### 5.4 Why Structured Concurrency

Unstructured concurrency (fire-and-forget) leads to:
- **Resource leaks**: Spawned computations hold memory and resources
- **Use-after-free**: A handle referencing a completed computation is a dangling reference
- **Unpredictable behavior**: Background tasks modifying shared state or producing output after the program has moved on

Camp eliminates these by requiring every spawn to have a defined outcome.

---

## 6. Effect Row Composition

### 6.1 Pure Spawn

```camp
-- Spawn a pure computation:
h = Spawn.spawn!(|| { fibonacci(40) })
result = Spawn.join!(h)
-- Effect row: { Spawn }
```

### 6.2 Spawn + Throw

```camp
-- Spawn a computation that may fail:
h = Spawn.spawn!(|| -[Throw(ParseError)]-> Int { parse_int!(input) })
result = Spawn.join!(h)
-- Effect row: { Spawn, Throw(ParseError) }
-- If the spawned computation throws, join! re-throws in the caller's context
```

### 6.3 Spawn + Parallel

```camp
-- The Parallel effect's thread-pool handler uses Spawn under the hood:
handle Parallel in {
  records.par_map!(|r| process!(r))
} with {
  .map!(resume, items, f) => {
    -- Split into chunks, spawn each chunk
    chunks = split_chunks(items, num_threads)
    handles = chunks.iter().map(|c| Spawn.spawn!(|| c.iter().map(f).collect())).collect()
    results = handles.iter().map(Spawn.join!).collect()
    resume(concat(results))
  }
}
-- This handler requires both Parallel and Spawn in its effect row
```

### 6.4 Effect Row of `join!`

`Spawn.join!` propagates the spawned thunk's effects into the caller's effect row:

```camp
-- The thunk's effect row is "remembered" in the Handle type
-- and surfaced when join! is called
h: Handle(a)   -- a = thunk's return type
               -- h also carries the thunk's effect row (type-level)

Spawn.join!(h)  -- effect row includes Spawn + thunk's effects
```

**Implementation note**: The Handle type needs to carry the thunk's effect information at the type level. This is tracked in the typechecker via the Handle's type parameter — `Handle(a)` where `a` is the return type. The effect row of the thunk is propagated to `join!`'s effect row at the call site.

---

## 7. Implementation Strategy

### 7.1 Three-Phase Approach

| Phase | Strategy | Memory Model | Availability |
|-------|----------|-------------|-------------|
| **Phase 3** | Multi-instance (N WASM stores on N OS threads) | Isolated (separate memories) | Works today in wasmtime |
| **Phase 5** | WASM threads (SharedArrayBuffer + atomics) | Shared read-only + thread-local heaps | Requires WASM threads support |
| **Future** | Component model async (stackless coroutines) | Component isolation | Requires Preview 3 |

### 7.2 Phase Selection at Runtime

```
┌──────────────────────────────────────────────────────────┐
│  Runtime Strategy Selection for Spawn                     │
│                                                          │
│  Is WASM threads available in the runtime?               │
│    Yes → Use in-process thread pool (Phase 5 strategy)   │
│    No ↓                                                  │
│                                                          │
│  Is multi-instance support available? (CLI flag)          │
│    Yes → Use multi-instance pool (Phase 3 strategy)     │
│    No ↓                                                  │
│                                                          │
│  Fall back to sequential execution                       │
│  (spawn! runs the thunk immediately on the calling thread)│
└──────────────────────────────────────────────────────────┘
```

---

## 8. Multi-Instance Architecture (Phase 3)

### 8.1 Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Camp CLI (host process, Odin)                                │
│                                                              │
│  Main Thread                          Worker Threads          │
│  ┌─────────────┐                      ┌─────────────┐       │
│  │ Store(main) │                      │ Store(worker0)│      │
│  │             │   spawn!(thunk) →    │  ┌─────────┐ │       │
│  │  ┌───────┐  │ ──────────────────▶ │  │execute  │ │       │
│  │  │ main! │  │   serialize thunk    │  │thunk()  │ │       │
│  │  └───────┘  │   enqueue in pool    │  └────┬────┘ │       │
│  │             │                      │       │      │       │
│  │  join!(h)   │◀────────────────────│  result │      │       │
│  │  ← result   │   return result      │       │      │       │
│  └─────────────┘                      └───────┼──────┘       │
│                                               │              │
│  ┌────────────────────────────────────────────▼──────────┐   │
│  │  Thread Pool Manager                                  │   │
│  │  - Maintains N stores (default: num_cpus)            │   │
│  │  - Work queue: thread-safe FIFO                      │   │
│  │  - Result slots: indexed by handle ID                │   │
│  │  - CAMP_THREADS env var / --threads N flag           │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 8.2 Closure Serialization

To pass a Camp closure from the main instance to a worker instance, we need a serialization format:

```
Serialized Closure Format:
┌──────────────────────────────────────────────┐
│  magic:      u32  (0x4350 = "CP")            │
│  version:    u32  (1)                        │
│  fn_index:   u32  (function table index)     │
│  env_size:   u32  (captured env byte count)  │
│  env_bytes:  [u8; env_size]                  │
│    - flat byte representation of captured     │
│      variables (i32/i64/f32/f64/ptr values)  │
│  effect_mask: u32  (bitmask of thunk's       │
│    effects, for handler wiring)              │
└──────────────────────────────────────────────┘
```

### 8.3 Worker Module

The compiler emits a second WASM module — the "worker" — that:

1. Exports a `run_task` function accepting a pointer to serialized closure data
2. Deserializes the closure (reads fn_index + env)
3. Reconstructs the closure environment
4. Calls the closure function with the environment
5. Serializes the result (or error) back to shared memory
6. Signals completion

### 8.4 Communication Protocol

```
Main Instance                          Worker Instance
─────────────                          ───────────────
spawn!(thunk):
  1. Serialize thunk
  2. Write to shared buffer
  3. Enqueue task in pool
  4. Return Handle(id)
                                       5. Dequeue task
                                       6. Read serialized thunk
                                       7. Deserialize + execute
                                       8. Serialize result
                                       9. Write result to slot
                                      10. Signal completion

join!(handle):
  11. Wait on handle's completion
  12. Read result from slot
  13. Deserialize result
  14. Return result to caller
```

### 8.5 Memory Isolation

Each WASM instance has its own linear memory. Values that cross the instance boundary must be serialized/deserialized. This is a feature, not a bug — it enforces isolation and prevents data races at the runtime level.

**Cost**: Serialization/deserialization overhead for each spawn/join. For large data, this can be significant. Mitigation:
- Pass small closures (closures that capture few variables)
- Pass IDs/indices instead of large data structures
- Use shared read-only memory for large constant data (both instances can read the same memory region)

---

## 9. WASM Threads Architecture (Phase 5)

### 9.1 Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Single WASM Module with SharedArrayBuffer                   │
│                                                              │
│  Main Agent                    Worker Agents                 │
│  ┌────────────┐               ┌────────────┐                │
│  │ Thread 0    │               │ Thread 1-N │                │
│  │ (spawner)   │               │ (workers)  │                │
│  └──────┬─────┘               └──────┬─────┘                │
│         │                            │                       │
│  ┌──────▼────────────────────────────▼───────────────────┐   │
│  │  Shared Memory (SharedArrayBuffer)                     │   │
│  │                                                        │   │
│  │  ┌─────────────────────────────────────────────┐       │   │
│  │  │ Work Queue (atomic lock-free)                │       │   │
│  │  │ - Circular buffer with atomic head/tail      │       │   │
│  │  │ - Each entry: fn_index + env_offset + size   │       │   │
│  │  ├─────────────────────────────────────────────┤       │   │
│  │  │ Thread-Local Heap Regions                     │       │   │
│  │  │ - Per-thread bump allocator regions          │       │   │
│  │  │ - No cross-thread refcounting needed          │       │   │
│  │  ├─────────────────────────────────────────────┤       │   │
│  │  │ Result Slots                                 │       │   │
│  │  │ - Indexed by handle ID                       │       │   │
│  │  │ - Status: pending/complete/failed            │       │   │
│  │  │ - memory.atomic.wait32/notify for blocking   │       │   │
│  │  ├─────────────────────────────────────────────┤       │   │
│  │  │ Closure Environment Data                     │       │   │
│  │  │ - Flat byte arrays for captured variables    │       │   │
│  │  └─────────────────────────────────────────────┘       │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  Requires: WASM threads (SharedArrayBuffer + atomics)        │
│  Requires: COOP/COEP headers in browsers                    │
└──────────────────────────────────────────────────────────────┘
```

### 9.2 Atomic Work Queue

The work-stealing queue uses WASM atomic instructions:

```
Work Queue Operations:
  - enqueue: i32.atomic.rmw.add (increment tail)
  - dequeue: i32.atomic.rmw.sub (decrement count) + i32.atomic.load (read entry)
  - steal:   i32.atomic.rmw.cmpxchg (compare-and-swap on victim's queue)

Synchronization:
  - Wait for work: memory.atomic.wait32 on queue count
  - Signal work available: memory.atomic.notify on queue count
  - Wait for result: memory.atomic.wait32 on result slot status
  - Signal result ready: memory.atomic.notify on result slot status
```

### 9.3 Per-Thread Heap Regions

Each WASM agent (thread) allocates from its own region of shared memory. No cross-thread refcounting is needed because:

1. **Values created by one thread are owned by that thread**
2. **Values that cross thread boundaries are deep-copied** (serialized to shared memory, deserialized by the receiving thread)
3. **Read-only data** (module code, constants, string literals) is shared by all threads without refcounting (immutable data doesn't need RC)

This avoids the complexity of cross-thread reference counting (which would require atomic inc/dec on every reference across thread boundaries).

### 9.4 New IR Nodes

| IR Node | WASM Instruction | Purpose |
|---------|-----------------|---------|
| `IR_Atomic_Load` | `i32.atomic.load` / `i64.atomic.load` | Load from shared memory with ordering |
| `IR_Atomic_Store` | `i32.atomic.store` / `i64.atomic.store` | Store to shared memory with ordering |
| `IR_Atomic_RMW` | `i32.atomic.rmw.add/sub/and/or/xor/xchg/cmpxchg` | Atomic read-modify-write |
| `IR_Atomic_Fence` | `atomic.fence` | Memory fence |
| `IR_Wait` | `memory.atomic.wait32` / `memory.atomic.wait64` | Suspend until notified |
| `IR_Notify` | `memory.atomic.notify` | Wake waiting agents |

### 9.5 Shared Memory Section

When `--threads=N` is specified:

1. The WASM memory declaration gets the `shared` flag
2. Memory must have a `maximum` size (required for shared memory)
3. Data segments are initialized once (in the main agent)
4. Worker agents receive the same memory import (shared)

---

## 10. Fallback Strategy

### 10.1 Sequential Fallback

When no parallel execution is available (single-threaded WASM runtime, no thread pool), the `Spawn` handler falls back to sequential execution:

```camp
-- Sequential Spawn handler:
handle Spawn in {
  h = Spawn.spawn!(|| { heavy_work() })
  result = Spawn.join!(h)
} with {
  .spawn!(resume, thunk) => {
    result = thunk()
    resume(Handle.with_value(result))
  }
  .join!(resume, handle) => {
    resume(handle.value)
  }
  .cancel!(resume, handle) => {
    resume({})
  }
}
```

`spawn!` runs the thunk immediately on the calling thread. `join!` returns immediately because the result is already available. This is semantically correct — just not parallel.

### 10.2 Graceful Degradation

| Environment | Strategy | Parallelism |
|-------------|----------|------------|
| wasmtime CLI, multi-core | Multi-instance thread pool | True parallelism |
| wasmtime CLI, single-core | Multi-instance (1 thread) | Sequential (concurrent scheduling) |
| Browser with COOP/COEP | WASM threads | True parallelism |
| Browser without COOP/COEP | Sequential fallback | Sequential |
| Single-threaded WASM runtime | Sequential fallback | Sequential |
| Component model async (future) | Component async tasks | Concurrent |

---

## 11. Implementation Plan

### Phase 3: Multi-Instance Spawn

| Step | Description | Scope | Depends On |
|------|-------------|-------|------------|
| 3a | `Spawn` effect definition in stdlib | ~40 Camp | Phase 0 (effects working) |
| 3b | Camp CLI thread pool manager | ~400 Odin | — |
| 3c | Worker module generation (second .wasm) | ~200 Odin (codegen) | 3b |
| 3d | Closure serialization/deserialization | ~300 Odin (runtime) | 3c |
| 3e | Spawn handler (dispatch to pool, return Handle) | ~150 Camp + runtime | 3a-d |
| 3f | Join handler (wait on completion, return result) | ~100 Camp + runtime | 3e |
| 3g | Cancel handler (signal cancellation) | ~60 Camp + runtime | 3e |
| 3h | Structured concurrency enforcement (unjoined warning) | ~80 Odin (typecheck) | 3a |
| 3i | E2E tests: true parallel execution benchmarks | ~150 Camp test | 3e-g |

**Total estimated scope**: ~1,480 lines

**Exit criterion**: `Spawn.spawn!` runs a CPU-heavy thunk on a separate core. Two spawned tasks complete ~2x faster than sequential. `Spawn.join!` returns the result. `Spawn.cancel!` stops a running task.

### Phase 5: WASM Threads

| Step | Description | Scope | Depends On |
|------|-------------|-------|------------|
| 5a | Shared memory codegen (shared flag + max size) | ~100 Odin | — |
| 5b | `IR_Atomic_*` IR nodes | ~150 Odin (ir.odin + traversals) | — |
| 5c | Atomic instruction WASM emission | ~250 Odin (codegen) | 5b |
| 5d | Lock-free work-stealing queue (WASM atomics) | ~300 Camp runtime | 5c |
| 5e | Per-thread heap regions | ~200 Odin (runtime) | 5a |
| 5f | Spawn handler migration (multi-instance → in-process) | ~100 Camp runtime | 5d, 5e |
| 5g | COOP/COEP detection/warning for browser targets | ~50 Odin (codegen) | 5a |
| 5h | E2E tests + benchmarks on multi-core | ~200 Camp test | 5f |

**Total estimated scope**: ~1,350 lines

**Exit criterion**: `Spawn.spawn!` and `Parallel.map!` work within a single WASM module using WASM threads. No multi-instance overhead. Falls back gracefully when threads unavailable.

---

## 12. Open Questions

### 12.1 Handle Type Implementation

**Status**: Handle is opaque at the language level, but needs a concrete WASM representation

**Options**:
- **i32 handle ID**: A handle is an index into a result slot array in shared memory. Simple, but requires a lookup table.
- **i32 pointer**: A handle points to a struct in linear memory containing status + result. More direct but requires careful memory management.

**Decision**: Use i32 handle ID with a result slot array. This works for both multi-instance (ID maps to a slot in the host's result map) and WASM threads (ID maps to a slot in shared memory).

### 12.2 Error Propagation Across Instances

**Status**: When a spawned computation throws in a separate WASM instance, how is the error propagated?

**Approach**: The worker instance catches the error, serializes it (tag + payload), writes it to the result slot with a "failed" status. `join!` in the main instance reads the serialized error and re-throws it using `Throw.throw!`.

This requires that thrown values are serializable. For `Throw` with tag unions, serialization is straightforward (tag index + payload bytes).

### 12.3 Nested Spawn

**Status**: Can a spawned computation itself call `Spawn.spawn!`?

**Current design**: Yes, if the spawned computation's handler includes `Spawn`. The nested spawn creates another task in the same thread pool. This enables recursive parallelism (divide-and-conquer).

**Concern**: Deep nesting could exhaust the thread pool. Mitigation: the pool has a maximum queue depth; excess tasks wait in a backlog.

### 12.4 Spawn and Async Interaction

**Status**: Can a spawned computation use `Async`?

**Current design**: Yes, but the spawned computation must handle `Async` internally. The thread pool worker doesn't integrate with the main thread's coroutine scheduler. Each worker runs its own coroutine scheduler if it encounters `Async` effects.

**This means**: A spawned task that does async I/O gets its own I/O polling loop (calling `wasi:io/poll` from the worker thread). This works because `wasi:io/poll` is thread-safe in wasmtime.

---

## 13. References

| Resource | URL | Relevance |
|----------|-----|-----------|
| WASM Threads Proposal | https://github.com/WebAssembly/threads | SharedArrayBuffer + atomics; Phase 4; the foundation for Phase 5 |
| shared-everything-threads | https://github.com/WebAssembly/shared-everything-threads | Future: sharing tables + globals; Phase 1 |
| Wasmtime Threads | https://docs.wasmtime.dev/examples-threads.html | Multi-store parallel execution pattern |
| Rayon (Rust) | https://github.com/rayon-rs/rayon | Work-stealing parallel iterator; design reference |
| Scoped Threads (Rust) | https://doc.rust-lang.org/std/thread/fn.scope.html | Structured concurrency model for threads |
| Swift Structured Concurrency | https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md | Structured concurrency enforcement |

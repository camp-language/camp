# Multi-Instance Parallelism Design Specification

> *"The simplest parallelism that works today."*

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Camp CLI Thread Pool](#3-camp-cli-thread-pool)
4. [Worker Module Generation](#4-worker-module-generation)
5. [Closure Serialization](#5-closure-serialization)
6. [Spawn Handler via Multi-Instance](#6-spawn-handler-via-multi-instance)
7. [Parallel Handler via Multi-Instance](#7-parallel-handler-via-multi-instance)
8. [Performance Considerations](#8-performance-considerations)
9. [Implementation Plan](#9-implementation-plan)
10. [References](#10-references)

---

## 1. Overview

This spec defines how Camp implements true parallelism using **multiple WASM instances on multiple OS threads** — the most practical parallelism pattern available in wasmtime today. No WASM threads proposal required. No SharedArrayBuffer required. No COOP/COEP headers required.

**Why multi-instance?**:

| Approach | Works Today? | Requires | Performance |
|----------|-------------|---------|-------------|
| **Multi-instance** | Yes | wasmtime (any version) | Good (N cores → ~Nx throughput) |
| WASM threads | Yes, but Tier 2 | SharedArrayBuffer + COOP/COEP (browsers) | Better (lower overhead per task) |
| Component model async | No | Preview 3 (not yet released) | TBD |

Multi-instance parallelism works by:
1. The Camp CLI creates N WASM `Store`s, each on its own OS thread
2. Each store instantiates the same compiled module (or a "worker" variant)
3. Work is distributed to stores via a thread-safe queue
4. Results are collected and returned to the main instance

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Camp CLI (Odin host process)                                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Thread Pool Manager                                      │   │
│  │                                                            │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │   │
│  │  │ Worker 0 │  │ Worker 1 │  │ Worker 2 │  ...          │   │
│  │  │ OS Thread│  │ OS Thread│  │ OS Thread│               │   │
│  │  │ ┌──────┐ │  │ ┌──────┐ │  │ ┌──────┐ │               │   │
│  │  │ │Store │ │  │ │Store │ │  │ │Store │ │               │   │
│  │  │ │ ┌──┐ │ │  │ │ ┌──┐ │ │  │ │ ┌──┐ │ │               │   │
│  │  │ │ │Mod│ │ │  │ │ │Mod│ │ │  │ │ │Mod│ │ │               │   │
│  │  │ │ └──┘ │ │  │ │ └──┘ │ │  │ │ └──┘ │ │               │   │
│  │  │ └──────┘ │  │ └──────┘ │  │ └──────┘ │               │   │
│  │  └──────┬───┘  └──────┬───┘  └──────┬───┘               │   │
│  │         │              │              │                    │   │
│  │  ┌──────▼──────────────▼──────────────▼───────────────┐   │   │
│  │  │  Work Queue (thread-safe MPMC channel)             │   │   │
│  │  │  - Serialized closures waiting to be executed      │   │   │
│  │  │  - FIFO ordering within priority levels            │   │   │
│  │  └────────────────────────────────────────────────────┘   │   │
│  │                                                            │   │
│  │  ┌────────────────────────────────────────────────────┐   │   │
│  │  │  Result Map (thread-safe hashmap)                  │   │   │
│  │  │  - task_id → { status, result_bytes }               │   │   │
│  │  │  - Completed tasks store serialized results         │   │   │
│  │  └────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────┐                                           │
│  │  Main Instance    │  ← user's main! runs here               │
│  │  (Store on main   │  ← Spawn/Parallel handlers dispatch    │
│  │   thread)         │     to the thread pool                   │
│  └──────────────────┘                                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Camp CLI Thread Pool

### 3.1 Configuration

| Source | Priority | Default |
|--------|----------|---------|
| `--threads=N` CLI flag | Highest | — |
| `CAMP_THREADS` env var | Medium | — |
| `os.thread_count()` (runtime detection) | Lowest | Number of CPU cores |

### 3.2 Thread Pool Lifecycle

```
1. Camp CLI parses --threads=N (or detects core count)
2. Create N worker threads
3. For each worker thread:
   a. Create a wasmtime::Store
   b. Create a wasmtime::Engine (shared across all stores)
   c. Compile the worker module (shared across all stores)
   d. Instantiate the worker module in the store
   e. Start the worker loop
4. Main thread runs the user's main! function in its own store
5. When main! completes:
   a. Signal all workers to stop
   b. Wait for all workers to finish current tasks
   c. Join all worker threads
   d. Return main!'s exit code
```

### 3.3 Worker Loop

```
worker_loop:
  1. Dequeue task from work queue (blocking wait)
  2. Deserialize the closure (fn_index + env_bytes)
  3. Call the worker module's run_task function with the closure data
  4. The run_task function:
     a. Reconstructs the closure environment
     b. Calls the closure function
     c. Serializes the result (or error)
     d. Returns the result pointer and size
  5. Write result to result map (task_id → result_bytes)
  6. Notify the main instance (via condition variable or polling)
  7. Go to step 1
```

### 3.4 Odin Implementation Sketch

```odin
Worker_Context :: struct {
    store:      wasm.Store,
    instance:   wasm.Instance,
    run_task:   wasm.Func,
    work_queue: ^Work_Queue,
    result_map: ^Result_Map,
}

worker_main :: proc(ctx: ^Worker_Context) {
    for {
        task, ok := ctx.work_queue.dequeue()
        if !ok do break  // queue closed

        result := execute_task(ctx, task)
        ctx.result_map.store(task.id, result)
        ctx.result_map.notify(task.id)
    }
}
```

---

## 4. Worker Module Generation

### 4.1 Two-Module Compilation

The Camp compiler emits two WASM modules when parallelism is needed:

1. **Main module**: Contains `main!` and all user functions. Runs in the main instance.
2. **Worker module**: Contains a `run_task` export that can execute any serialized closure. Contains the same function definitions as the main module (same function table).

### 4.2 Worker Module Structure

```wasm
(module $camp-worker
  ;; Same imports as main module (wasi, camp runtime)
  (import "wasi_snapshot_preview1" "fd_write" ...)

  ;; Same function definitions as main module
  ;; (all user-defined functions are included)
  (func $user_fn_0 ...)
  (func $user_fn_1 ...)

  ;; Function table (same as main module)
  (table $functable N funcref)
  (elem $table_offset
    (func $user_fn_0 $user_fn_1 ...))

  ;; Shared memory (optional, for shared read-only data)
  ;; (memory $memory (export "memory") 1)

  ;; Worker entry point
  (func $run_task (export "run_task")
    (param $closure_ptr i32) (param $closure_len i32)
    (result i32)  ;; result pointer

    ;; 1. Read fn_index from closure_ptr
    ;; 2. Read env_bytes from closure_ptr + 4
    ;; 3. Reconstruct closure environment
    ;; 4. Call fn_table[fn_index](env_ptr)
    ;; 5. Serialize result
    ;; 6. Return result pointer
    ...)
)
```

### 4.3 Module Sharing

Both modules contain the same function definitions. To avoid duplicating code size:

- **Same Engine**: All stores share the same `wasmtime::Engine`, which caches compiled module code. The second instantiation reuses the compiled code.
- **Same Module binary**: If the main module and worker module are identical (the worker just adds `run_task`), a single binary can be instantiated in all stores.

**Optimization**: In practice, the compiler can emit a single module that serves as both main and worker. The `_start` function only runs in the main instance. Workers call `run_task` instead.

---

## 5. Closure Serialization

### 5.1 Format

```
Serialized Closure:
┌───────────────────────────────────────┐
│  magic:      u32  (0x4350 = "CP")     │
│  version:    u32  (1)                 │
│  fn_index:   u32  (table index)       │
│  env_size:   u32  (byte count)        │
│  env_bytes:  [u8; env_size]           │
│    - i32 values: 4 bytes each         │
│    - i64 values: 8 bytes each         │
│    - f32 values: 4 bytes each         │
│    - f64 values: 8 bytes each         │
│    - pointers:   4 bytes each (i32)   │
│  effect_row: u32  (bitmask)           │
└───────────────────────────────────────┘
```

### 5.2 Serialization Rules

| Camp Type | Serialized As | Notes |
|-----------|--------------|-------|
| `I8`..`I64`, `U8`..`U64` | Direct integer bytes | Little-endian |
| `F32`, `F64` | Direct float bytes | IEEE 754 |
| `Bool` | 1 byte (0 or 1) | — |
| `Str` | NOT serializable across instances | Must pass by value (copy to shared buffer) or by index |
| `List(a)` | NOT serializable across instances | Must pass by value (copy all elements) |
| Records | Flat byte sequence (field by field) | Only if all fields are serializable |
| Tag unions | Tag index + payload bytes | Only if payload is serializable |
| Closures | fn_index + env_bytes | The whole point of serialization |

### 5.3 String and List Handling

Strings and lists are heap-allocated in WASM linear memory. They cannot be passed across instances by pointer because each instance has its own memory.

**Options**:

1. **Deep copy**: Serialize the string/list bytes into the closure's env. The worker deserializes them into its own heap. This is correct but expensive for large data.

2. **Index reference**: Store the string/list in a shared buffer (host-managed). Pass an index in the closure. The worker looks up the data from the shared buffer. This avoids copying but requires host coordination.

3. **Shared memory** (Phase 5): When WASM threads are available, all instances share memory and can pass pointers directly.

**Phase 3 strategy**: Use deep copy for simplicity. For hot paths, use index references (host-managed shared buffer).

### 5.4 Effect Row in Serialization

The `effect_row` bitmask tells the worker which effects the thunk may perform. This allows the worker to install the correct handlers:

| Bit | Effect | Worker Handler |
|-----|--------|---------------|
| 0 | `Throw` | Install Throw handler that serializes errors back |
| 1 | `Console` | Install Console handler that calls WASI fd_write |
| 2 | `File` | Install File handler that calls WASI filesystem |
| 3 | `Async` | Install Async handler (worker's own scheduler) |
| 4 | `Parallel` | Error — nested parallelism not supported in Phase 3 |
| 5 | `Spawn` | Error — nested spawn not supported in Phase 3 |

---

## 6. Spawn Handler via Multi-Instance

### 6.1 Handler Implementation

The `Spawn` handler in the main instance dispatches to the thread pool:

```camp
-- Spawn handler (runs in main instance):
handle Spawn in {
  h = Spawn.spawn!(|| { fibonacci(40) })
  result = Spawn.join!(h)
} with {
  .spawn!(resume, thunk) => {
    -- Serialize the thunk closure
    serialized = camp_serialize_closure(thunk)
    -- Submit to thread pool
    handle_id = camp_thread_pool_submit(serialized)
    -- Return handle to caller
    resume(Handle(handle_id))
  }
  .join!(resume, handle) => {
    -- Wait for the thread pool result
    camp_thread_pool_wait(handle.id)
    -- Read the result
    result_bytes = camp_thread_pool_result(handle.id)
    -- Deserialize the result
    result = camp_deserialize_value(result_bytes)
    resume(result)
  }
  .cancel!(resume, handle) => {
    camp_thread_pool_cancel(handle.id)
    resume({})
  }
}
```

### 6.2 Handle ID Mapping

Handle IDs are assigned by the thread pool manager. They are simple incrementing integers:

- Handle 0: Main coroutine (in async runtime)
- Handles 1..N: Spawned tasks in the thread pool
- Handle IDs are shared between the main instance and the pool manager

### 6.3 Join Blocking

`Spawn.join!(handle)` blocks the main instance's WASM execution until the result is available. Options:

1. **Polling**: The main instance periodically checks the result map. This requires wasmtime's async support (`call_async` + fuel-based yield interval).

2. **Host callback**: The `join!` handler calls a host function that blocks the OS thread until the result is ready. This is simpler but prevents the main instance from doing other work while waiting.

**Phase 3 strategy**: Use host callback (blocking). The main instance is single-threaded — if it's waiting on a join, it can't do anything else. Use `Async` for concurrent work; use `Spawn` for parallel work where blocking on join is expected.

---

## 7. Parallel Handler via Multi-Instance

### 7.1 Chunk-Based Work Distribution

The `Parallel` handler uses `Spawn` to distribute work:

```camp
-- Parallel.map! handler using Spawn:
.map!(resume, items, f) => {
  -- Determine chunk size (heuristic)
  chunk_size = max(1, items.len() / num_threads)
  -- Split items into chunks
  chunks = split_chunks(items, chunk_size)
  -- Spawn each chunk as a separate task
  handles = chunks.iter().map(|chunk| {
    Spawn.spawn!(|| {
      chunk.iter().map(f).collect()
    })
  }).collect()
  -- Wait for all chunks to complete
  results = handles.iter().map(Spawn.join!).collect()
  -- Concatenate chunk results in order
  resume(concat(results))
}
```

### 7.2 Chunk Size Heuristic

| Collection Size | Threads | Chunk Size | Rationale |
|----------------|---------|------------|-----------|
| < 100 | N | 100 (all in one chunk) | Overhead of parallelism > benefit |
| 100..10,000 | N | ceil(len / (N * 4)) | 4 chunks per thread for load balancing |
| > 10,000 | N | ceil(len / (N * 8)) | 8 chunks per thread for better balance |

**Goal**: Enough chunks to keep all threads busy (work stealing), not so many that scheduling overhead dominates.

### 7.3 Parallel.reduce! Handler

```camp
.reduce!(resume, items, init, f) => {
  -- Split into N chunks
  chunks = split_chunks(items, ceil(items.len() / num_threads))
  -- Reduce each chunk in parallel
  handles = chunks.iter().map(|chunk| {
    Spawn.spawn!(|| {
      chunk.iter().fold(init, f)
    })
  }).collect()
  partials = handles.iter().map(Spawn.join!).collect()
  -- Combine partial results (tree reduce)
  result = partials.iter().fold(init, f)
  resume(result)
}
```

---

## 8. Performance Considerations

### 8.1 Overhead Sources

| Source | Cost | Mitigation |
|--------|------|-----------|
| Closure serialization | ~1-10 µs per closure | Keep closures small; avoid passing large data |
| WASM instantiation | ~0.1-1 ms per worker (one-time) | Workers are long-lived; instantiate once |
| Work queue enqueue/dequeue | ~0.1-1 µs per task | Thread-safe MPMC channel (lock-free) |
| Result deserialization | ~1-10 µs per result | Keep results small; use indices for large data |
| Cross-instance data copy | ~proportional to data size | Share read-only data via host buffer |

### 8.2 Break-Even Point

Parallelism via multi-instance is beneficial when:

```
task_time >> serialization_time + scheduling_overhead
```

For CPU-heavy tasks (matrix multiply, sort, parse), task_time is typically > 1ms, so the overhead (~0.01-0.1 ms) is negligible.

For very fine-grained tasks (add two numbers), the overhead exceeds the benefit. Use sequential execution for these.

**Chunk size guidance**: Each chunk should take at least ~0.1 ms of CPU time. For a function that takes ~1 µs per element, a chunk of 100+ elements is needed to amortize overhead.

### 8.3 Scalability

| Threads | Expected Speedup | Observed (typical) |
|---------|-----------------|-------------------|
| 1 | 1x (sequential) | 1x |
| 2 | 2x | 1.8-1.95x |
| 4 | 4x | 3.5-3.8x |
| 8 | 8x | 6.5-7.5x |
| 16 | 16x | 12-14x |

Diminishing returns from: scheduling overhead, memory bandwidth contention, OS thread scheduling overhead.

---

## 9. Implementation Plan

### Phase 3: Multi-Instance Spawn

| Step | Description | Scope (lines) | Depends On |
|------|-------------|---------------|------------|
| 3a | Camp CLI `--threads=N` flag + `CAMP_THREADS` env var | ~50 Odin | — |
| 3b | Thread pool manager (create stores, start workers) | ~250 Odin | 3a |
| 3c | Worker loop (dequeue, execute, return result) | ~100 Odin | 3b |
| 3d | Worker module generation (single module + `run_task` export) | ~200 Odin (codegen) | — |
| 3e | Closure serialization format + implementation | ~200 Odin (runtime) | — |
| 3f | Closure deserialization in worker | ~100 Odin (runtime) | 3e |
| 3g | Spawn handler (serialize, submit, wait, deserialize) | ~150 Odin (runtime) | 3e, 3b |
| 3h | Parallel handler (chunk, spawn, join, concatenate) | ~150 Odin (runtime) | 3g |
| 3i | String/list cross-instance handling (deep copy) | ~100 Odin (runtime) | 3e |
| 3j | Error propagation across instances (serialize Throw) | ~80 Odin (runtime) | 3e |
| 3k | Structured concurrency (join/cancel tracking) | ~80 Odin | 3b |
| 3l | E2E tests + benchmarks | ~200 Camp | 3g, 3h |

**Total estimated scope**: ~1,560 lines

---

## 10. References

| Resource | URL | Relevance |
|----------|-----|-----------|
| Wasmtime Threads Example | https://github.com/bytecodealliance/wasmtime/blob/main/examples/threads.rs | Multi-store parallel execution pattern |
| Wasmtime API: Store | https://docs.wasmtime.dev/api/wasm/struct.Store.html | Store is Send but not Sync — one per thread |
| Wasmtime API: Engine | https://docs.wasmtime.dev/api/wasm/struct.Engine.html | Engine is Send + Sync — shared across threads |
| Wasmtime API: Module | https://docs.wasmtime.dev/api/wasm/struct.Module.html | Module is Send + Sync — shared across threads |

# WASM Threads Optimization Design Specification

> *"When you can share memory, share it. When you can't, copy."*

## Table of Contents

1. [Overview](#1-overview)
2. [WASM Threads Landscape](#2-wasm-threads-landscape)
3. [Architecture](#3-architecture)
4. [Shared Memory Layout](#4-shared-memory-layout)
5. [Atomic Work Queue](#5-atomic-work-queue)
6. [Per-Thread Heap Regions](#6-per-thread-heap-regions)
7. [New IR Nodes](#7-new-ir-nodes)
8. [WASM Codegen Changes](#8-wasm-codegen-changes)
9. [Fallback and Detection](#9-fallback-and-detection)
10. [Implementation Plan](#10-implementation-plan)
11. [References](#11-references)

---

## 1. Overview

This spec defines how Camp migrates from multi-instance parallelism (Phase 3) to in-process parallelism using the WASM threads proposal (Phase 5). WASM threads enable all WASM agents to share a single linear memory with atomic operations, eliminating the serialization/deserialization overhead of multi-instance parallelism.

**Why this matters**: Multi-instance parallelism requires serializing closures and results across instance boundaries — ~1-10 µs per task. With WASM threads, closures can be passed by pointer. Results are written directly to shared memory. Overhead drops to ~0.01-0.1 µs per task.

**When this is available**:
- **wasmtime**: Tier 2 support (all Cranelift targets except Pulley). Works today.
- **Browsers**: Requires COOP/COEP headers for SharedArrayBuffer. Works in Chrome, Firefox, Safari.
- **Node.js**: Works (no header restrictions).

---

## 2. WASM Threads Landscape

### 2.1 WASM Threads Proposal (Phase 4 — Standardized)

The proposal adds three capabilities:

1. **Shared Linear Memory**: Memory with `shared=true` flag. All agents in an agent cluster can access it. Requires `maximum` size (no dynamic growth beyond pre-allocated max).

2. **Atomic Instructions**: Sequentially consistent atomic operations on shared memory:
   - `i32.atomic.load` / `i64.atomic.load`
   - `i32.atomic.store` / `i64.atomic.store`
   - `i32.atomic.rmw.add` / `sub` / `and` / `or` / `xor` / `xchg` / `cmpxchg`
   - `i64.atomic.rmw.add` / `sub` / `and` / `or` / `xor` / `xchg` / `cmpxchg`
   - `atomic.fence`

3. **Wait/Notify**: Thread synchronization primitives:
   - `memory.atomic.wait32` / `wait64`: Block until notified or timeout
   - `memory.atomic.notify`: Wake blocked agents

### 2.2 What Threads Does NOT Provide

The threads proposal does NOT define:
- **Thread creation**: No `thread.spawn` instruction. The embedder (browser, wasmtime) creates agents.
- **Shared tables/globals**: Only memory is shared. Tables (function references) and globals are per-agent.
- **Shared stack**: Each agent has its own stack.

### 2.3 Thread Creation in Wasmtime

Wasmtime does not provide a WASI thread-spawning API. To create WASM agents:

1. Create N OS threads (via `core:thread` in Odin)
2. Each OS thread creates a `Store` with the shared memory import
3. Each OS thread instantiates the module
4. All instances share the same `Memory` object (via import)

```odin
// Odin host code (sketch)
shared_mem := wasm.Memory.new(engine, wasm.Memory.Config{shared = true, min = 1, max = 256})

for i in 0..<num_threads {
    thread.spawn(proc() {
        store := wasm.Store.new(engine)
        instance := linker.instantiate(store, module)  // same module, same shared_mem
        // Call the worker entry function
    })
}
```

### 2.4 Browser Requirements (COOP/COEP)

For WASM threads in browsers, the page must be served with:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Without these headers, `SharedArrayBuffer` is not available (Spectre mitigation since 2018).

**Implication**: Camp programs targeting browsers with WASM threads must be served with these headers. The Camp documentation should include a deployment guide.

---

## 3. Architecture

### 3.1 In-Process Thread Pool

```
┌──────────────────────────────────────────────────────────────────┐
│  Single WASM Module with SharedArrayBuffer                       │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Shared Memory (shared=true, max=N pages)                │    │
│  │                                                           │    │
│  │  ┌─────────────────────────────────────────────────┐     │    │
│  │  │  Module Code + Constants (read-only)             │     │    │
│  │  │  - Function bodies (shared by all agents)        │     │    │
│  │  │  - String constants, numeric literals            │     │    │
│  │  ├─────────────────────────────────────────────────┤     │    │
│  │  │  Atomic Work Queue                              │     │    │
│  │  │  - Circular buffer with atomic head/tail ptrs   │     │    │
│  │  │  - Each entry: fn_index + env_offset + result   │     │    │
│  │  ├─────────────────────────────────────────────────┤     │    │
│  │  │  Per-Thread Heap Regions                        │     │    │
│  │  │  - Thread 0: [offset_0, offset_0 + region_size) │     │    │
│  │  │  - Thread 1: [offset_1, offset_1 + region_size) │     │    │
│  │  │  - Each thread allocates from its own region     │     │    │
│  │  ├─────────────────────────────────────────────────┤     │    │
│  │  │  Result Slots                                  │     │    │
│  │  │  - Array of { status: u32, result_offset: u32 }  │     │    │
│  │  │  - Indexed by handle ID                         │     │    │
│  │  ├─────────────────────────────────────────────────┤     │    │
│  │  │  Closure Environment Pool                       │     │    │
│  │  │  - Flat byte arrays for captured variables      │     │    │
│  │  │  - Allocated from shared memory (thread-safe)   │     │    │
│  │  └─────────────────────────────────────────────────┘     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ Agent 0  │  │ Agent 1  │  │ Agent 2  │  ... (N agents)      │
│  │ (main)   │  │ (worker) │  │ (worker) │                       │
│  │ Own stack│  │ Own stack│  │ Own stack│                       │
│  │ Own table│  │ Own table│  │ Own table│                       │
│  └──────────┘  └──────────┘  └──────────┘                      │
│  All share the same Memory object                               │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Memory sharing | All agents share one `Memory` | Required by WASM threads proposal; enables fast data passing |
| Thread-local heaps | Each agent allocates from its own region | Avoids cross-thread refcounting; eliminates data races in allocator |
| Closures by pointer | Closures pass env_offset, not serialized bytes | No serialization needed; pointer in shared memory is valid for all agents |
| Function tables NOT shared | Each agent has its own function table | WASM threads doesn't share tables; each agent instantiates the same module (same fn indices) |
| Synchronization via atomics | Work queue + result slots use atomic ops | Standard lock-free patterns; maps directly to WASM atomic instructions |

---

## 4. Shared Memory Layout

### 4.1 Region Map

```
Address Space (shared memory):
┌──────────────────────────────┐  0x0000_0000
│  Module Data Segment         │  Read-only: constants, string literals
│  (initialized at startup)    │
├──────────────────────────────┤  0x0010_0000 (approx)
│  Atomic Work Queue           │  Circular buffer: head, tail, entries[]
│  Size: queue_capacity * 16B │
├──────────────────────────────┤  0x0010_0000 + queue_size
│  Result Slots                │  Array: { status: u32, result: u32 }[]
│  Size: max_handles * 8B     │
├──────────────────────────────┤  0x0010_0000 + queue_size + slots_size
│  Thread-Local Heap Regions   │  Per-thread bump allocators
│  Region 0: [start_0, end_0) │  Each region: ~1MB (configurable)
│  Region 1: [start_1, end_1) │
│  Region 2: [start_2, end_2) │
│  ...                         │
├──────────────────────────────┤  heap_regions_end
│  Closure Environment Pool    │  Shared bump allocator for env data
│                              │  (atomic offset increment)
├──────────────────────────────┤
│  Free space (grows as needed)│  Available for future use
└──────────────────────────────┘  max memory size
```

### 4.2 Memory Configuration

```wasm
;; Shared memory declaration (requires maximum)
(memory $memory (export "memory") 1 65536 shared)
;;                                    ^^    ^^^^^^
;;                                    min   max (256MB / 4KB pages)
```

The `shared` flag enables:
- `SharedArrayBuffer` in browsers
- Atomic instructions in WASM
- Multi-agent access in wasmtime

---

## 5. Atomic Work Queue

### 5.1 Data Structure

```
Work Queue Layout:
┌──────────────────────────────────────────────────────────┐
│  head:       u32 (atomic)  — index of next task to dequeue │
│  tail:       u32 (atomic)  — index of next slot to enqueue│
│  capacity:   u32           — ring buffer size              │
│  padding:    u32           — cache line alignment          │
│                                                            │
│  entries[0]: { fn_index: u32, env_offset: u32,            │
│               result_slot: u32, flags: u32 }               │
│  entries[1]: { ... }                                      │
│  entries[2]: { ... }                                      │
│  ...                                                       │
│  entries[capacity-1]: { ... }                              │
└──────────────────────────────────────────────────────────┘
```

### 5.2 Enqueue Operation

```
enqueue(fn_index, env_offset, result_slot):
  1. current_tail = i32.atomic.rmw.add(tail_addr, 1)  ;; atomic increment
  2. slot = current_tail % capacity
  3. entries[slot] = { fn_index, env_offset, result_slot, 0 }
  4. memory.atomic.notify(tail_addr, 1)  ;; wake one waiting worker
```

### 5.3 Dequeue Operation

```
dequeue() -> (fn_index, env_offset, result_slot):
  1. current_head = i32.atomic.rmw.add(head_addr, 1)  ;; atomic increment
  2. slot = current_head % capacity
  3. spin-wait until entries[slot].flags != 0  ;; entry is written
  4. entry = entries[slot]
  5. return (entry.fn_index, entry.env_offset, entry.result_slot)
```

### 5.4 Work-Stealing (Optional Enhancement)

For load balancing, idle workers can steal tasks from other workers' local queues. This requires:
- Each worker has a local deque (double-ended queue) in shared memory
- Stealing uses `i32.atomic.rmw.cmpxchg` to atomically pop from the victim's deque tail
- The victim pops from its own deque head (no contention)

This is the same design as Rust's `rayon` work-stealing scheduler.

---

## 6. Per-Thread Heap Regions

### 6.1 Why Per-Thread Heaps

Each WASM agent allocates from its own region of shared memory. This avoids:
- **Cross-thread refcounting**: Perceus RC operations (`camp_dup`/`camp_drop`) don't need atomic increments
- **Allocator contention**: No lock or atomic needed for allocation within a thread's region
- **False sharing**: Each thread's data is in its own cache lines

### 6.2 Region Layout

```
Thread 0's Heap Region:
┌──────────────────────────────────┐
│  bump_offset: u32 (non-atomic)   │  Only thread 0 writes this
│  region_start: u32               │  Start of the region
│  region_end: u32                 │  End of the region
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  allocated data...               │  Camp values allocated here
│  free space...                   │
└──────────────────────────────────┘
```

### 6.3 Allocation Within a Region

```wasm
;; camp_alloc_region(region_ptr, size) -> ptr
;; Fast bump allocation within a thread's own region
(func $camp_alloc_region
  (param $region_ptr i32) (param $size i32) (result i32)
  (local $offset i32)
  (local.set $offset
    (i32.load (local.get $region_ptr)))          ;; bump_offset (non-atomic — own thread)
  ;; Check if enough space
  (if (i32.gt_u
    (i32.add (local.get $offset) (local.get $size))
    (i32.load offset=4 (local.get $region_ptr)))  ;; region_end
    (then (return (i32.const 0))))                 ;; out of space
  ;; Update bump offset
  (i32.store (local.get $region_ptr)
    (i32.add (local.get $offset) (local.get $size)))
  ;; Return pointer to allocated memory
  (local.get $offset))
```

### 6.4 Values That Cross Thread Boundaries

When a value is created by one thread but consumed by another:

1. **Deep copy**: The sending thread copies the value's bytes into the closure environment (in shared memory). The receiving thread reads the bytes and creates a new value in its own heap region.

2. **Immutable read-only sharing**: Values in the module's data segment (constants, string literals) are shared by all threads without copying. Since they're immutable, no refcounting is needed.

3. **Transfer ownership**: The sending thread increments the refcount to 1 (from 0), writes the value pointer to the closure env. The receiving thread takes ownership (refcount stays 1). The sending thread must not access the value after transfer.

**Phase 5 strategy**: Use deep copy for correctness. Optimize with ownership transfer later.

---

## 7. New IR Nodes

### 7.1 Atomic IR Nodes

| IR Node | Fields | WASM Instruction |
|---------|--------|-----------------|
| `IR_Atomic_Load` | `ptr: IR_Expr, offset: u32, width: Atomic_Width, ordering: Memory_Ordering` | `i32.atomic.load` / `i64.atomic.load` |
| `IR_Atomic_Store` | `ptr: IR_Expr, offset: u32, value: IR_Expr, width: Atomic_Width, ordering: Memory_Ordering` | `i32.atomic.store` / `i64.atomic.store` |
| `IR_Atomic_RMW` | `ptr: IR_Expr, offset: u32, value: IR_Expr, op: Atomic_Op, width: Atomic_Width, ordering: Memory_Ordering` | `i32.atomic.rmw.<op>` |
| `IR_Atomic_Fence` | `ordering: Memory_Ordering` | `atomic.fence` |
| `IR_Wait` | `ptr: IR_Expr, offset: u32, expected: IR_Expr, timeout: IR_Expr, width: Atomic_Width` | `memory.atomic.wait32` / `wait64` |
| `IR_Notify` | `ptr: IR_Expr, offset: u32, count: IR_Expr` | `memory.atomic.notify` |

### 7.2 Supporting Types

```odin
Atomic_Width :: enum {
    B1,  -- 1 byte (i32 atomic with 8-bit alignment)
    B2,  -- 2 bytes
    B4,  -- 4 bytes (i32)
    B8,  -- 8 bytes (i64)
}

Atomic_Op :: enum {
    Add,
    Sub,
    And,
    Or,
    Xor,
    Xchg,
    CmpXchg,
}

Memory_Ordering :: enum {
    SeqCst,  -- Sequentially consistent (the only ordering in WASM)
}
```

### 7.3 IR Traversal

Every mid-end pass that traverses `IR_Expr` must handle the new variants:
- `effect_lower.odin`
- `closure_convert.odin`
- `cps.odin`
- `rc.odin`

For Phase 5, atomic IR nodes are only generated by the runtime codegen (work queue, result slots), not by user code. Users interact with parallelism via the `Spawn` and `Parallel` effects — the runtime generates the atomic operations internally.

---

## 8. WASM Codegen Changes

### 8.1 Shared Memory Declaration

When `--threads=N` is specified:

```wasm
;; Before (single-threaded):
(memory $memory (export "memory") 1)

;; After (multi-threaded):
(memory $memory (export "memory") 1 65536 shared)
```

Changes in `codegen.odin`:
- Memory section: set `shared` flag
- Memory section: require `maximum` field
- Compute `maximum` based on `--max-memory` flag or default (256 MB)

### 8.2 Atomic Instruction Emission

| IR Node | WASM Opcode | Operands |
|---------|------------|----------|
| `IR_Atomic_Load{.B4, .SeqCst}` | `0x FE 10` | `align=0, offset` |
| `IR_Atomic_Load{.B8, .SeqCst}` | `0x FE 11` | `align=0, offset` |
| `IR_Atomic_Store{.B4, .SeqCst}` | `0x FE 17` | `align=0, offset` |
| `IR_Atomic_Store{.B8, .SeqCst}` | `0x FE 18` | `align=0, offset` |
| `IR_Atomic_RMW{.Add, .B4, .SeqCst}` | `0x FE 1E` | `align=0, offset` |
| `IR_Atomic_RMW{.CmpXchg, .B4, .SeqCst}` | `0x FE 48` | `align=0, offset` |
| `IR_Atomic_Fence{.SeqCst}` | `0x FE 50` | (none) |
| `IR_Wait{.B4}` | `0x FE 52` | `align=0, offset` |
| `IR_Notify` | `0x FE 54` | `align=0, offset` |

### 8.3 Worker Entry Function

The worker entry function is generated when `--threads=N` is specified:

```wasm
(func $camp_worker_entry (export "camp_worker_entry")
  (local $task_fn i32)
  (local $task_env i32)
  (local $task_result_slot i32)

  (block $break
    (loop $loop
      ;; Dequeue a task from the atomic work queue
      (call $camp_dequeue_task)
      (local.set $task_fn)
      ;; If fn_index == 0, no more work — exit
      (br_if $break (i32.eqz (local.get $task_fn)))

      ;; Get env and result slot from the queue entry
      ;; (already set by camp_dequeue_task)

      ;; Call the task function with its environment
      (call_indirect (type $task_sig)
        (local.get $task_env)
        (local.get $task_fn))

      ;; Store result in the result slot
      ;; (already done by the task function)

      ;; Loop back for more work
      (br $loop))))
```

---

## 9. Fallback and Detection

### 9.1 Runtime Detection

The Camp runtime should detect whether WASM threads are available:

1. **wasmtime**: Try to create a shared `Memory`. If it fails, fall back to multi-instance.
2. **Browser**: Check if `SharedArrayBuffer` is defined. If not, fall back to sequential.
3. **Node.js**: Always available (no header restrictions).

### 9.2 Graceful Degradation

```
┌─────────────────────────────────────────────────────────────┐
│  Parallelism Strategy Selection (at runtime)                 │
│                                                              │
│  1. Try WASM threads (shared memory + atomics)              │
│     └─ Fails? → Fall back to multi-instance (Phase 3)      │
│                                                              │
│  2. Try multi-instance (N stores on N threads)              │
│     └─ Fails? → Fall back to sequential (Phase 2)          │
│                                                              │
│  3. Sequential handler (always works)                       │
│                                                              │
│  The user's code is the same regardless of strategy.        │
│  Only the handler implementation changes.                    │
└─────────────────────────────────────────────────────────────┘
```

### 9.3 Compile-Time Flag

The `--threads=N` flag controls code generation:

| Flag | Codegen |
|------|---------|
| `--threads=1` (or absent) | Single-threaded module (no shared memory, no atomics) |
| `--threads=N` (N > 1) | Multi-threaded module (shared memory, atomics, worker entry) |

### 9.4 COOP/COEP Warning

For browser targets, emit a warning if `--threads=N` is specified:

```
warning: WASM threads require COOP/COEP headers in browsers.
  Add these HTTP headers to your server:
    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp
  See: https://web.dev/coop-coep/
```

---

## 10. Implementation Plan

### Phase 5: WASM Threads

| Step | Description | Scope (lines) | Depends On |
|------|-------------|---------------|------------|
| 5a | Shared memory codegen (shared flag + maximum) | ~80 Odin | — |
| 5b | `IR_Atomic_*` node types + Odin types | ~100 Odin | — |
| 5c | IR traversal for atomic nodes (all mid-end passes) | ~150 Odin | 5b |
| 5d | Atomic instruction WASM emission | ~200 Odin | 5b |
| 5e | Work queue data structure in shared memory | ~150 Odin | 5d |
| 5f | Enqueue/dequeue operations (atomic) | ~150 Odin | 5e |
| 5g | Worker entry function codegen | ~100 Odin | 5f |
| 5h | Per-thread heap region allocation | ~100 Odin | 5a |
| 5i | `camp_alloc_region` function (bump allocator) | ~50 Odin | 5h |
| 5j | Spawn handler migration (multi-instance → in-process) | ~100 Odin | 5f, 5h |
| 5k | Parallel handler migration | ~50 Odin | 5j |
| 5l | COOP/COEP warning for browser targets | ~30 Odin | 5a |
| 5m | Runtime detection (try shared memory, fallback) | ~80 Odin | 5a |
| 5n | E2E tests + benchmarks (multi-core) | ~200 Camp | 5j, 5k |

**Total estimated scope**: ~1,540 lines

**Exit criterion**: `Spawn.spawn!` and `Parallel.map!` work within a single WASM module using WASM threads. Near-linear speedup on multi-core. No multi-instance overhead. Falls back gracefully when threads unavailable.

---

## 11. References

| Resource | URL | Relevance |
|----------|-----|-----------|
| WASM Threads Spec | https://webassembly.github.io/threads/ | Atomic instructions, shared memory, wait/notify |
| WASM Threads Proposal Repo | https://github.com/WebAssembly/threads | Phase 4 status, browser support matrix |
| Wasmtime Threads Example | https://github.com/bytecodealliance/wasmtime/blob/main/examples/threads.rs | Multi-store + shared memory pattern |
| Wasmtime Threads Tier 2 | https://github.com/bytecodealliance/wasmtime/issues/12067 | Known gaps: no fuzzing for atomics |
| shared-everything-threads | https://github.com/WebAssembly/shared-everything-threads | Future: shared tables/globals + thread.spawn |
| Rayon Work-Stealing | https://github.com/rayon-rs/rayon | Reference for lock-free work-stealing queue design |
| COOP/COEP Guide | https://web.dev/coop-coep/ | Browser SharedArrayBuffer requirements |

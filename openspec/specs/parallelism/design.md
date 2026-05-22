# Parallelism Domain Design

## Architecture Overview

Camp provides three complementary effects for concurrency and parallelism:

```
┌──────────────────────────────────────────────────────────┐
│  Spawn: "Run THIS computation on a separate core"        │
│  Use case: independent CPU-heavy tasks                   │
│  Execution: truly parallel (separate OS thread/instance) │
├──────────────────────────────────────────────────────────┤
│  Parallel: "Apply THIS function across ALL elements"     │
│  Use case: data-parallel collection processing           │
│  Execution: sequential or thread-pool (handler choice)   │
├──────────────────────────────────────────────────────────┤
│  Async: "Overlap THESE I/O operations"                   │
│  Use case: concurrent file/network I/O                    │
│  Execution: cooperative coroutines on one thread          │
└──────────────────────────────────────────────────────────┘
```

| Effect | Purpose | Execution | Memory Model | Overhead |
|--------|---------|-----------|-------------|----------|
| `Async!` | I/O concurrency | Cooperative coroutines on one thread | Shared linear memory | ~100 bytes/coroutine |
| `Parallel!` | Data parallelism | Sequential or thread pool | Depends on handler | Depends on handler |
| `Spawn!` | Task parallelism | Separate OS threads / WASM instances | Isolated or shared | ~1-8 MB (instance) or ~100 bytes (thread) |

**Key principle**: Effects express *intent*; handlers choose *strategy*. A program that is correct with the sequential handler is also correct with the parallel handler (assuming `reduce!`'s function is associative).

---

## Parallel Effect

### Effect Definition

```camp
effect Parallel! {
  map! : <a, b>|items: List(a), f: |a| -> b| -[Parallel!]-> List(b)
  for_each! : <a>|items: List(a), f: |a| ->{}| -[Parallel!]-> {}
  filter! : <a>|items: List(a), predicate: |a| -> Bool| -[Parallel!]-> List(a)
  reduce! : <a, b>|items: List(a), init: b, f: |b, a| -> b| -[Parallel!]-> b
  all! : <a>|tasks: List(|| -> a)| -[Parallel!]-> List(a)
  any! : <a, e>|tasks: List(|| -[Throw!(e)]-> a)| -[Parallel! | Throw!(e)]-> a
}
```

### Operation Semantics

| Operation | Guarantee | Ordering |
|-----------|-----------|----------|
| `map!` | Apply `f` to every element; result has same length and order as input | Results in input order |
| `for_each!` | Apply `f` to every element; no return | Side effect order NOT guaranteed |
| `filter!` | Return elements where predicate is `True` | Preserves input order |
| `reduce!` | Cumulative application of `f` | `f` MUST be associative for parallel correctness; sequential handler folds left |
| `all!` | Execute every task; return all results | Results in input order |
| `any!` | Execute tasks; return first successful result; cancel remaining | Returns whichever task succeeds first |

### reduce! and Associativity

Camp does NOT enforce associativity at the type level (undecidable). Instead:

1. Documentation states `reduce!` requires associative `f` for parallel correctness
2. Sequential handler always folds left (correct regardless)
3. Parallel handler may fold in any order (correct only if `f` is associative)
4. For guaranteed left-to-right order, use `items.iter().fold(init, f)`

**Alternatives considered**:
- `Associative` trait: Undecidable, adds complexity for marginal benefit
- Separate `par_reduce!` (associative) and `par_fold!` (sequential): Adds API surface

### Effect Propagation

Each operation propagates the inner function's effects into the caller's effect row via effect polymorphism:

```camp
apply_all = <a, b, e>|items: List(a), f: |a| -[e]-> b| -[Parallel! | e]-> List(b) {
  items.par_map!(f)
}
```

### Collection Method Sugar

| Method | Desugars to | Effect Row |
|--------|------------|------------|
| `list.par_map!(f)` | `Parallel!.map!(list, f)` | `-[Parallel \| ...]->` |
| `list.par_filter!(p)` | `Parallel!.filter!(list, p)` | `-[Parallel!]->` |
| `list.par_reduce!(init, f)` | `Parallel!.reduce!(list, init, f)` | `-[Parallel!]->` |
| `list.par_for_each!(f)` | `Parallel!.for_each!(list, f)` | `-[Parallel!]->` |

Method sugar desugars at canonicalization. Surface AST preserves the method call form for tooling; canonical AST sees the `Parallel!.map!` call.

Future: `Map.par_map_values!`, `Set.par_map!`, `Iter.par_collect!` (deferred).

### Block Syntax

```camp
par { e1, e2, e3 }
-- Desugars to: Parallel!.all!([|| e1, || e2, || e3])
-- Returns: (T1, T2, T3) — tuple preserving individual types

par for x in xs { body }
-- Desugars to: Parallel!.for_each!(xs, |x| body)
-- Returns: {} (unit)
```

`par` keyword added to lexer. `par { }` returns a tuple (fixed compile-time count, preserves types). `Parallel!.all!` returns `List(a)` (dynamic count, same type). Use `par { }` for 2-10 tasks; `Parallel!.all!` for dynamic lists.

### Handlers

**Sequential handler** (reference, works everywhere):

```camp
handle Parallel in { ... } with {
  .map!(resume, items, f) => resume(items.iter().map(f).collect())
  .filter!(resume, items, pred) => resume(items.iter().filter(pred).collect())
  .reduce!(resume, items, init, f) => resume(items.iter().fold(init, f))
  .for_each!(resume, items, f) => { items.iter().for_each(f); resume({}) }
  .all!(resume, tasks) => resume(tasks.iter().map(|t| t()).collect())
  .any!(resume, tasks) => handle_any_sequential(tasks, resume)
}
```

**Thread-pool handler** (runtime-provided, auto-installed when `Parallel!` in `main!`'s effect row):

- `map!`: Split into N chunks, spawn each chunk, join, concatenate in order
- `reduce!`: Split into N chunks, reduce each locally, tree-reduce partial results
- `all!`: Enqueue each task, workers pick up, collect in input order
- `any!`: Enqueue all tasks, first success cancels remaining

The thread-pool handler uses `Spawn!` under the hood.

### Handler Guarantees

| Guarantee | Sequential | Thread-Pool |
|-----------|-----------|-------------|
| Result order | Preserved | Preserved |
| Determinism | Fully deterministic | Non-deterministic execution order, deterministic result order |
| Side effect order (`for_each!`) | Left-to-right | NOT guaranteed |
| Error propagation | First error stops | First error or all errors (handler choice) |
| Cancellation | N/A | `any!` cancels remaining on first success |

### Type System Rules

- Any function calling `Parallel!` operations (directly or transitively) must have `Parallel!` in its effect row
- Effect polymorphism: `f` may carry effect variable `e` that propagates through `par_map!`
- All `Parallel!` operations carry `!` (effectful naming convention)
- No shared mutation enforcement: functions passed to `Parallel!` cannot capture `$`-prefixed mutable bindings (falls out from existing stack-local mutation rules)

---

## Spawn Effect

### Effect Definition

```camp
effect Spawn! {
  spawn! : <a>|thunk: || -> a| -[Spawn!]-> Handle(a)
  join! : <a>|handle: Handle(a)| -[Spawn!]-> a
  cancel! : <a>|handle: Handle(a)| -[Spawn!]-> {}
}
```

### Operation Semantics

| Operation | Semantic |
|-----------|---------|
| `spawn!` | Creates new execution context, starts `thunk`, returns `Handle(a)` immediately |
| `join!` | Blocks until computation completes; re-throws errors in caller's context |
| `cancel!` | Signals computation to stop (best-effort); handle becomes invalid |

### Handle Type

- **Opaque**: Users cannot access internals
- **One-shot**: Consumed by exactly one `join!` or `cancel!`
- **Move semantics**: Cannot be used after consumption
- **No send**: Cannot be passed to another spawned computation

Handle lifecycle: Created → Pending → Completed → Joined (or Cancelled).

### Handle Implementation

**Decision**: Use i32 handle ID with a result slot array. Works for both multi-instance (ID maps to host result map) and WASM threads (ID maps to shared memory slot).

### Structured Concurrency

Every `Spawn!.spawn!` must be followed by exactly one `Spawn!.join!` or `Spawn!.cancel!` before the handler exits. Unstructured concurrency (fire-and-forget) leads to resource leaks, use-after-free, and unpredictable behavior.

Enforcement:
1. Compiler emits warning (future: error) for unjoined spawns
2. Handler tracks outstanding handles; on exit, warns and auto-cancels

### Error Propagation Across Instances

When a spawned computation throws in a separate WASM instance: worker catches error, serializes it (tag + payload), writes to result slot with "failed" status. `join!` reads serialized error and re-throws via `Throw.throw!`. Requires thrown values to be serializable.

### Nested Spawn

A spawned computation can call `Spawn!.spawn!` if its handler includes `Spawn!`. Creates another task in the same thread pool. Enables recursive divide-and-conquer. Pool has max queue depth; excess tasks wait in backlog.

### Spawn + Async Interaction

Spawned computations can use `Async!` but must handle it internally. Each worker runs its own coroutine scheduler for `Async!` effects. `wasi:io/poll` is thread-safe in wasmtime.

### Effect Row of join!

The Handle type carries the thunk's effect information at the type level. `join!`'s effect row includes `Spawn!` plus the thunk's effects.

---

## Async Effect and WASI Runtime

### Design Philosophy

- **Single-threaded event loop**: All coroutines on one WASM thread (matches WASM's model)
- **Poll-driven I/O**: Use `wasi:io/poll` for readiness-based polling
- **Stackless coroutines**: CPS-compiled state machines (~100-300 bytes each)

### Coroutine Scheduler

Data structures:
- **Ready Queue**: FIFO of coroutines ready to run
- **Blocked Map**: WASI pollable → waiting coroutines
- **Active Handles**: Handle ID → { status, result } for structured concurrency
- **Join Waiters**: Handle ID → coroutines waiting on join!

Scheduler loop:
1. If ready_queue empty and blocked_map empty → done
2. If ready_queue empty → `wasi:io/poll-list` on all pollables, move ready coroutines to queue
3. Dequeue coroutine, resume it
4. Coroutine either: completes, yields, blocks on I/O, joins handle, spawns, or throws
5. Go to 1

**Fairness**: Round-robin FIFO, yield-based cooperation, no starvation guarantee (no preemption in WASM).

### WASI I/O Poll Bridge

When a coroutine calls `File.read!(handle)`:
1. Call `wasi:io/input-stream.read(len)`
2. If short read / would-block → `handle.subscribe()` → add to blocked_map → suspend
3. When pollable ready → resume and retry read

Short read/write handling: Runtime buffers partial results and retries transparently (like Rust's `tokio::io::AsyncReadExt::read_exact`).

### Effect-to-WASI Mapping

| Camp Operation | WASI System Call |
|----------------|-----------------|
| `Console.print!(msg)` | `wasi:io/output-stream.write(stdout, msg)` |
| `Console.readln!()` | `wasi:io/input-stream.read(stdin)` + subscribe |
| `File.read!(handle)` | `wasi:io/input-stream.read` + subscribe |
| `File.write!(handle, data)` | `wasi:io/output-stream.write` + subscribe |
| `Time.sleep!(ms)` | `wasi:io/poll.poll-list([], timeout=ms)` |
| `Random.int!(min, max)` | `wasi:random/random.get-random-bytes(8)` |
| `Async.yield!()` | (no WASI call; reschedule coroutine) |
| `Async.spawn!(thunk)` | (no WASI call; enqueue coroutine) |

### WASM Codegen

Runtime functions embedded in generated WASM:

| Function | Purpose |
|----------|---------|
| `camp_async_init` | Initialize scheduler |
| `camp_async_enqueue` | Enqueue coroutine; returns handle ID |
| `camp_async_dequeue` | Dequeue next ready coroutine |
| `camp_async_block` | Block coroutine on pollable |
| `camp_async_complete` | Mark handle completed |
| `camp_async_join_wait` | Suspend until handle completes |
| `camp_async_cancel` | Cancel handle |
| `camp_async_run` | Main scheduler loop |

When `main!` has `Async!` in effect row, `_start` initializes scheduler, enqueues main as coroutine 0, runs scheduler loop, and returns exit code.

### Component Model Async Migration

**Current (WASI Preview 2)**: Poll-based, Camp manages scheduling, CPS-compiled coroutines.

**Future (WASI Preview 3)**: Host-managed event loop, `future<T>`/`stream<T>`, component model async lowering/lifting.

**Migration path**: Runtime change only — `Async!` effect API (`spawn!`, `join!`, `yield!`, `cancel!`) stays the same. User code does not change.

Timeline: Stack-switching in wasmtime ~2026 H2; component model async ~2027; WASI Preview 3 ~2027+.

---

## Multi-Instance Architecture (Phase 3)

The simplest parallelism that works today in wasmtime — no WASM threads, no SharedArrayBuffer, no COOP/COEP required.

### Architecture

```
Camp CLI (Odin host)
├── Main Instance (Store on main thread, runs main!)
├── Thread Pool Manager
│   ├── Worker 0 (OS Thread + Store + Module)
│   ├── Worker 1 (OS Thread + Store + Module)
│   └── Worker N ...
├── Work Queue (thread-safe MPMC channel)
└── Result Map (thread-safe hashmap: task_id → { status, result_bytes })
```

### Closure Serialization

```
Serialized Closure Format:
┌──────────────────────────────────────┐
│  magic:      u32  (0x4350 = "CP")    │
│  version:    u32  (1)                │
│  fn_index:   u32  (table index)      │
│  env_size:   u32  (byte count)       │
│  env_bytes:  [u8; env_size]          │
│    - primitives: direct bytes (LE)   │
│    - pointers: 4 bytes each (i32)    │
│  effect_row: u32  (bitmask)          │
└──────────────────────────────────────┘
```

**String/list handling** (cannot pass by pointer across instances):
- **Deep copy**: Serialize bytes into closure env; worker deserializes into its own heap
- **Index reference**: Store in host-managed shared buffer; pass index
- **Phase 3 strategy**: Deep copy for simplicity; index references for hot paths

**Effect row bitmask** tells the worker which handlers to install:

| Bit | Effect | Worker Handler |
|-----|--------|---------------|
| 0 | `Throw` | Serialize errors back |
| 1 | `Console` | WASI fd_write |
| 2 | `File` | WASI filesystem |
| 3 | `Async!` | Worker's own scheduler |
| 4 | `Parallel!` | Error — not supported in Phase 3 |
| 5 | `Spawn!` | Error — not supported in Phase 3 |

### Worker Module Generation

Two-module compilation:
1. **Main module**: `main!` + all user functions
2. **Worker module**: `run_task` export + same function definitions/table

Optimization: Emit a single module serving as both main and worker. `_start` only runs in main instance; workers call `run_task`.

### Spawn Handler via Multi-Instance

```camp
.spawn!(resume, thunk) => {
  serialized = camp_serialize_closure(thunk)
  handle_id = camp_thread_pool_submit(serialized)
  resume(Handle(handle_id))
}
.join!(resume, handle) => {
  camp_thread_pool_wait(handle.id)       // host callback (blocking)
  result_bytes = camp_thread_pool_result(handle.id)
  result = camp_deserialize_value(result_bytes)
  resume(result)
}
```

Join blocking: Use host callback (blocks OS thread). Main instance is single-threaded — if waiting on join, can't do other work. Use `Async!` for concurrent work; `Spawn!` for parallel work where blocking on join is expected.

### Parallel Handler via Multi-Instance

Chunk-based work distribution:

```camp
.map!(resume, items, f) => {
  chunk_size = max(1, items.len() / num_threads)
  chunks = split_chunks(items, chunk_size)
  handles = chunks.iter().map(|chunk| {
    Spawn!.spawn!(|| chunk.iter().map(f).collect())
  }).collect()
  results = handles.iter().map(Spawn!.join!).collect()
  resume(concat(results))
}
```

Chunk size heuristic:

| Collection Size | Chunk Size | Rationale |
|----------------|------------|-----------|
| < 100 | All in one chunk | Parallelism overhead > benefit |
| 100..10,000 | ceil(len / (N * 4)) | 4 chunks/thread for load balancing |
| > 10,000 | ceil(len / (N * 8)) | 8 chunks/thread for better balance |

### Performance

| Source | Cost |
|--------|------|
| Closure serialization | ~1-10 µs per closure |
| WASM instantiation | ~0.1-1 ms per worker (one-time) |
| Work queue enqueue/dequeue | ~0.1-1 µs per task |
| Result deserialization | ~1-10 µs per result |

Break-even: `task_time >> serialization_time + scheduling_overhead`. CPU-heavy tasks (> 1ms) benefit; fine-grained tasks should use sequential. Each chunk should take ≥ ~0.1 ms CPU time.

Expected scalability: 2 threads → ~1.8-1.95x; 4 → ~3.5-3.8x; 8 → ~6.5-7.5x; 16 → ~12-14x.

---

## WASM Threads Architecture (Phase 5)

Migrates from multi-instance to in-process parallelism using the WASM threads proposal. Closures pass by pointer instead of serialization. Overhead drops from ~1-10 µs to ~0.01-0.1 µs per task.

### WASM Threads Capabilities

1. **Shared Linear Memory**: `shared=true` flag; requires `maximum` size
2. **Atomic Instructions**: `i32.atomic.load/store/rmw.*`, `i64.atomic.*`, `atomic.fence`
3. **Wait/Notify**: `memory.atomic.wait32/64`, `memory.atomic.notify`

**What threads does NOT provide**: Thread creation (`thread.spawn`), shared tables/globals, shared stacks.

**Thread creation in wasmtime**: Host creates N OS threads, each creates a `Store` with shared memory import, each instantiates the module. All instances share the same `Memory` object.

**Browser**: Requires COOP/COEP headers for `SharedArrayBuffer`.

### In-Process Architecture

```
Single WASM Module with SharedArrayBuffer
├── Shared Memory (shared=true, max=N pages)
│   ├── Module Data Segment (read-only constants)
│   ├── Atomic Work Queue (circular buffer)
│   ├── Per-Thread Heap Regions (bump allocators)
│   ├── Result Slots (status + result per handle ID)
│   └── Closure Environment Pool (shared bump allocator)
├── Agent 0 (main, own stack + table)
├── Agent 1 (worker, own stack + table)
└── Agent N ...
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Memory sharing | All agents share one Memory | Required by WASM threads |
| Thread-local heaps | Per-agent allocation region | Avoids cross-thread refcounting, allocator contention, false sharing |
| Closures by pointer | Pass env_offset in shared memory | No serialization needed |
| Function tables NOT shared | Each agent has own table | WASM threads doesn't share tables; same fn indices |
| Synchronization via atomics | Work queue + result slots | Maps directly to WASM atomic instructions |

### Shared Memory Layout

```
0x0000_0000  Module Data Segment (constants, string literals)
0x0010_0000  Atomic Work Queue (head, tail, entries[])
              Result Slots ({ status: u32, result: u32 }[])
              Thread-Local Heap Regions (per-thread ~1MB)
              Closure Environment Pool (atomic offset increment)
              Free space
```

Memory declaration: `(memory $memory (export "memory") 1 65536 shared)` — 256 MB max.

### Atomic Work Queue

```
Work Queue:
  head:     u32 (atomic) — next dequeue index
  tail:     u32 (atomic) — next enqueue index
  capacity: u32
  entries[]: { fn_index: u32, env_offset: u32, result_slot: u32, flags: u32 }

Enqueue: i32.atomic.rmw.add(tail, 1), write entry, memory.atomic.notify
Dequeue: i32.atomic.rmw.add(head, 1), read entry
Work-stealing (optional): i32.atomic.rmw.cmpxchg on victim's deque
```

### Per-Thread Heap Regions

Each WASM agent allocates from its own shared memory region. Bump allocator within the region (non-atomic — own thread only). Avoids:
- Cross-thread refcounting (Perceus `camp_dup`/`camp_drop` don't need atomics)
- Allocator contention
- False sharing

**Values crossing thread boundaries**:
1. **Deep copy** (Phase 5 strategy): Sending thread copies bytes into shared closure env; receiving thread creates new value in its own heap
2. **Immutable read-only sharing**: Data segment constants shared without refcounting
3. **Ownership transfer** (future optimization): Increment refcount to 1, write pointer, receiving thread takes ownership

### New IR Nodes

| IR Node | Fields | WASM Instruction |
|---------|--------|-----------------|
| `IR_Atomic_Load` | ptr, offset, width, ordering | `i32.atomic.load` / `i64.atomic.load` |
| `IR_Atomic_Store` | ptr, offset, value, width, ordering | `i32.atomic.store` / `i64.atomic.store` |
| `IR_Atomic_RMW` | ptr, offset, value, op, width, ordering | `i32.atomic.rmw.<op>` |
| `IR_Atomic_Fence` | ordering | `atomic.fence` |
| `IR_Wait` | ptr, offset, expected, timeout, width | `memory.atomic.wait32` / `wait64` |
| `IR_Notify` | ptr, offset, count | `memory.atomic.notify` |

Supporting types:

```odin
Atomic_Width :: enum { B1, B2, B4, B8 }
Atomic_Op :: enum { Add, Sub, And, Or, Xor, Xchg, CmpXchg }
Memory_Ordering :: enum { SeqCst }  // WASM only supports sequentially consistent
```

All mid-end passes must handle atomic IR variants: `effect_lower`, `closure_convert`, `cps`, `rc`. Phase 5: atomic nodes only generated by runtime codegen, not user code.

### WASM Codegen Changes

**Shared memory**: When `--threads=N`, set `shared` flag and require `maximum` field.

**Atomic opcodes**:

| IR Node | Opcode |
|---------|--------|
| `IR_Atomic_Load{.B4, .SeqCst}` | `0xFE 10` |
| `IR_Atomic_Store{.B4, .SeqCst}` | `0xFE 17` |
| `IR_Atomic_RMW{.Add, .B4, .SeqCst}` | `0xFE 1E` |
| `IR_Atomic_RMW{.CmpXchg, .B4, .SeqCst}` | `0xFE 48` |
| `IR_Atomic_Fence{.SeqCst}` | `0xFE 50` |
| `IR_Wait{.B4}` | `0xFE 52` |
| `IR_Notify` | `0xFE 54` |

**Worker entry function**: `camp_worker_entry` export — dequeue task loop, `call_indirect` with task env and fn, store result.

### Runtime Detection and Fallback

```
1. Try WASM threads (shared memory + atomics)
   └─ Fails? → Fall back to multi-instance (Phase 3)
2. Try multi-instance (N stores on N threads)
   └─ Fails? → Fall back to sequential (Phase 2)
3. Sequential handler (always works)
```

Detection:
- **wasmtime**: Try creating shared `Memory`; fallback to multi-instance
- **Browser**: Check `SharedArrayBuffer` defined; fallback to sequential
- **Node.js**: Always available

Compile-time flag: `--threads=1` (or absent) → single-threaded module; `--threads=N` (N > 1) → multi-threaded module.

COOP/COEP warning emitted for browser targets.

---

## Implementation Plan

### Phase 1: I/O Concurrency via WASI Poll (Async Runtime)

| Step | Description | Scope |
|------|-------------|-------|
| 1a | Async scheduler data structures | ~200 Odin |
| 1b | Scheduler loop: dequeue, resume, block, complete | ~150 Odin |
| 1c | `camp_async_*` runtime functions | ~300 Odin |
| 1d | WASI poll bridge | ~150 Odin |
| 1e | Short read/write handling | ~100 Odin |
| 1f | `Time.sleep!` via poll timeout | ~50 Odin |
| 1g | `Async.yield!` | ~30 Odin |
| 1h | Structured concurrency enforcement | ~80 Odin |
| 1i | Effect-to-WASI mapping | ~200 Odin |
| 1j | E2E tests | ~150 Camp |

**Total**: ~1,410 lines. **Exit criterion**: Concurrent file reads with `wasi:io/poll`.

### Phase 2: Sequential Parallel Effect

| Step | Description | Scope |
|------|-------------|-------|
| 2a | `Parallel!` effect definition in Prelude | ~40 Camp |
| 2b | Sequential handler | ~80 Camp |
| 2c | Typechecker: effect row propagation | ~30 Odin |
| 2d | Collection method sugar | ~60 Odin |
| 2e | `par { }` and `par for` block syntax | ~80 Odin |
| 2f | E2E tests | ~200 Camp |
| 2g | Formatter support | ~30 Odin |

**Total**: ~520 lines. **Exit criterion**: `Parallel!.map!` works with sequential handler; effect row includes `Parallel!`.

### Phase 3: Multi-Instance Spawn

| Step | Description | Scope |
|------|-------------|-------|
| 3a | `--threads=N` flag + `CAMP_THREADS` env var | ~50 Odin |
| 3b | Thread pool manager | ~250 Odin |
| 3c | Worker loop | ~100 Odin |
| 3d | Worker module generation | ~200 Odin |
| 3e | Closure serialization format + implementation | ~200 Odin |
| 3f | Closure deserialization in worker | ~100 Odin |
| 3g | Spawn handler (serialize, submit, wait, deserialize) | ~150 Odin |
| 3h | Parallel handler (chunk, spawn, join, concatenate) | ~150 Odin |
| 3i | String/list cross-instance handling | ~100 Odin |
| 3j | Error propagation across instances | ~80 Odin |
| 3k | Structured concurrency tracking | ~80 Odin |
| 3l | E2E tests + benchmarks | ~200 Camp |

**Total**: ~1,560 lines. **Exit criterion**: Two spawned tasks ~2x faster than sequential.

### Phase 4: Thread-Pool Parallel Handler

| Step | Description | Scope |
|------|-------------|-------|
| 4a | `Parallel!` → `Spawn!` handler: chunk-based distribution | ~150 Camp |
| 4b | Auto-install thread-pool handler | ~80 Odin |
| 4c | Chunk size heuristics | ~60 Camp |
| 4d | Work-stealing scheduler (optional) | ~400 Camp |
| 4e | E2E + benchmarks | ~200 Camp |

**Total**: ~490 lines (without work-stealing) or ~890 lines. **Exit criterion**: Near-linear speedup on multi-core.

### Phase 5: WASM Threads

| Step | Description | Scope |
|------|-------------|-------|
| 5a | Shared memory codegen | ~80 Odin |
| 5b | `IR_Atomic_*` node types | ~100 Odin |
| 5c | IR traversal for atomic nodes | ~150 Odin |
| 5d | Atomic instruction WASM emission | ~200 Odin |
| 5e | Work queue data structure | ~150 Odin |
| 5f | Enqueue/dequeue operations | ~150 Odin |
| 5g | Worker entry function codegen | ~100 Odin |
| 5h | Per-thread heap regions | ~100 Odin |
| 5i | `camp_alloc_region` bump allocator | ~50 Odin |
| 5j | Spawn handler migration (multi-instance → in-process) | ~100 Odin |
| 5k | Parallel handler migration | ~50 Odin |
| 5l | COOP/COEP warning | ~30 Odin |
| 5m | Runtime detection + fallback | ~80 Odin |
| 5n | E2E tests + benchmarks | ~200 Camp |

**Total**: ~1,540 lines. **Exit criterion**: `Spawn!.spawn!` and `Parallel!.map!` work within single WASM module. No multi-instance overhead.

### Phase 6: SIMD Optimization (Future)

| Step | Description | Scope |
|------|-------------|-------|
| 6a | `Simd` intrinsics module | ~200 Camp |
| 6b | Auto-vectorization for `Parallel!.map!` on numeric data | ~300 Odin |
| 6c | `Iter.par_collect!` SIMD fast path | ~100 Odin |

---

## Open Questions

### reduce! Associativity

**Decision**: No static enforcement. Document convention only. Same tradeoff as Rust's `rayon::reduce` and Java's `ParallelStream.reduce`.

### par Block Tuple vs List Return

**Decision**: `par { e1, e2, e3 }` returns `(T1, T2, T3)` (preserves individual types). `Parallel!.all!` returns `List(a)` (dynamically-sized, same type).

### Error Handling in map!

**Decision**: Short-circuit on first error. Alternatives considered: collect all errors (breaks `Throw(e)` model), return `[Ok | Err]` (changes return type). `any!` succeeds on first success; `map!` fails on first failure — dual behavior.

### Interaction with Iter(a)

**Status**: Deferred. Future `Iter.par_collect!` requires knowing iterator length or consuming eagerly into chunks.

### Handle Type Implementation

**Decision**: i32 handle ID with result slot array. Works for multi-instance (host result map) and WASM threads (shared memory slots).

### Nested Spawn

**Decision**: Allowed. Nested `Spawn!.spawn!` creates tasks in the same thread pool. Enables recursive divide-and-conquer. Max queue depth prevents exhaustion.

### Spawn + Async Interaction

**Decision**: Allowed. Each worker runs its own coroutine scheduler. `wasi:io/poll` is thread-safe in wasmtime.

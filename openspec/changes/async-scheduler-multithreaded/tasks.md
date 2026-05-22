## 1. IR and Codegen Infrastructure

- [ ] 1.1 Add `IR_Resume` node to `ir.odin` with fields: `resume_id`, `value`, `type`, `span`
- [ ] 1.2 Add `IR_Resume` to the `IR_Expr` union
- [ ] 1.3 Add 6 atomic IR nodes to `ir.odin`: `IR_Atomic_Load`, `IR_Atomic_Store`, `IR_Atomic_RMW`, `IR_Atomic_Fence`, `IR_Wait`, `IR_Notify` with supporting enums `Atomic_Width` and `Atomic_Op`
- [ ] 1.4 Add atomic IR nodes to the `IR_Expr` union
- [ ] 1.5 Add `Memory_Ordering` enum (`SeqCst` only) and `Atomic_Width` enum (`B1`, `B2`, `B4`, `B8`)
- [ ] 1.6 Update `collect_locals` in `codegen.odin` to traverse `IR_Resume` and atomic IR nodes
- [ ] 1.7 Update `ir_expr_wasm_type` and `ir_operand_wasm_type` for new IR nodes
- [ ] 1.8 Implement WASM codegen for `IR_Resume`: load fn_idx from closure, one-shot check (trap if zero), zero fn_idx (mark consumed), load env_ptr, `call_indirect`
- [ ] 1.9 Implement WASM codegen for atomic IR nodes with correct opcodes (`0xFE` prefix)
- [ ] 1.10 Implement `emit_expr` for `IR_Atomic_Load`, `IR_Atomic_Store`, `IR_Atomic_RMW`, `IR_Atomic_Fence`, `IR_Wait`, `IR_Notify`
- [ ] 1.11 Update `effect_lower.odin` to pass through atomic and resume IR nodes
- [ ] 1.12 Update `closure_convert.odin` to handle atomic and resume IR nodes
- [ ] 1.13 Update `cps.odin` to handle atomic and resume IR nodes
- [ ] 1.14 Update `rc.odin` to handle atomic and resume IR nodes
- [ ] 1.15 Verify `odin test src` passes with all new IR nodes

## 2. Scheduler Data Structures in WASM Codegen

- [ ] 2.1 Define shared memory layout constants in `codegen.odin` (scheduler base address, queue sizes, handle table size, timer wheel size, per-agent heap size)
- [ ] 2.2 Implement `emit_camp_sched_init_body` — allocate scheduler state in linear memory, zero-initialize queues and handle table
- [ ] 2.3 Implement ready queue ring buffer layout: head (atomic u32), tail (u32), capacity, mask, entries[256]
- [ ] 2.4 Implement LIFO slot layout: single atomic u32 (task pointer, 0 = empty)
- [ ] 2.5 Implement global inject queue layout: head (atomic u32), tail (atomic u32), capacity, entries[4096]
- [ ] 2.6 Implement handle table layout: next_id (atomic u32), entries[4096] × 16 bytes (status, result, result_fn, result_env, scope_id, task_ptr)
- [ ] 2.7 Implement wait map layout: count, entries[1024] × (pollable_handle, task_ptr)
- [ ] 2.8 Implement join map layout: count, entries[1024] × (handle_id, task_ptr)
- [ ] 2.9 Implement timer wheel layout: 4 levels × 64 slots, each slot a doubly-linked list head
- [ ] 2.10 Implement per-agent heap region layout: base addresses for N agents
- [ ] 2.11 Implement notification address layout: epoch counters and wait addresses per worker
- [ ] 2.12 Add `RUNTIME_SCHED_INIT`, `RUNTIME_SCHED_SPAWN`, `RUNTIME_SCHED_JOIN`, `RUNTIME_SCHED_CANCEL`, `RUNTIME_SCHED_COMPLETE`, `RUNTIME_SCHED_YIELD`, `RUNTIME_SCHED_BLOCK_IO`, `RUNTIME_SCHED_TIMER_INSERT`, `RUNTIME_SCHED_TIMER_CANCEL`, `RUNTIME_SCHED_NOTIFY`, `RUNTIME_SCHED_PARK`, `RUNTIME_SCHED_WORKER_LOOP` runtime function indices
- [ ] 2.13 Update `RUNTIME_FUNC_COUNT` to include all new scheduler runtime functions
- [ ] 2.14 Implement `emit_camp_sched_spawn_body` — allocate handle in table (CAS on next_id), set status=Pending, enqueue task in local queue or LIFO slot, notify spinning/parked workers per spinning protocol
- [ ] 2.15 Implement `emit_camp_sched_complete_body` — CAS handle status to Completed, store result, check join map for waiters, wake join waiters
- [ ] 2.16 Implement `emit_camp_sched_join_body` — check handle status; if Completed, return result; if Pending, register in join map and suspend; if Cancelled, return Cancelled result
- [ ] 2.17 Implement `emit_camp_sched_cancel_body` — CAS handle status to Cancelled, set cancellation flag in task header, remove from wait/join maps if present, re-enqueue task
- [ ] 2.18 Implement `emit_camp_sched_yield_body` — decrement budget; if zero, reset budget and re-enqueue at tail; if non-zero, no-op (inline resume)
- [ ] 2.19 Implement `emit_camp_sched_block_io_body` — register pollable+task in wait map, suspend task
- [ ] 2.20 Implement `emit_camp_sched_timer_insert_body` — compute target level and slot, insert into linked list
- [ ] 2.21 Implement `emit_camp_sched_timer_cancel_body` — remove entry from linked list
- [ ] 2.22 Implement `emit_camp_sched_notify_body` — increment epoch, `memory.atomic.notify`
- [ ] 2.23 Implement `emit_camp_sched_park_body` — load epoch, double-check for work, `memory.atomic.wait32`

## 3. Worker Loop and Work-Stealing

- [ ] 3.1 Implement `emit_camp_sched_worker_loop_body` — main loop: LIFO → local pop → global pop (every 61 ticks) → steal → I/O poll (Worker 0) → park
- [ ] 3.2 Implement local queue push: check capacity, overflow half to global queue if full, write entry, increment tail
- [ ] 3.3 Implement local queue pop: refresh cached head if empty, pop from tail (LIFO from owner side)
- [ ] 3.4 Implement local queue steal: load victim's head, compute steal count (half), CAS on victim's head, transfer tasks
- [ ] 3.5 Implement LIFO slot swap: `i32.atomic.rmw.xchg` on slot address
- [ ] 3.6 Implement global queue push: CAS loop on tail
- [ ] 3.7 Implement global queue pop: CAS loop on head
- [ ] 3.8 Implement spinning protocol: decrement `nmspinning` before parking, re-check for work, wake one worker if last spinner finds work
- [ ] 3.9 Implement Worker 0 I/O driver: collect pollables from wait map, compute timeout from timer wheel, call `wasi:io/poll.poll-list`, dispatch completions
- [ ] 3.10 Implement timer wheel advance: expire all timers up to current time, cascade from higher levels, move expired tasks to ready queues
- [ ] 3.11 Implement timer wheel next_expiry: scan all non-empty slots for minimum expiry
- [ ] 3.12 Implement `camp_worker_entry` export function: set up per-agent heap, call worker_loop(worker_id)
- [ ] 3.13 Verify `odin build src -out:camp -ignore-unknown-attributes` succeeds

## 4. Shared Memory and WASM Threads Codegen

- [ ] 4.1 Update WASM memory declaration: set `shared=true` and `maximum=65536` when `--threads=N` (N > 1)
- [ ] 4.2 Add `--threads` CLI flag parsing in `cli.odin` (already scaffolded from Group 18, verify it works)
- [ ] 4.3 Add `CAMP_THREADS` env var reading with medium priority
- [ ] 4.4 Add `num_cpus()` detection as default priority
- [ ] 4.5 Emit `_start` with scheduler initialization: `camp_sched_init(num_workers)`, spawn main! as task 0, enter `camp_sched_worker_loop(0)`
- [ ] 4.6 Emit `camp_worker_entry` as WASM export for host-spawned worker threads
- [ ] 4.7 Implement per-agent `camp_alloc` dispatch: each agent's alloc reads its worker_id to find its heap region base
- [ ] 4.8 Verify e2e test: 2 workers, simple spawn + join

## 5. Effect Handler Codegen for Async!/Spawn!

- [ ] 5.1 Implement `Async!` default handler codegen in `codegen.odin` — `.spawn!` arm allocates handle and calls `camp_sched_spawn`; `.join!` arm calls `camp_sched_join`; `.yield!` arm calls `camp_sched_yield`; `.cancel!` arm calls `camp_sched_cancel`
- [ ] 5.2 Implement `Spawn!` default handler codegen — same as Async! but with `task_type=Spawn`
- [ ] 5.3 Implement `Handle(a, e)` type representation: i32 handle ID (opaque), effect row `e` tracked in type system
- [ ] 5.4 Implement error result slot tagging in `camp_sched_complete`: tag=0 for normal, tag=1 for thrown error
- [ ] 5.5 Implement `join!` re-throw: check result slot tag; if tag=1, perform `Throw!.throw!(error_value)` in caller's context
- [ ] 5.6 Implement handle scope tracking: each handler scope gets a unique scope_id; handles are tagged with scope_id; on handler exit, iterate handle table and cancel all Pending handles with matching scope_id
- [ ] 5.7 Implement budget decrement instrumentation in CPS transform: before each `IR_Perform`, emit budget load, decrement, store, and conditional branch to yield
- [ ] 5.8 Implement cancellation flag check instrumentation in CPS transform: before each `IR_Perform`, emit atomic load of cancellation flag, conditional branch to exit-with-Cancelled
- [ ] 5.9 Verify `odin test src` passes with all handler codegen

## 6. I/O Bridge and Timer Wheel Integration

- [ ] 6.1 Implement WASI I/O imports: `wasi:io/poll.poll-list`, `wasi:io/input-stream.read`, `wasi:io/input-stream.subscribe`, `wasi:io/output-stream.write`, `wasi:io/output-stream.subscribe`
- [ ] 6.2 Implement `File!.read!` handler: try read, if short/blocking → subscribe → `camp_sched_block_io` → suspend → retry on resume
- [ ] 6.3 Implement `File!.write!` handler: try write, if blocking → subscribe → `camp_sched_block_io` → suspend → retry on resume
- [ ] 6.4 Implement `Console!.readln!` handler: subscribe stdin → `camp_sched_block_io` → suspend → read on resume
- [ ] 6.5 Implement `Time.sleep!` handler: insert timer via `camp_sched_timer_insert` → suspend → resume on expiry
- [ ] 6.6 Implement zero-duration poll safety: when timer wheel has zero-duration timer, enqueue task immediately without calling `poll-list(timeout=0)`, yield to host before next iteration
- [ ] 6.7 Verify e2e test: concurrent file reads bounded by slowest
- [ ] 6.8 Verify e2e test: `Time.sleep!` + concurrent I/O overlap correctly

## 7. Type System: Handle(a, e) and Effect Propagation

- [ ] 7.1 Update `Handle` type in `types.odin` to carry effect row parameter `e`
- [ ] 7.2 Update typechecker to infer `Handle(a, e)` from spawn! thunk's effect row
- [ ] 7.3 Update `join!` effect row propagation: compose `Spawn! | e` (or `Async! | e`) into caller's effect row
- [ ] 7.4 Update effect row subtraction for `handle Async!`/`handle Spawn!` to remove the effect AND propagate `e` from joined handles
- [ ] 7.5 Implement unjoined spawn warning: track Handle values in handler scope, warn if not consumed on all paths
- [ ] 7.6 Update prelude effect definitions for `Async!` and `Spawn!` with `Handle(a, e)` return types
- [ ] 7.7 Verify `odin test src` passes with Handle(a, e) changes

## 8. Parallel! Thread-Pool Handler

- [ ] 8.1 Implement `Parallel!` thread-pool handler: `.map!` chunks work and spawns via `Spawn!.spawn!`, joins all, concatenates in order
- [ ] 8.2 Implement `Parallel!.reduce!` handler: chunk, reduce each locally, tree-reduce partial results
- [ ] 8.3 Implement `Parallel!.any!` handler: spawn all tasks, first success cancels remaining via `cancel!`
- [ ] 8.4 Implement `Parallel!.all!` handler: spawn all tasks, join all, collect in order
- [ ] 8.5 Implement `Parallel!.filter!` handler: parallel map + sequential filter (preserves order)
- [ ] 8.6 Implement `Parallel!.for_each!` handler: spawn chunks, join all, side effects unordered
- [ ] 8.7 Implement chunk size heuristics: < 100 items → one chunk; 100–10,000 → 4 chunks/thread; > 10,000 → 8 chunks/thread
- [ ] 8.8 Implement auto-install thread-pool handler when `Parallel!` in `main!`'s effect row
- [ ] 8.9 Verify e2e test: `Parallel!.map!` with N workers achieves near-linear speedup
- [ ] 8.10 Verify e2e test: `Parallel!.any!` cancels remaining tasks on first success

## 9. Multi-Instance Fallback

- [ ] 9.1 Implement closure serialization format in `runtime.odin` (Odin host): magic, version, fn_index, env_size, env_bytes, effect_row bitmask
- [ ] 9.2 Implement closure deserialization in worker module
- [ ] 9.3 Implement thread pool manager (Odin host): MPMC work queue, result map, worker thread creation
- [ ] 9.4 Implement `camp_worker_entry` for multi-instance mode: dequeue serialized closure, deserialize, execute, serialize result, store in result map
- [ ] 9.5 Implement `Spawn!` handler for multi-instance: serialize thunk, submit to host queue, return Handle; join! polls result map
- [ ] 9.6 Implement error propagation across instances: serialize error tag + payload in result slot
- [ ] 9.7 Implement runtime detection: try creating shared Memory → try multi-instance → fall back to sequential
- [ ] 9.8 Verify e2e test: multi-instance mode distributes work across OS threads
- [ ] 9.9 Verify e2e test: sequential fallback works when threads unavailable

## 10. Testing and Hardening

- [ ] 10.1 E2E test: `Async!.spawn!` + `Async!.join!` on single worker (`--threads=1`)
- [ ] 10.2 E2E test: `Async!.spawn!` + `Async!.join!` on multiple workers (`--threads=4`)
- [ ] 10.3 E2E test: work-stealing distributes tasks when one worker is overloaded
- [ ] 10.4 E2E test: cooperative budget — CPU-bound task yields after 128 operations
- [ ] 10.5 E2E test: cancellation delivery — cancelled task stops within one budget cycle
- [ ] 10.6 E2E test: structured concurrency — handler exit auto-cancels unjoined handles
- [ ] 10.7 E2E test: error propagation — `Spawn!.join!` re-throws error in caller's context
- [ ] 10.8 E2E test: timer wheel — `Time.sleep!` with concurrent I/O
- [ ] 10.9 E2E test: zero-duration sleep does not starve host runtime
- [ ] 10.10 E2E test: double join is a runtime error (trap)
- [ ] 10.11 E2E test: cancel-then-join sees Cancelled status
- [ ] 10.12 E2E test: handle table exhaustion triggers Throw!(HandleLimit)
- [ ] 10.13 E2E test: `Parallel!.map!` preserves order regardless of execution order
- [ ] 10.14 E2E test: `Parallel!.any!` returns first successful result
- [ ] 10.15 Benchmark: near-linear speedup on multi-core with `Parallel!.map!`
- [ ] 10.16 Verify `odin test src` (all unit tests) passes
- [ ] 10.17 Verify `just test-e2e` passes with all new e2e tests

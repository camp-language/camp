# Camp Async: WASI Migration Roadmap

Current implementation targets **WASI Preview 1** (`poll_oneoff`, `clock_time_get`). This document tracks the known gaps and migration path to Preview 2 and beyond.

## Current State: WASI Preview 1

| Feature | Implementation | Status |
|---------|----------------|--------|
| Timer via `clock_time_get` | `sched_timer_tick` calls `clock_time_get(CLOCK_MONOTONIC)` | Done |
| Sleep via timer wheel | `sched_timer_insert` + `poll_oneoff` with timeout | Partial — timer insert works, poll bridge needs timeout subscription |
| I/O blocking via `poll_oneoff` | `sched_block_io` records in wait_map; `sched_poll_and_dispatch` builds fd_read subscriptions | Done |
| Cooperative scheduling | `sched_run_single` drains local+global queues, yields on budget exhaustion | Done |
| Task context | `sched_current_task` reads per-worker slot | Done |
| Join parking | `sched_join` registers in join_map, yields; `sched_complete` wakes waiters | Done |

## Migration: WASI Preview 1 → Preview 2

WASI Preview 2 uses the Component Model and replaces `poll_oneoff` with per-resource pollables.

### Key API Differences

| Preview 1 | Preview 2 |
|-----------|-----------|
| `poll_oneoff(in, out, nsubs, nevents) -> errno` | `wasi:io/poll.poll(list<pollable>) -> list<u32>` |
| `clock_time_get(clock_id, precision, out_ptr) -> errno` | `wasi:clocks/monotonic-clock.now() -> instant` |
| `wasi:io/poll.pollable` (fd-based) | `wasi:io/pollable` (first-class resource) |
| `subscription_t` (48 bytes, userdata+type+union) | Per-operation `subscribe-*` methods returning `pollable` |
| Sleep via `poll_oneoff` clock subscription | `wasi:clocks/monotonic-clock.subscribe-duration(ms) -> pollable` |

### Migration Steps

1. **Abstract WASI calls behind a platform layer**
   - Create `camp_wasi_poll`, `camp_wasi_clock`, `camp_wasi_fd_read` wrappers
   - Current code emits WASI calls inline; wrap in separate runtime functions
   - This lets us swap P1 vs P2 implementations at link time

2. **Replace subscription-based polling with pollable-based polling**
   - P1: Build subscription array in linear memory → `poll_oneoff`
   - P2: Build list of pollable handles → `wasi:io/poll.poll`
   - The `sched_poll_and_dispatch` body would emit different WASM depending on target

3. **Replace `clock_time_get` with `monotonic-clock.now`**
   - P1: `clock_time_get(1, 0_i64, out_ptr)` writes i64 to memory
   - P2: `monotonic-clock.now()` returns i64 directly (no out_ptr needed)
   - Simpler calling convention in P2

4. **Replace sleep implementation**
   - P1: Insert into timer wheel + `poll_oneoff` with clock subscription
   - P2: `subscribe-duration(ms)` returns a pollable → add to poll list
   - No timer wheel needed for sleep in P2 (pollable handles the wait)
   - Keep timer wheel for general timeout/cancellation support

5. **Component Model ABI**
   - P2 requires the Component Model (different binary format from core modules)
   - Camp currently emits core WASM modules
   - Need a Component Model emitter or a P2 adapter (Wasmtime provides P1→P2 adapter)

### Ecosystem Readiness (as of 2026-05)

| Runtime | P1 Support | P2 Support | Notes |
|---------|-----------|-----------|-------|
| Wasmtime | Full | Full | Production P2; provides P1→P2 adapter |
| Wasmer | Full | None | P2 issue closed without implementation |
| WasmEdge | Full | Partial | P2 partial; no monotonic-clock yet |
| WAMR | Full | None | P1 only |
| wasm3 | Full | None | P1 only, interpreter |

**Conclusion**: P2 is only viable on Wasmtime today. P1 remains the correct target for portability.

## Migration: WASI Preview 2 → Preview 3 (Async-native)

WASI Preview 3 (hypothetical) would add native async/await to the component model.

### Expected Features
- `wasi:io/async-poll` — native async poll without blocking
- Stream/resource cancellation at the WASM level
- Structured concurrency (task groups/scopes)

### Camp Alignment
- Camp's algebraic effects + CPS transform already provide structured concurrency
- The scheduler loop + cooperative yield maps well to P3's async model
- When P3 arrives, the scheduler loop can be replaced with native WASM async primitives
- The CPS transform may become unnecessary for async (but still needed for effect handlers)

## Known Gaps in Current Implementation

1. **Timer insert not truly atomic** — single-threaded mode doesn't need atomics, but multi-threaded mode needs CAS on slot heads. Current insert uses non-atomic read-then-write.
2. **Timer cascade not implemented** — when level 0 slot cursor wraps, entries from level 1 should cascade down. Currently only level 0 is processed.
3. **Poll timeout subscription missing** — `sched_poll_and_dispatch` builds fd_read subscriptions but not clock subscriptions for timers. This means `poll_oneoff` may block forever if only timers are pending.
4. **Main entry wrapper uses unreachable** — the wrapper function that bridges scheduler calling convention to main!'s evidence-parameter calling convention uses `unreachable` to satisfy the i32 return type. This works but is fragile.
5. **No work-stealing** — `sched_worker_loop` exists but doesn't implement the full multi-threaded work-stealing design. Single-threaded `sched_run_single` is the primary path.
6. **Global queue not bounded** — no overflow handling when global queue reaches capacity.
7. **No task cancellation propagation** — `sched_cancel` sets the handle status but doesn't cancel running tasks or remove timer entries.
8. **No scope-based cancellation** — scope_id is stored in handle entries but not used for hierarchical cancellation.

## References

- [WASI Preview 1 Spec](https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md)
- [WASI Preview 2 Spec](https://github.com/WebAssembly/WASI/blob/main/wasip2/docs.md)
- [Component Model](https://github.com/WebAssembly/component-model)
- [Tokio Scheduler Internals](https://tokio.rs/blog/2019-10-scheduler)

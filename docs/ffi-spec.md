# FFI — Foreign Function Interface (Design Proposal)

**Status: PROPOSAL.** Not implemented. The `@extern`/`@export` syntax is a
candidate and must be ratified in `docs/syntax-recipe.md` before any
compiler work. See also `docs/effects-spec.md`.

## Problem

Camp has no FFI surface. Host interaction is hardcoded in the compiler two
ways: stdlib intrinsics (`crash "intrinsic: …"` pattern-matched in codegen)
and scheduler prelude effects (`Console!`, `File!`, … recognized by name in
`ir/effect_lower.odin`, emitting WASI calls). Neither is extensible without
editing Odin. This proposal replaces both with one *declared* mechanism.

## Core idea

Effects and FFI are separate layers:

- **Handlers** (`handle E! in … with { … }`) are pure Camp and already
  support zero/one/multi-shot resumption. FFI does not touch them.
- **FFI** is only the leaf: a synchronous host call that takes and returns
  values.

> **Invariant: the host is always a leaf.** It never captures or resumes a
> Camp continuation. Every effect = *(Camp handler, any shape) + (host
> leaves)*. Multi-shot composes because Camp drives the resuming and
> re-invokes the leaf.

This is the line OCaml 5, Koka, and Effekt all draw.

## Outbound — Camp calls the host (imports)

`@extern(module, field)` names a WASM import.

```camp
# pure leaf (generalizes intrinsics)
@extern("env", "now_millis")
clock_raw = || -> I64

# effectful leaf (generalizes scheduler effects) — the row IS the capture annotation
Clock! : {
  @extern("wasi_snapshot_preview1", "clock_time_get")
  now! : || -[Clock!]-> I64,
}
```

| Effect shape | Reached via | Status |
|---|---|---|
| I/O leaves (Console, File, Clock, Env) | the extern itself | v1 |
| Abort (`Throw!`) | host returns errno; Camp aborts | v1 |
| State / Reader / Writer / nondeterminism | Camp handler over host leaves | v1 |
| Async / callbacks | scheduler-mediated (`poll_oneoff` is the leaf) | not raw FFI |

Async is excluded by the leaf invariant: foreign code re-entering and
resuming Camp is forbidden. Camp's in-WASM scheduler already handles
`Async!`/`Spawn!` and uses `poll_oneoff`/`sched_yield` as leaves.

## Inbound — the host calls Camp (exports)

Today only `_start`, `memory`, `camp_worker_entry` are exported;
`build/export_table.odin` is Camp's internal module system, not a foreign
ABI. A foreign caller can't speak Camp's effect rows, so:

> **Exports must be effect-closed** — pure, or only host-backed leaf effects
> (the same reason `main!` may carry `-[Console! | Throw!]->`).

**Effect-closed ≠ effect-free.** The function still performs and *handles*
effects internally; the foreign caller just gets the value. To let the host
control an effect's behavior, pass the capability *in* as an import the
handler calls — don't make the host a handler:

```camp
Db! : { query!: |Str| -[Db!]-> Bytes }
@extern("host_db", "exec") host_db_exec = |Str| -> Bytes

pub run_report = || -> Bytes {                 # exported: effect-closed
  handle Db! in work() with {
    .query!(resume, sql) => resume(host_db_exec(sql))
  }
}
```

The host owns the *capability* (import); Camp owns the *handler*. Neither
direction carries an unhandled effect. Forbidden in both directions: foreign
code acting as a handler that resumes a Camp continuation (breaks
one-shot/RC soundness; no two languages share an effect ABI anyway).

## Implementation sketch

1. Parse `@extern`/`@export` attributes (`frontend/`).
2. Type-check extern signatures as declared; verify rows + WASM-representable
   types (`semantics/`). Reject effect-open exports.
3. IR: `IR_Extern_Call`; effectful externs bypass CPS like scheduler effects
   (`ir/`).
4. Codegen: replace the hardcoded WASI table with a registry that dedupes
   `(module, field, sig)` into `Wasm_Import`s (`codegen/`).
5. Dogfood: migrate prelude scheduler effects + stdlib intrinsics onto it.
6. Tests under `tests/e2e/`; update kitchen-sink once syntax is ratified.

v1 marshaling: `I32/I64/F32/F64` and `Str`/`Bytes` as ptr+len (as `fd_write`
already does). Records/variants/resources await a WIT/Component-Model phase.

## Open decisions (need owner sign-off; record in syntax-recipe §14)

1. `@extern`/`@export` syntax — `@` is currently reserved for nominal types
   and derives.
2. Pure-extern enforcement, or drop the pure tier (all externs effectful).
3. Async externs out of scope for v1 (recommended) vs. an Effekt-style
   `async` capture.
4. RC ownership convention for `Str`/`Bytes` across the boundary, both ways.
5. WIT / Component Model as the longer-term target.

## Non-goals

- GC or runtime deps (Perceus preserved).
- Foreign code capturing/resuming Camp continuations (either direction).
- Effect-open exports.
- Dynamic loading; imports resolve at WASM link time.

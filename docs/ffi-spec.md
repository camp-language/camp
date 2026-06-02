# FFI — Foreign Function Interface (Design Proposal)

## Status

**PROPOSAL — not yet implemented, syntax not yet ratified.**

This document is a design proposal, not a behavioral specification. The
surface syntax described here (`@extern(...)`) is a *candidate* and MUST be
recorded in `docs/syntax-recipe.md` before any parser or compiler work
begins — per `AGENTS.md`, the recipe is the single source of truth for
syntax and no syntax may be added to the compiler or specs without first
recording the decision in the recipe. Open decisions are tracked in the
"Open Decisions" section below.

For the effect system this builds on, see `docs/effects-spec.md`. For the
compilation pipeline, see `docs/compiler-spec.md`.

## Purpose

Define how Camp interoperates with the host platform in a way that
integrates with — rather than bypasses — the algebraic effect system,
covering both directions: **outbound** (Camp calling the host via WASM
imports / WASI) and **inbound** (another language calling a Camp export).
The goal is to generalize the two host-interaction mechanisms that exist
today (hardcoded stdlib intrinsics and hardcoded "scheduler" prelude
effects) into a single *declared* mechanism, without weakening effect
tracking, strict typing, or Perceus reference-counting semantics.

## Current State (what this proposal generalizes)

Camp has **no FFI surface syntax** today. All host interaction is hardcoded
in the Odin compiler:

1. **Stdlib intrinsics** — a stdlib function writes `crash "intrinsic:
   Str.length"` as its body. The `crash` is never reached; codegen
   (`src/codegen/emit_expr.odin`, the `IR_Call` path) pattern-matches the
   module-qualified callee name against a fixed list and emits a direct
   runtime call. The binding lives in the codegen switch, not the language.

2. **Scheduler prelude effects** — `Console!`, `File!`, `Time!`, `Async!`,
   `Spawn!`, `Parallel!` are recognized by name in
   `src/ir/effect_lower.odin` (`is_scheduler_effect`). Their `IR_Perform`
   nodes bypass the CPS handler transform and pass straight to codegen,
   which emits direct WASM calls (e.g. `Console.println!` builds an iovec
   in scratch memory and calls the `fd_write` WASI import). The 9 WASI
   preview1 imports are fixed in `emit_wasi_imports()`
   (`src/codegen/codegen.odin`).

Neither mechanism is extensible without editing the Odin compiler.

## Core Model: FFI Is the Leaf, Not the Handler

Camp's effect handlers (`handle E! in <body> with { ... }`) already support
every resumption multiplicity — this is pure-Camp CPS machinery
(`src/ir/cps.odin`), exercised by the e2e tests:

```camp
.read!(resume)         => resume(42)          # one-shot
.read!(resume)         => resume(resume(1))   # multi-shot
.throw!(resume, _code) => 1                   # zero-shot (abort)
```

FFI does not touch this. The design rests on a single invariant:

> **The host is always a leaf.** A foreign function produces and consumes
> *values*. It never captures, holds, or resumes a Camp continuation.

Every effect therefore decomposes as **(a Camp handler of any resumption
multiplicity) + (synchronous host leaves)**. Multi-shot effects compose
with FFI because *Camp* drives the resuming and simply re-invokes the
(re-runnable) host leaf each time; the host is unaware it sits inside a
continuation.

This is the same boundary drawn by OCaml 5, Koka, and Effekt: you cannot
resume through a host stack frame you do not own. Effekt names the sole
exception explicitly — only `async`-captured externs may touch the
continuation, and they are special-cased. Camp adopts the same stance (see
"Asynchrony" below).

## Surface Syntax (candidate)

A foreign declaration is an effect operation (or pure function) whose body
is a host call rather than Camp code. The `@extern(module, field)`
attribute names the WASM import.

### Tier 1 — pure / leaf foreign function (generalizes intrinsics)

```camp
@extern("env", "now_millis")
clock_raw = || -> I64
```

A pure extern has no effect row and is intrinsic-like (candidate for
inlining). It MUST be referentially transparent; if it is not, it belongs
in Tier 2.

### Tier 2 — effectful foreign operation (generalizes scheduler effects)

The extern attribute sits on an operation inside an effect declaration. The
effect row on the signature carries the effect — this *is* the capture
annotation (cf. Effekt's `at io`), reusing Camp's existing effect-row
machinery rather than a separate capture lattice.

```camp
Clock! : {
  @extern("wasi_snapshot_preview1", "clock_time_get")
  now! : || -[Clock!]-> I64,
}
```

No user-level handler is required: the `@extern` *is* the handler, and it
is the host. The operation resumes exactly once, synchronously. This is
precisely what today's `Console.println!` → `fd_write` does, declared
instead of hardcoded.

## How Each Effect Class Is Supported

| Effect shape | Handler | How the host is reached | Status |
|---|---|---|---|
| I/O leaves (Console, File, Clock, Env, Random) | the extern itself | direct `@extern` host call | proposed v1 |
| Error / abort (`Throw!`) | zero-shot Camp handler | host returns errno; Camp aborts | proposed v1 |
| State, Reader, Writer, Logging | one-shot Camp handler | bottoms out in I/O leaves | proposed v1 |
| Nondeterminism, generators, backtracking | multi-shot Camp handler | re-runs host leaves | proposed v1 |
| Async / callbacks (host resumes Camp) | scheduler (not a raw extern) | scheduler suspends/resumes; `poll_oneoff` is a leaf | scheduler-mediated |

### Leaf host effect (operation *is* the host call)

```camp
Clock! : {
  @extern("wasi_snapshot_preview1", "clock_time_get")
  now! : || -[Clock!]-> I64,
}
```

### Multi-shot effect over host leaves (composes cleanly)

```camp
Choose! : { pick!: |I64, I64| -[Choose!]-> I64 }

explore = || -[Console!]-> {} {
  handle Choose! in {
    x = Choose!.pick!(1, 2)
    Console.println!("trying ${x}")     # host leaf — runs once per resume
  } with {
    .pick!(resume, a, b) => { resume(a); resume(b); {} }   # multi-shot
  }
}
```

The host leaf (`println!` → `fd_write`) is invoked twice because the *Camp*
handler resumes twice. The host never knew it was inside a multi-shot
continuation.

### Abort/error composes with fallible host calls

Foreign functions **return** errors (errno-style); they never unwind Camp's
stack.

```camp
File! : {
  @extern("wasi_snapshot_preview1", "fd_read")
  read! : |I32| -[File!]-> Result(Bytes, I32),
}

readOrDie = |fd| -[File! | Throw!(I64)]-> Bytes {
  match File!.read!(fd) {
    Ok(b)  => b
    Err(e) => Throw!.throw!(e)    # zero-shot handler discards continuation
  }
}
```

### Asynchrony — the one capability `@extern` does NOT grant

A plain `@extern` leaf cannot express foreign code that re-enters Camp and
resumes a suspended continuation (a JS `setTimeout` callback, an
epoll-driven socket read). This is forbidden by the leaf invariant.

Camp already handles this correctly *without* FFI doing it: `Async!`,
`Spawn!`, and `Parallel!` are handled by Camp's in-WASM scheduler, which
suspends and resumes Camp continuations itself and uses leaf FFI
(`poll_oneoff`, `sched_yield`) only to *block*. The rule holds one level
up: **the scheduler is the handler; `poll_oneoff` is a leaf.** Direct
host→Camp resumption stays forbidden; the scheduler mediates it.

## Direction: Inbound Calls (Exports)

Everything above is the *outbound* direction — Camp calling the host via
imports. The *inbound* direction — another language calling a Camp function
— is a separate, asymmetric problem.

### Current state

Camp emits only three WASM exports today (`src/codegen/emit_start.odin`,
`src/codegen/codegen.odin`): `_start` (the WASI command entry wrapping
`main!`), `memory`, and `camp_worker_entry` (scheduler workers). The
`Export_Table` in `src/build/export_table.odin` is **not** a foreign ABI —
it is purely Camp's *internal* module system, resolving `pub`
consts/effects/traits between `.camp` files (`Export_Kind` =
`Const/Effect/Trait/Alias/Newtype`). There is no mechanism to expose an
arbitrary `pub` Camp function to a Rust/JS caller.

### A handler is an interpreter; it lives in the language that owns the effect

A foreign caller has no notion of a Camp effect row — it cannot typecheck
`-[Db!]->`, install a handler in a form Camp's CPS machinery understands, or
reason about resumption. Effects are intrinsically a Camp-internal concept.
So the boundary rule mirrors the outbound leaf invariant:

> **Effects never cross the boundary as an obligation on the foreign side.**
> On import, the host cannot *perform* Camp effects. On export, the foreign
> caller cannot *handle* them. Effects are always discharged on the Camp
> side — by Camp handlers, or by host-backed leaf imports.

This is the standard FFI discipline for any effect/monad system, not a Camp
limitation: Haskell cannot export an unhandled `IO a` for C to "run" (the
RTS runs it; C sees `a`); OCaml 5 cannot export an unhandled effectful
computation for C to supply the handler. Run/handle it in the language that
understands the effect, then hand a value across.

### What an export may carry: effect-closed signatures

An exported Camp function MUST be **effect-closed**: its signature is pure,
*or* its only residual effects are **host-backed leaves** (`Console!`,
`File!`, `Clock!`, …) that resolve to imports. This is exactly why `main!`
is already allowed the row `-[Console! | Throw!([..])]->` — those resolve to
host-backed leaves (WASI), not to a Camp handler.

### Effect-closed ≠ effect-free

This is the crux, and the reason exports do **not** defeat the purpose of
effects. An effect-closed export may still:

- **Perform any effect internally and handle it itself** — `State!`,
  nondeterminism, retries, logging. The effects *happen*; the effect system
  did its entire job (tracking, sequencing, handler-based interpretation,
  mockability) *inside that call*. The foreign caller simply receives the
  result, the same way it does not participate in Camp's type inference or
  Perceus RC.
- **Route residual effects to host-backed leaves**, so real I/O still
  reaches the host via the import direction that works.

### The host can still inject behavior — as a capability, via imports

The case to worry about is "what if Rust wants to control how a Camp effect
behaves?" That works — not by making the host a handler, but by making the
host a **leaf the Camp handler calls**. Invert it:

```camp
Db! : { query!: |Str| -[Db!]-> Bytes }

@extern("host_db", "exec")            # host provides the capability as a leaf
host_db_exec = |Str| -> Bytes

# Camp owns the handler (the interpreter); the host owns the capability
runWithDb = |work| {
  handle Db! in work() with {
    .query!(resume, sql) => resume(host_db_exec(sql))
  }
}

pub run_report = || -> Bytes {        # exported: effect-closed
  runWithDb(|| { ... Db!.query!("select ...") ... })
}
```

Rust calls `run_report`. Inside, Camp performs `Db!`, the **Camp handler**
interprets it, and the actual database work is done by the **host import**
`host_db_exec`. The host fully controls behavior — but as a capability
passed *in* via imports, with Camp's handler as the mediator. The effect
typing stays meaningful end to end: `Db!` was tracked and sequenced, and the
handler chose to route it to the host.

> The export carries values. The imports carry capabilities. The Camp side
> owns the handler. Neither direction carries an unhandled effect obligation.

### What is genuinely not possible (and why it is a feature)

A foreign caller cannot be a **transparent effect handler that resumes Camp
continuations** — e.g. Rust calling `f : || -[Ask!]-> I64` and Rust itself
being the `Ask!` handler that resumes. That would require the host to
implement Camp's continuation protocol and hold a Camp continuation across
the boundary — the same unsoundness the outbound leaf invariant forbids,
which would break Camp's one-shot/RC semantics. The capability-as-import
pattern above delivers everything *useful* about that without it. (No two
languages share an effect ABI in any case; effect-polymorphic composition
across a WASM boundary was never on the table for any language.)

### Memory / RC ownership (both directions)

`Str`/`Bytes` crossing the boundary need an ownership convention consistent
with Perceus, in *both* directions: who frees a buffer the foreign caller
passes in, and who owns a buffer Camp returns. The v1 leaf convention (see
Type Marshaling) must be stated symmetrically for exports — left as an open
decision below.

## Implementation Sketch (smallest viable cut)

1. **Parser / AST** (`src/frontend/`): parse `@extern("mod", "field")` as an
   attribute on `Decl_Fn` and on effect-operation signatures.
2. **Semantics** (`src/semantics/`): take the `@extern` signature as
   declared (not inferred, like Effekt). Verify the effect row is
   well-formed and that parameter/return types are WASM-representable using
   existing `lower_type` / `wasm_type` machinery.
3. **IR** (`src/ir/`): represent externs with an `IR_Extern_Call` (or a
   tagged `IR_Perform`) carrying `(module, field, type)`. Effectful externs
   route exactly as `is_scheduler_effect` does today — bypass CPS.
4. **Codegen** (`src/codegen/`): replace the hardcoded WASI import table
   with a *registry* — collect every `@extern` `(module, field,
   signature)`, dedupe, emit one `Wasm_Import` per unique pair via the
   existing `add_import()`, and emit `Wasm_Call{import_index}` at the call
   site.
5. **Dogfood**: migrate the prelude scheduler effects and the stdlib
   intrinsics onto the declared mechanism so the codegen switch shrinks and
   the feature is exercised by the whole stdlib.
6. **Tests**: add e2e coverage under `tests/e2e/effects/` (leaf extern,
   multi-shot over a leaf, fallible extern + `Throw!`) and update the
   kitchen-sink test once syntax is ratified.

## Type Marshaling (v1 scope)

v1 restricts foreign signatures to WASM-native types plus Camp types with
stable layouts: `I32`/`I64`/`F32`/`F64`, and `Str`/`Bytes` as a
pointer+length pair in linear memory (exactly what `fd_write` already
uses). Records, tag unions, and resource handles wait for a future
Component-Model / WIT direction (see below).

## Open Decisions

These need the project owner's sign-off and must be recorded in
`docs/syntax-recipe.md` (§14 TBD) before implementation:

1. **Attribute syntax.** Is `@extern("mod", "field")` the right surface?
   Note `@` is currently reserved for nominal-type construction/destruction
   and derive clauses only (per the recipe) — adding an `@extern` attribute
   form is a syntax extension that must be ratified.
2. **Pure-extern purity enforcement.** How (if at all) does the compiler
   prevent a Tier-1 pure extern from being effectful in practice? Options:
   trust the author; require all externs be Tier-2 (effectful) and drop the
   pure tier.
3. **Async/continuation-capturing externs.** Confirm these are out of scope
   for v1 and always mediated by the scheduler (recommended), versus a
   future Effekt-style `async`-capture annotation.
4. **WIT / Component Model alignment.** Whether the longer-term target is
   WASI preview2/0.3 typed interfaces (worlds, resources, async), and
   whether `@extern` should eventually be generated from `.wit` rather than
   hand-written.
5. **Export surface.** How a `pub` Camp function is marked for export to a
   foreign caller (e.g. an `@export("name")` attribute), and how the
   compiler enforces the *effect-closed* requirement on exported signatures
   (reject any residual effect that is not pure or a host-backed leaf).
6. **RC ownership convention across the boundary.** The symmetric rule for
   who owns/frees `Str`/`Bytes` passed in by a foreign caller versus
   returned by Camp, consistent with Perceus.

## Non-Goals

- Garbage collection or any runtime dependency (Perceus RC is preserved;
  ownership of `Str`/`Bytes` passed across the boundary follows existing RC
  rules).
- Allowing foreign code to capture or resume Camp continuations directly
  (in either direction — host as handler of a Camp export is forbidden).
- Exporting effect-open Camp functions (signatures with unhandled
  user-defined effects); exports must be effect-closed.
- Dynamic loading / `dlopen`-style FFI — all imports are resolved at WASM
  link time.

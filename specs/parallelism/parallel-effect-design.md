# Parallel Effect Design Specification

> *"Make the common case fast, make the unsafe case explicit."*

## Table of Contents

1. [Overview](#1-overview)
2. [Design Philosophy](#2-design-philosophy)
3. [Effect Definition](#3-effect-definition)
4. [Collection Method Sugar](#4-collection-method-sugar)
5. [Block Syntax Sugar](#5-block-syntax-sugar)
6. [Handler Semantics](#6-handler-semantics)
7. [Effect Row Composition](#7-effect-row-composition)
8. [Type System Rules](#8-type-system-rules)
9. [Sequential Handler (Reference)](#9-sequential-handler-reference)
10. [Runtime Handler (Auto-Install)](#10-runtime-handler-auto-install)
11. [WASM/WASI Mapping](#11-wasmwasi-mapping)
12. [Implementation Plan](#12-implementation-plan)
13. [Open Questions](#13-open-questions)
14. [References](#14-references)

---

## 1. Overview

The `Parallel` effect provides data-parallelism operations for Camp — applying functions across collections in parallel. It is Camp's primary mechanism for expressing parallel intent: the caller says "apply this function to every element," and the handler decides whether to run sequentially, on a thread pool, or with SIMD.

**Key insight**: Camp's effect system separates *what* to compute from *how* to execute it. The `Parallel` effect expresses parallel *intent*; the handler chooses the *strategy*. This makes parallel code:

- **Safe**: No data races (Camp has no shared mutable state)
- **Explicit**: `Parallel` in the effect row tells the reader "this code runs in parallel"
- **Composable**: `Parallel` + `Async` + `Throw` compose naturally via effect rows
- **Portable**: Sequential handler works everywhere; thread-pool handler works on multi-core
- **Gradual**: Start with sequential, swap to parallel by changing the handler

### Relationship to Other Effects

| Effect | Purpose | Execution |
|--------|---------|-----------|
| `Async` | I/O concurrency (overlap I/O operations) | Cooperative coroutines on one thread |
| `Parallel` | Data parallelism (parallelize across collection) | Thread pool or sequential |
| `Spawn` | Task parallelism (independent computations on separate cores) | Separate OS threads / WASM instances |

`Parallel` is data-parallelism: one operation applied to many elements. `Spawn` is task-parallelism: different operations on different cores. `Async` is concurrency: overlapping I/O without blocking.

---

## 2. Design Philosophy

### 2.1 Effects Express Intent, Handlers Choose Strategy

The `Parallel` effect does NOT mean "this code MUST run in parallel." It means "this code *intends* parallel execution — the handler may run it sequentially, on a thread pool, with SIMD, or distributed."

This is the same pattern as all Camp effects:
- `Console.println!` — the handler decides where to print (stdout, stderr, /dev/null, captured buffer)
- `Throw.throw!` — the handler decides what to do with the error (log, abort, convert to Result)
- `Parallel.map!` — the handler decides how to distribute work (sequential, thread-pool, SIMD)

### 2.2 No Shared Mutable State = No Data Races

Camp's stack-local mutation model means functions passed to `Parallel.map!` cannot share mutable data. Every value is immutable unless explicitly copied and mutated within a stack-local `$` binding. This eliminates data races by construction — no locks, no atomics, no mutex needed for the user's code.

### 2.3 Effect Row Propagation

If the function `f` passed to `Parallel.map!` is itself effectful (e.g., it performs `Throw` or `Async`), those effects propagate through the `Parallel` operation and appear in the caller's effect row. The handler must handle or propagate all of them.

### 2.4 Method Sugar for Ergonomics

`Parallel.map!` is the primitive — it lives on the effect and always appears in the effect row. Collection method sugar (`list.par_map!`) provides a more ergonomic spelling. Both are equivalent; the effect system tracks `Parallel` either way.

---

## 3. Effect Definition

```camp
effect Parallel {
  -- Apply f to each element of items, return results in order
  map! : <a, b>|items: List(a), f: |a| -> b| -[Parallel]-> List(b)

  -- Apply f to each element, discard results (side-effecting)
  for_each! : <a>|items: List(a), f: |a| ->{}| -[Parallel]-> {}

  -- Filter items in parallel, preserving order
  filter! : <a>|items: List(a), predicate: |a| -> Bool| -[Parallel]-> List(a)

  -- Reduce items using associative operator
  reduce! : <a, b>|items: List(a), init: b, f: |b, a| -> b| -[Parallel]-> b

  -- Run N independent computations in parallel, return all results
  all! : <a>|tasks: List(|| -> a)| -[Parallel]-> List(a)

  -- Run N computations in parallel, return first successful result
  any! : <a, e>|tasks: List(|| -[Throw(e)]-> a)| -[Parallel | Throw(e)]-> a
}
```

### 3.1 Operation Semantics

| Operation | Semantic Guarantee | Ordering |
|-----------|-------------------|----------|
| `map!` | Apply `f` to every element of `items`; result list has same length and order as `items` | Results are in the same order as input (regardless of execution order) |
| `for_each!` | Apply `f` to every element; no return value | Order of side effects is NOT guaranteed (handler may reorder) |
| `filter!` | Return elements where `predicate` returns `True`, in original order | Results preserve input order |
| `reduce!` | Apply `f` cumulatively: `f(f(f(init, x0), x1), x2)...` | `f` MUST be associative for parallel correctness. Sequential handler folds left. Parallel handler may fold in parallel tree. |
| `all!` | Execute every task; return list of results in input order | Results in input order |
| `any!` | Execute tasks in parallel; return first successful result; cancel remaining tasks | Returns result of whichever task succeeds first |

### 3.2 Effect Propagation Through Operations

Each operation propagates the inner function's effects into the caller's effect row:

```camp
-- f is pure:
Parallel.map!(items, |x| x + 1)
-- Effect row: { Parallel }

-- f throws:
Parallel.map!(items, |x| might_throw!(x))
-- Effect row: { Parallel, Throw(E) }

-- f does async I/O:
Parallel.map!(items, |name| File.read!(name))
-- Effect row: { Parallel, File, Throw(IoError) }
```

This is standard effect polymorphism — the `Parallel` effect operations propagate whatever effects the user's function carries.

### 3.3 `reduce!` and Associativity

For sequential execution, `reduce!` is a left fold: `f(f(f(init, a0), a1), a2)...`. For parallel execution, the handler may split the list into chunks, reduce each chunk, then combine — requiring `f` to be associative.

**Camp does NOT enforce associativity at the type level** (this is undecidable in general). Instead:

1. The documentation states that `reduce!` requires an associative `f` for parallel correctness
2. The sequential handler always folds left (correct regardless of associativity)
3. The parallel handler may fold in any order (correct only if `f` is associative)
4. If the programmer needs guaranteed left-to-right order, use `items.iter().fold(init, f)` instead

**Design decision**: Do not add an `Associative` trait. Enforcing associativity at the type level adds significant complexity for marginal benefit. The same tradeoff exists in every parallel reduce API (Rust's `rayon::reduce`, Java's `ParallelStream.reduce`, etc.) — none enforce it statically.

---

## 4. Collection Method Sugar

### 4.1 List Methods

The `List(a)` type gains parallel-aware methods that desugar to `Parallel` effect operations:

| Method | Desugars to | Effect Row |
|--------|------------|------------|
| `list.par_map!(f)` | `Parallel.map!(list, f)` | `-[Parallel \| ...]->` |
| `list.par_filter!(p)` | `Parallel.filter!(list, p)` | `-[Parallel]->` |
| `list.par_reduce!(init, f)` | `Parallel.reduce!(list, init, f)` | `-[Parallel]->` |
| `list.par_for_each!(f)` | `Parallel.for_each!(list, f)` | `-[Parallel]->` |

### 4.2 Desugaring at Canonicalization

Method sugar desugars at canonicalization (the same phase where dot lambdas and `@derive` expand). The surface AST preserves the method call form for tooling (formatter, LSP, error messages); the canonical AST and later stages see the `Parallel.map!` call.

### 4.3 Method Chaining

```camp
records.par_map!(|r| process!(r))
       .par_filter!(|r| r.is_valid())
       .par_reduce!(0, |acc, r| acc + r.score)
```

Each method call desugars to a `Parallel` operation. The effect row accumulates: `-[Parallel | ...]->`. Method chaining works because `par_map!` returns `List(b)`, which has `par_filter!`, etc.

### 4.4 Other Collection Types

Future collection types (`Map`, `Set`, `Iter`) can also implement parallel methods:

| Type | Methods |
|------|---------|
| `Map(k, v)` | `par_map_values!`, `par_for_each!` |
| `Set(a)` | `par_map!`, `par_for_each!`, `par_filter!` |
| `Iter(a)` | `par_collect!` (parallel terminal operation) |

These are deferred — implement for `List` first, extend later.

---

## 5. Block Syntax Sugar

### 5.1 `par { }` Block

```camp
result = par {
  compute_alpha!(),
  compute_beta!(),
  compute_gamma!()
}
```

**Desugars to**:

```camp
result = Parallel.all!([|| compute_alpha!(), || compute_beta!(), || compute_gamma!()])
```

**Semantics**: Each expression in the block is wrapped in a zero-argument lambda and passed to `Parallel.all!`. The handler decides whether to execute them sequentially or in parallel. Results are returned as a tuple matching the block's expression order.

**Return type**: `(Alpha, Beta, Gamma)` — a tuple of the return types of each expression.

### 5.2 `par for` Block

```camp
par for r in records {
  process_record!(r)
}
```

**Desugars to**:

```camp
Parallel.for_each!(records, |r| process_record!(r))
```

**Semantics**: The body is applied to each element. Order of execution is not guaranteed. Return value is `{}` (unit).

### 5.3 Parsing

| Syntax | Parse Rule |
|--------|-----------|
| `par { e1, e2, e3 }` | `Expr_Par_Block` with `expressions: [dynamic]Expr` |
| `par for name in expr { body }` | `Expr_Par_For` with `name: Intern_ID`, `iterator: Expr`, `body: Expr` |

The `par` keyword is added to the lexer. It is NOT a type or tag (lowercase), so it doesn't conflict with the UpperCamelCase convention.

### 5.4 `par` Block vs Explicit `Parallel.all!`

The `par` block is pure sugar. It provides two benefits:
1. **Visual clarity**: The parallel structure is immediately visible
2. **Tuple result**: Returns `(A, B, C)` instead of `List(a)` — types are preserved

The tradeoff: `par { }` is limited to a fixed number of expressions known at compile time. `Parallel.all!` accepts a dynamically-sized list. Use `par { }` for 2-10 concurrent tasks; use `Parallel.all!` for dynamic lists.

---

## 6. Handler Semantics

### 6.1 Sequential Handler (Default / Fallback)

The sequential handler runs everything on the calling thread, one element at a time. It is correct, deterministic, and works everywhere — including single-threaded WASM runtimes without WASM threads support.

```camp
handle Parallel in {
  records.par_map!(|r| process!(r))
} with {
  .map!(resume, items, f) => resume(items.iter().map(f).collect())
  .filter!(resume, items, pred) => resume(items.iter().filter(pred).collect())
  .reduce!(resume, items, init, f) => resume(items.iter().fold(init, f))
  .for_each!(resume, items, f) => {
    items.iter().for_each(f)
    resume({})
  }
  .all!(resume, tasks) => resume(tasks.iter().map(|t| t()).collect())
  .any!(resume, tasks) => handle_any_sequential(tasks, resume)
}
```

**Key property**: The sequential handler preserves the same semantics as the parallel handler. A program that is correct with the sequential handler is also correct with the parallel handler (assuming `reduce!`'s `f` is associative).

### 6.2 Thread-Pool Handler (Runtime-Provided)

The thread-pool handler distributes work across N worker threads. It is installed automatically by the Camp runtime when `Parallel` appears in `main!`'s effect row.

```
┌─────────────────────────────────────────────────────┐
│  Thread-Pool Handler                                │
│                                                     │
│  Parallel.map!(items, f) →                          │
│    1. Split items into N chunks (N = thread count)  │
│    2. Enqueue each chunk as a task                  │
│    3. Workers pick up chunks, apply f to each item  │
│    4. Collect chunk results, concatenate in order    │
│    5. resume(concatenated_results)                  │
│                                                     │
│  Parallel.reduce!(items, init, f) →                 │
│    1. Split items into N chunks                     │
│    2. Each chunk reduces locally                    │
│    3. Combine partial results pairwise (tree reduce)│
│    4. resume(final_result)                          │
│                                                     │
│  Parallel.all!(tasks) →                             │
│    1. Enqueue each task as-is                       │
│    2. Workers pick up tasks, execute them           │
│    3. Collect results in input order                │
│    4. resume(results)                              │
│                                                     │
│  Parallel.any!(tasks) →                            │
│    1. Enqueue all tasks                             │
│    2. On first successful completion:              │
│       a. Record result                             │
│       b. Cancel remaining tasks                    │
│       c. resume(result)                            │
│    3. If all tasks fail: Throw the last error       │
└─────────────────────────────────────────────────────┘
```

**Implementation**: The thread-pool handler uses the `Spawn` effect under the hood. `Parallel.map!` splits work into chunks, `Spawn.spawn!`s each chunk, `Spawn.join!`s the results, and concatenates.

### 6.3 Handler Guarantees

| Guarantee | Sequential | Thread-Pool |
|-----------|-----------|-------------|
| **Result order** | Preserved | Preserved |
| **Determinism** | Fully deterministic | Non-deterministic execution order, deterministic result order |
| **Side effect order** (`for_each!`) | Left-to-right | NOT guaranteed |
| **Error propagation** | First error stops | First error or all errors (handler choice) |
| **Cancellation** | N/A (no parallelism) | `any!` cancels remaining on first success |

---

## 7. Effect Row Composition

### 7.1 Pure Parallel

```camp
square_all = |nums: List(I64)| -[Parallel]-> List(I64) {
  nums.par_map!(|x| x * x)
}
```

Effect row: `{ Parallel }` only. No other effects.

### 7.2 Parallel + Throw

```camp
parse_all = |inputs: List(Str)| -[Parallel | Throw(ParseError)]-> List(I64) {
  inputs.par_map!(|s| parse_int!(s))
}
```

The inner function `parse_int!` has `Throw(ParseError)` in its effect row. `par_map!` propagates it. The caller must handle or propagate both `Parallel` and `Throw`.

### 7.3 Parallel + Async

```camp
fetch_all = |urls: List(Str)| -[Parallel | Async | Http | Throw(HttpError)]-> List(Str) {
  urls.par_map!(|url| Http.get!(url))
}
```

The inner function does async I/O. `par_map!` propagates all its effects. The handler must handle both `Parallel` and `Async` (and their transitive effects).

### 7.4 Effect Row Subsumption

A function with `-[Parallel | Async | Http | Throw(HttpError)]->` can be called in a context that handles a superset of those effects. For example, `main!` with `-[Parallel | Async | Http | Console | Throw([..])]->` can call `fetch_all` because its effect row is a subset.

---

## 8. Type System Rules

### 8.1 Parallel Effect in Function Types

Any function that calls a `Parallel` operation directly or transitively must have `Parallel` in its effect row:

```camp
-- Direct call:
process = |data: List(Int)| -[Parallel]-> List(Int) {
  data.par_map!(|x| expensive(x))
}

-- Transitive call:
pipeline = |data: List(Int)| -[Parallel | Console]-> {} {
  results = process(data)     -- process has Parallel in its row
  Console.println!("Done")
}
```

### 8.2 Effect Polymorphism in Parallel Operations

The function `f` passed to `Parallel.map!` may carry an effect variable `e`:

```camp
-- e propagates through par_map:
apply_all = <a, b, e>|items: List(a), f: |a| -[e]-> b| -[Parallel | e]-> List(b) {
  items.par_map!(f)
}
```

If `f` is pure, `e` is empty and `apply_all` has only `Parallel`. If `f` throws, `e` includes `Throw(E)`.

### 8.3 `!` Naming Convention

All `Parallel` operations carry `!` because they are effectful:

- `Parallel.map!` — not `Parallel.map`
- `list.par_map!` — not `list.par_map`

A function that calls `Parallel` operations must have `!` in its name:

```camp
process_all! = |records: List(Record)| -[Parallel | Throw(IoError)]-> List(Result) {
  records.par_map!(|r| process!(r))
}
```

### 8.4 No-Shared-Mutation Enforcement

The typechecker enforces that functions passed to `Parallel` operations cannot capture `$`-prefixed mutable bindings from enclosing scopes. This is already enforced by Camp's stack-local mutation model — `$` bindings cannot escape their function scope, so they cannot be captured by closures passed to `Parallel.map!`.

```camp
-- ERROR: $counter cannot be captured by the closure
broken! = |items: List(Int)| -[Parallel]-> I64 {
  $counter = 0
  items.par_map!(|x| { $counter = $counter + 1; x * 2 })
  -- ↑ Error: $counter is captured across a parallel boundary
}
```

This error falls out naturally from the existing stack-local mutation rules — no new enforcement needed.

---

## 9. Sequential Handler (Reference)

The sequential handler is the reference implementation. It proves the semantics and works everywhere.

```camp
sequential_parallel = || ->{} {
  handle Parallel in {
    -- user code here
  } with {
    .map!(resume, items, f) => {
      resume(items.iter().map(f).collect())
    }
    .filter!(resume, items, pred) => {
      resume(items.iter().filter(pred).collect())
    }
    .reduce!(resume, items, init, f) => {
      resume(items.iter().fold(init, f))
    }
    .for_each!(resume, items, f) => {
      items.iter().for_each(f)
      resume({})
    }
    .all!(resume, tasks) => {
      resume(tasks.iter().map(|t| t()).collect())
    }
    .any!(resume, tasks) => {
      -- Try each task; return first success, or last error if all fail
      last_err = None
      result = None
      for task in tasks.iter() {
        match handle Throw in {
          Some(task())
        } with {
          .throw!(resume, err) => {
            last_err = Some(err)
            None
          }
        } -> {
          Some(value) => { result = Some(value); break }
          None => {}
        }
      }
      match result {
        Some(value) => resume(value)
        None => match last_err {
          Some(err) => Throw.throw!(err)
          None => Throw.throw!(NoTasks)
        }
      }
    }
  }
}
```

---

## 10. Runtime Handler (Auto-Install)

When `main!` has `Parallel` in its effect row, the Camp runtime installs the thread-pool handler automatically — following the same pattern as `Console`, `Throw`, and other effects.

### 10.1 Thread Count

| Source | Priority | Default |
|--------|----------|---------|
| `--threads=N` CLI flag | Highest | — |
| `CAMP_THREADS` environment variable | Medium | — |
| `num_cpus()` (runtime detection) | Lowest | Number of CPU cores |

### 10.2 Fallback When No Threads Available

If the WASM runtime doesn't support WASM threads AND the Camp CLI is not running in multi-instance mode, the runtime falls back to the sequential handler. The `Parallel` effect still works — it just runs sequentially.

```camp
-- This program works everywhere — even in single-threaded WASM:
main! = || -[Parallel | Console | Throw([..])]-> I64 {
  results = records.par_map!(|r| process(r))
  Console.println!("Processed ${results.len()} records")
  0
}
-- On multi-core wasmtime: runs in parallel
-- On single-threaded runtime: runs sequentially (still correct)
```

### 10.3 Runtime Handler Selection

```
┌────────────────────────────────────────────────────────┐
│  Runtime Handler Selection for Parallel                │
│                                                        │
│  Is WASM threads available?                            │
│    Yes → Use in-process thread-pool handler            │
│         (Phase 5: SharedArrayBuffer + atomics)         │
│    No ↓                                                │
│                                                        │
│  Is multi-instance available?                          │
│    Yes → Use multi-instance Spawn-based handler        │
│         (Phase 3-4: N stores on N OS threads)          │
│    No ↓                                                │
│                                                        │
│  Use sequential handler                               │
│  (Phase 2: single-threaded, works everywhere)          │
└────────────────────────────────────────────────────────┘
```

---

## 11. WASM/WASI Mapping

### 11.1 Current State (Sequential Handler)

The `Parallel` effect compiles through the existing evidence-passing pipeline:

1. `Parallel.map!` → `IR_Perform` with effect name `Parallel` and operation `map!`
2. Evidence passing passes handler closures as extra arguments
3. CPS captures continuation at the perform site
4. The handler body runs on the calling thread

No new IR nodes or WASM features required.

### 11.2 Phase 3-4 (Multi-Instance Thread Pool)

```
┌──────────────────────────────────────────────────────────┐
│  Camp CLI (host process)                                  │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │ Store 0  │  │ Store 1  │  │ Store 2  │  ...          │
│  │ Thread 0 │  │ Thread 1 │  │ Thread 2 │               │
│  │ (wasmtime)│  │ (wasmtime)│  │ (wasmtime)│              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
│       │             │             │                       │
│  ┌────▼─────────────▼─────────────▼────┐                 │
│  │  Host orchestration (Odin/C/Rust)   │                 │
│  │  - Work queue (thread-safe)         │                 │
│  │  - Result collection                │                 │
│  │  - Closure serialization            │                 │
│  └─────────────────────────────────────┘                 │
│                                                          │
│  Parallel.map!(items, f) →                               │
│    1. Handler splits items into N chunks                 │
│    2. Each chunk serialized + enqueued                    │
│    3. Worker picks up chunk, deserializes, executes      │
│    4. Worker serializes result, enqueues result          │
│    5. Handler collects all results, concatenates         │
│    6. resume(final_result)                               │
└──────────────────────────────────────────────────────────┘
```

### 11.3 Phase 5 (WASM Threads)

```
┌──────────────────────────────────────────────────────────┐
│  Single WASM Module with SharedArrayBuffer               │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │ Agent 0  │  │ Agent 1  │  │ Agent 2  │  (WASM agents)│
│  │ (thread) │  │ (thread) │  │ (thread) │               │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
│       │             │             │                      │
│  ┌────▼─────────────▼─────────────▼────┐                 │
│  │  Shared Memory                      │                 │
│  │  ┌────────────────────────────┐     │                 │
│  │  │ Atomic work-stealing queue │     │                 │
│  │  ├────────────────────────────┤     │                 │
│  │  │ Per-thread heap regions    │     │                 │
│  │  ├────────────────────────────┤     │                 │
│  │  │ Result slots              │     │                 │
│  │  └────────────────────────────┘     │                 │
│  └─────────────────────────────────────┘                 │
│                                                          │
│  Requires: WASM threads proposal (Phase 4, shipped)     │
│  Requires: SharedArrayBuffer + COOP/COEP (browsers)    │
└──────────────────────────────────────────────────────────┘
```

---

## 12. Implementation Plan

### Phase 2: Sequential Parallel Effect (Current Priority)

| Step | Description | Scope (lines) | Depends On |
|------|-------------|---------------|------------|
| 2a | Add `Parallel` effect definition to stdlib/Prelude | ~40 Camp | Phase 0 (effects working) |
| 2b | Implement sequential handler | ~80 Camp | 2a |
| 2c | Typechecker: verify effect row propagation through `Parallel` ops | ~30 Odin | 2a |
| 2d | Collection method sugar: `par_map!`, `par_filter!`, `par_reduce!`, `par_for_each!` on `List(a)` | ~60 Odin (canonicalize) | 2a |
| 2e | `par { }` and `par for` block syntax: parser + desugar | ~80 Odin (parser + canonicalize) | 2a |
| 2f | E2E tests: parallel operations with sequential handler | ~200 Camp test files | 2b-d |
| 2g | Formatter support for `par` blocks and `par_*!` method calls | ~30 Odin | 2e |

**Total estimated scope**: ~520 lines

**Exit criterion**: `Parallel.map!(items, f)` and `items.par_map!(f)` work correctly with sequential handler. Effect row includes `Parallel`. `par { e1, e2 }` desugars to `Parallel.all!`. `par for x in xs { body }` desugars to `Parallel.for_each!`.

### Phase 4: Thread-Pool Parallel Handler

| Step | Description | Scope (lines) | Depends On |
|------|-------------|---------------|------------|
| 4a | `Parallel` → `Spawn` handler: chunk-based work distribution | ~150 Camp | Phase 3 (Spawn) |
| 4b | Auto-install thread-pool handler when `Parallel` in `main!`'s row | ~80 Odin (CLI) | 4a |
| 4c | Chunk size heuristics | ~60 Camp | 4a |
| 4d | Work-stealing scheduler (optional) | ~400 Camp | Phase 5 (atomics) |
| 4e | E2E + benchmarks: verify near-linear speedup | ~200 Camp | 4a |

**Total estimated scope**: ~890 lines (without work-stealing: ~490 lines)

### Phase 6: SIMD Optimization (Future)

| Step | Description | Scope | Depends On |
|------|-------------|-------|------------|
| 6a | `Simd` intrinsics module: `I32x4`, `F32x4`, etc. | ~200 Camp | WASM SIMD support in codegen |
| 6b | Auto-vectorization for `Parallel.map!` on numeric data | ~300 Odin | 6a |
| 6c | `Iter.par_collect!` SIMD fast path | ~100 Odin | 6a |

---

## 13. Open Questions

### 13.1 `reduce!` Associativity Enforcement

**Status**: No static enforcement (documented convention only)

**Alternatives considered**:
- `Associative` trait: Undecidable in general. Would require programmer annotation with no compile-time verification. Adds complexity for marginal benefit.
- Separate `par_reduce!` (associative) and `par_fold!` (sequential): Adds API surface. The name `reduce!` already implies associativity in most parallel programming contexts.

**Decision**: Document that `reduce!` requires an associative `f` for parallel correctness. The sequential handler folds left. The parallel handler may reorder.

### 13.2 `par` Block Tuple vs List Return

**Status**: `par { e1, e2, e3 }` returns a tuple `(T1, T2, T3)`, not `List(a)`

**Rationale**: A tuple preserves the individual types of each expression. `Parallel.all!` returns `List(a)` because it accepts a dynamically-sized list of same-typed tasks. The `par` block is a fixed-size syntactic form — tuple is more precise.

**Implementation**: The `par` block's type is a tuple of the types of each expression. This requires the canonicalizer to construct a tuple type from the expression types.

### 13.3 Error Handling in `map!`

**Status**: If `f` throws in `Parallel.map!`, the entire operation fails (short-circuit)

**Alternatives considered**:
- Collect all errors and throw a `List(E)`: More informative but breaks the `Throw(e)` model (can't throw a list of different-typed errors)
- Return `[Ok(a) | Err(e)]` instead of throwing: Changes the return type, which is inconsistent with `map!`'s contract

**Decision**: Short-circuit on first error. The handler catches the first `Throw` from any worker and propagates it. Remaining workers may be cancelled (handler choice). This matches `Parallel.any!`'s dual — `any!` succeeds on first success, `map!` fails on first failure.

### 13.4 Interaction with `Iter(a)`

**Status**: Deferred

`Iter(a)` is Camp's lazy iterator pipeline. `par_map!` operates on `List(a)` (eager). A future `Iter.par_collect!` could consume an iterator pipeline in parallel, but this requires:
- Knowing the iterator length (for chunking)
- Or consuming elements eagerly into chunks

This is deferred until the `Iter` type is implemented.

### 13.5 `Parallel` Effect and `for_each!` Side Effect Ordering

**Status**: `for_each!` does NOT guarantee side effect order

**Rationale**: If the handler runs `for_each!` in parallel, the order of side effects (e.g., `Console.println!`) is non-deterministic. This is documented in the operation semantics. Users who need ordered side effects should use `items.iter().for_each(f)` instead.

---

## 14. References

### WASM/WASI Parallelism Landscape

| Resource | URL | Relevance |
|----------|-----|-----------|
| WASM Threads Proposal | https://github.com/WebAssembly/threads | SharedArrayBuffer + atomics; Phase 4; shipped in all browsers + wasmtime Tier 2 |
| WASI I/O Polling | https://github.com/WebAssembly/WASI/tree/main/wasip2 | `wasi:io/poll` for readiness-based I/O; Phase 3 |
| Component Model Concurrency | https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md | Async ABI design for Preview 3; not yet implemented |
| Stack Switching Proposal | https://github.com/WebAssembly/stack-switching | Foundation for component model async; Phase 3 |
| shared-everything-threads | https://github.com/WebAssembly/shared-everything-threads | Future: sharing tables + globals + thread.spawn; Phase 1 |

### Parallel Programming in Functional Languages

| Resource | Language | Pattern |
|----------|----------|---------|
| Rayon | Rust | Work-stealing parallel iterator; requires WASM threads + COOP/COEP |
 | Parallel.Generator | F# | Parallel-for with .NET thread pool |
| Control.Parallel.Strategies | Haskell | Eval monad + rpar/rseq for parallel evaluation |
| pmap | Erlang/Elixir | Parallel map over list; one process per element |

### Academic References

| Paper | Year | Key Contribution |
|-------|------|-----------------|
| "Effect Handlers, Evidently" — Xie et al. | 2020 | Evidence passing for O(1) effect dispatch — Camp's compilation strategy |
| "Koka: Programming with Row-Polymorphic Effect Types" — Leijen | 2014 | Effect rows and handler composition |
| "Perceus: Garbage Free Reference Counting with Reuse" — Reinking et al. | 2021 | Perceus RC — Camp's memory model (no shared mutable state = safe parallelism) |

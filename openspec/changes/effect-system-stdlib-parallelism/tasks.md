## 1. Parser Syntax Alignment

- [x] 1.1 Add `-[Eff1 | Eff2]->` effect row syntax to parser (replace `->{ Eff1, Eff2 }`)
- [x] 1.2 Update handler arm parameter syntax: `.op!(resume, arg1, arg2) => body` — first param is always `resume`
- [x] 1.3 Update `format_type` to emit `-[...]->` syntax
- [x] 1.4 Update AST: `Handler_Arm.params: [dynamic]Intern_ID` replaces `resume_id: Intern_ID`
- [x] 1.5 Update e2e tests for new effect row and handler arm syntax

## 2. Cherry-pick Bugfixes from stdlib-impl

- [x] 2.1 Cherry-pick recursive definition fix (`self_var`/`rec_vars` with occurs check exclusion)
- [x] 2.2 Cherry-pick tag row kind fix (`fresh_tag_row` instead of `fresh_value_var`)

## 3. Fix Existing Bugs (Phase 0b)

- [x] 3.1 Add `IR_Crash` node — `CExpr_Crash` discards crash semantics (H2)
- [x] 3.2 Fix missing handler evidence argument — `ev_var == NO_NAME` omits evidence (M4)
- [x] 3.3 Fix generalization at child levels — child levels not checked before generalizing (M9)
- [x] 3.4 Fix closure body nil — `IR_Decl_Fn.body` is nil after closure conversion (C8)
- [x] 3.5 Add `call_indirect` for higher-order calls — no indirect dispatch for non-name callees (C7)
- [x] 3.6 Fix CPS transform to create continuation functions — never creates `kc` functions (M5)

## 4. Effect Row Subtraction (Phase 1)

- [x] 4.1 Implement `subtract_effect_from_row(store, row, effect) -> Type_Var_ID` helper
- [x] 4.2 Update `handle` expression typechecking to compute result row via subtraction
- [x] 4.3 Add e2e tests for effect row subtraction

## 5. Evidence Passing (Phase 2)

- [x] 5.1 Add `effects: [dynamic]Canonical_Name` field to `IR_Decl_Fn` (replace `effect_row: IR_Type`)
- [x] 5.2 Rewrite `effect_lower`: prepend evidence `i32` params to effectful functions
- [x] 5.3 Rewrite `effect_lower`: append evidence arguments at call sites to effectful functions
- [x] 5.4 Rewrite `effect_lower`: `IR_Perform` dispatches through evidence record (load fn_idx + env_ptr, call_indirect)
- [x] 5.5 Rewrite `effect_lower`: `IR_Handle` allocates evidence record, initializes arm closures
- [x] 5.6 Add e2e tests for evidence passing (handlers actually intercept performs)

## 6. CPS Continuation Capture (Phase 3)

- [x] 6.1 Add `IR_Resume` IR node with `resume_id`, `value`, `type`, `span`
- [x] 6.2 Implement CPS transform at `IR_Perform` sites in `IR_Let` — create continuation function, closure record, call handler arm
- [x] 6.3 Implement deep handler semantics — pass `ev` to continuation so handler is reinstalled
- [x] 6.4 Implement shallow handler semantics — don't pass `ev` to continuation
- [x] 6.5 Implement one-shot enforcement — zero `fn_idx` on first resume, trap on null (double-resume)
- [x] 6.6 Add e2e tests for resume mechanism and one-shot enforcement

## 7. WASM Codegen for Effects (Phase 4)

- [ ] 7.1 Generate handler arm functions as WASM table entries with correct signature
- [ ] 7.2 Codegen evidence record allocation (`camp_alloc`) and initialization (store fn_idx + env_ptr)
- [ ] 7.3 Codegen `IR_Perform` → `call_indirect` via evidence (load arm, call with op_args + resume + ev)
- [ ] 7.4 Codegen `IR_Resume` → `call_indirect` on continuation closure with one-shot check
- [ ] 7.5 Codegen effectful `main!`: generate `_start` with default handlers for Console!, Throw!, etc.
- [ ] 7.6 Add e2e tests — effects execute end-to-end in WASM

## 8. Effect `:` Syntax Migration (Phase 5)

- [ ] 8.1 Remove `Kw_Effect` from lexer — no `effect` keyword
- [ ] 8.2 Add `Kw_Par` to lexer
- [ ] 8.3 Extend parser: `Name! : { ... }` routes to `CDecl_Effect`, `Name : { ... }` routes to `CDecl_Trait`
- [ ] 8.4 Enforce effect operation type annotations are required (error if missing)
- [ ] 8.5 Error if non-effect type name ends with `!`
- [ ] 8.6 Update canonicalize for `:`-style effect definitions (no more `effect` block parsing)
- [ ] 8.7 Update `format_decl` to emit `:` syntax for effects
- [ ] 8.8 Update all e2e tests from `effect IO { ... }` to `IO! : { ... }`
- [ ] 8.9 Update formatter for new syntax

## 9. Parameterized Effects + Variant Widening (Phase 6)

- [ ] 9.1 Add type parameters to effect definitions: `Throw! : { throw!: |e| -[Throw!(e)]-> a }`
- [ ] 9.2 Track effect type arguments in effect rows: `-[Throw!([NotFound])]->`
- [ ] 9.3 Implement tag row unification for effect type parameters — general widening (not Throw-specific)
- [ ] 9.4 Remove any Throw-specific widening code in typechecker/unifier
- [ ] 9.5 Add e2e tests: parameterized effects, variant widening, custom effects with widening

## 10. Effect Polymorphism (Phase 7)

- [ ] 10.1 Add `is_effect: bool` field to `Type_Param`
- [ ] 10.2 Set `is_effect = true` for lowercase type params used in effect row position
- [ ] 10.3 Implement effect row variable unification (bind row var to concrete row, link two row vars)
- [ ] 10.4 Implement effect row composition: `-[Parallel! | e]->` unifies with `-[e]->` by adding `Parallel!`
- [ ] 10.5 Implement effect row subtraction with variables: `handle Parallel! in body` where body has `-[Parallel! | e]->` produces `-[e]->`
- [ ] 10.6 Update handler arm type verification against declared operation signatures
- [ ] 10.7 Add e2e tests for effect-polymorphic functions and row composition/subtraction

## 11. Prelude Effects (Phase 8)

- [ ] 11.1 Add `Console!` as prelude effect: `{ println!: |Str| -[Console!]-> {}, readln!: -[Console!]-> Str }`
- [ ] 11.2 Add `Throw!` as normal resumable prelude effect: `{ throw!: |e| -[Throw!(e)]-> a }`
- [ ] 11.3 Add default Throw! handler in `_start` codegen — print tag to stderr, `proc_exit(1)`, does not call resume
- [ ] 11.4 Remove non-resuming handler special case from `effect_lower` and `codegen` — all handlers use same arm signature
- [ ] 11.5 Add e2e tests: Throw! resumable handler, Throw! non-resuming handler, default Throw! in main

## 12. Stdlib Infrastructure — Prelude Expansion

- [ ] 12.1 Expand Odin-injected type declarations: I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Bool, Str, Bytes, Unit
- [ ] 12.2 Expand Odin-injected collection type declarations: List, Iter, Map, Set, Handle, Ordering
- [ ] 12.3 Expand Odin-injected tag declarations: True, False, Ok, Err, Some, None, Less, Equal, Greater, Nil, Cons
- [ ] 12.4 Add Odin-injected effect name declarations: Console!, Throw!, Async!, Parallel!, Spawn!, File!, Env!, Time!, Random!, Log!, Crypto.Random!
- [ ] 12.5 Add Odin-injected operator function declarations (numeric, comparison, boolean operators)

## 13. Stdlib Infrastructure — Runtime WASM Primitives

- [ ] 13.1 Add list runtime functions: `camp_list_alloc`, `camp_list_push`, `camp_list_len`, `camp_list_get`
- [ ] 13.2 Add string runtime functions: `camp_str_concat`, `camp_str_len`, `camp_str_eq`, `camp_str_slice`
- [ ] 13.3 Add file I/O runtime functions: `camp_print_str` (WASI fd_write), `camp_read_str` (WASI fd_read)
- [ ] 13.4 Add env runtime functions: `camp_args`, `camp_get_env`
- [ ] 13.5 Add time runtime functions: `camp_time_now`, `camp_time_sleep`
- [ ] 13.6 Add random runtime functions: `camp_random_bytes` (WASI random_get), `camp_random_int`

## 14. Stdlib Infrastructure — .camp File Embedding

- [ ] 14.1 Create `stdlib/` directory structure with initial .camp files
- [ ] 14.2 Write `Result.camp` and `Option.camp` — tag union helpers (Ok/Err, Some/None)
- [ ] 14.3 Write `Bool.camp`, `Int.camp`, `Str.camp` — primitive type operations
- [ ] 14.4 Implement .camp file embedding at Odin build time (embed_file or #embed)
- [ ] 14.5 Update module system: resolve `import <name>` by checking user `src/` first, then embedded stdlib
- [ ] 14.6 Write `List.camp` — map, filter, fold, append, iter, etc.
- [ ] 14.7 Write `Iter.camp` — lazy iterator pipeline (map, filter, fold, collect, chain, enumerate, take, skip, zip)
- [ ] 14.8 Write `Map.camp`, `Set.camp` — collection operations
- [ ] 14.9 Write `Eq.camp`, `Ord.camp`, `Hash.camp` — trait definitions and instances
- [ ] 14.10 Write `Fmt.camp` — Display trait, format function
- [ ] 14.11 Write `Path.camp` — file path manipulation
- [ ] 14.12 Write effect .camp files: `Console!.camp`, `Throw!.camp`, `File!.camp`, `Env!.camp`, `Time!.camp`, `Random!.camp`
- [ ] 14.13 Write `Serialize.camp` — simple Codec trait with encode/decode methods
- [ ] 14.14 Write `Bytes.camp` — raw byte operations

## 15. Parallel Effect — Sequential Handler + Syntax

- [ ] 15.1 Add `Parallel!` effect definition to prelude: `{ map!, for_each!, filter!, reduce!, all!, any! }`
- [ ] 15.2 Implement sequential `Parallel!` handler (iterates sequentially, uses Iter operations)
- [ ] 15.3 Implement collection method sugar in canonicalize: `list.par_map!(f)` → `Parallel!.map!(list, f)`
- [ ] 15.4 Implement `par { e1, e2, e3 }` block desugaring → `Parallel!.all!([|| e1, || e2, || e3])`
- [ ] 15.5 Implement `par for x in xs { body }` desugaring → `Parallel!.for_each!(xs, |x| body)`
- [ ] 15.6 Add effect row propagation for Parallel! operations (effect-polymorphic inner function)
- [ ] 15.7 Add formatter support for `par` blocks and method sugar
- [ ] 15.8 Add e2e tests for sequential parallelism, method sugar, par blocks

## 16. Spawn Effect — Sequential Handler

- [ ] 16.1 Add `Spawn!` effect definition to prelude: `{ spawn!, join!, cancel! }`
- [ ] 16.2 Add `Handle(a)` opaque type to prelude
- [ ] 16.3 Implement sequential `Spawn!` handler — spawn runs thunk immediately, join returns result
- [ ] 16.4 Add e2e tests for sequential Spawn!

## 17. Async Runtime

- [ ] 17.1 Implement Async scheduler data structures (ready queue, blocked map, active handles, join waiters)
- [ ] 17.2 Implement scheduler loop: dequeue, resume, block on I/O, complete, poll when idle
- [ ] 17.3 Add `camp_async_*` runtime functions (init, enqueue, dequeue, block, complete, join_wait, cancel, run)
- [ ] 17.4 Implement WASI poll bridge — subscribe to pollable, move ready coroutines to queue
- [ ] 17.5 Implement short read/write handling — buffer partial results, retry transparently
- [ ] 17.6 Implement `Time.sleep!` via poll timeout
- [ ] 17.7 Implement `Async.yield!` (reschedule) and `Async.spawn!` (enqueue coroutine)
- [ ] 17.8 Implement structured concurrency enforcement — track outstanding handles, warn on unjoined spawns
- [ ] 17.9 Codegen: initialize scheduler in `_start` when `Async!` in main's effect row
- [ ] 17.10 Add e2e tests for concurrent I/O with WASI poll

## 18. Multi-Instance Spawn

- [ ] 18.1 Add `--threads=N` CLI flag and `CAMP_THREADS` env var to CLI
- [ ] 18.2 Implement thread pool manager in Odin host (MPMC work queue, result map, worker lifecycle)
- [ ] 18.3 Implement worker loop (dequeue task, deserialize closure, execute, serialize result)
- [ ] 18.4 Implement two-module compilation strategy (main module + worker module, or single dual-purpose module)
- [ ] 18.5 Implement closure serialization format (magic, version, fn_index, env_size, env_bytes, effect_row bitmask)
- [ ] 18.6 Implement closure deserialization in worker module
- [ ] 18.7 Implement `Spawn!` handler via multi-instance — serialize thunk, submit to pool, wait, deserialize result
- [ ] 18.8 Implement `Parallel!` handler via multi-instance — chunk distribution, spawn+join, concatenate
- [ ] 18.9 Handle string/list cross-instance data (deep copy for correctness)
- [ ] 18.10 Implement error propagation across instances — serialize thrown tags, re-throw in caller
- [ ] 18.11 Implement structured concurrency tracking across instances
- [ ] 18.12 Add e2e tests and benchmarks for multi-instance parallelism

## 19. WASM Threads

- [ ] 19.1 Add shared memory codegen — `shared=true` flag, `maximum` field when `--threads=N > 1`
- [ ] 19.2 Add `IR_Atomic_Load`, `IR_Atomic_Store`, `IR_Atomic_RMW`, `IR_Atomic_Fence` IR node types
- [ ] 19.3 Add `IR_Wait` and `IR_Notify` IR node types for `memory.atomic.wait32/64` and `notify`
- [ ] 19.4 Update mid-end passes to handle atomic IR variants (effect_lower, closure_convert, cps, rc)
- [ ] 19.5 Implement atomic instruction WASM emission (0xFE opcodes)
- [ ] 19.6 Implement work queue data structure in shared memory (atomic head/tail, entries array)
- [ ] 19.7 Implement enqueue/dequeue operations using atomic RMW and notify
- [ ] 19.8 Implement worker entry function codegen (`camp_worker_entry` export)
- [ ] 19.9 Implement per-thread heap regions in shared memory (bump allocator, no cross-thread refcounting)
- [ ] 19.10 Implement `camp_alloc_region` bump allocator for thread-local allocation
- [ ] 19.11 Migrate `Spawn!` handler to in-process (pass closure by pointer in shared memory)
- [ ] 19.12 Migrate `Parallel!` handler to in-process
- [ ] 19.13 Add COOP/COEP warning for browser targets
- [ ] 19.14 Implement runtime detection and fallback chain: WASM threads → multi-instance → sequential
- [ ] 19.15 Add e2e tests and benchmarks for WASM threads parallelism

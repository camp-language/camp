## Context

The Camp compiler has basic algebraic effects working on main: evidence passing, CPS continuation capture, deep/shallow handlers, one-shot continuations, effect row subtraction, and `!` naming enforcement. The module system works end-to-end (discovery, graph, topological sort, cross-module typecheck). The annotate + mono pipeline exists and works (CFile → TFile → specialized TFile → lower).

However, the effect system has three gaps:
1. **Syntax**: Effects use a deprecated `effect` keyword instead of the `:` type alias syntax that unifies them with traits
2. **Type system**: No effect polymorphism (row variables as generic parameters), no parameterized effects, variant widening is Throw-specific
3. **Stdlib**: Minimal prelude (8 types, 2 tags), no runtime primitives, no .camp module files

The `smores/stdlib-impl` branch has two salvageable bugfixes (recursive definitions, tag row kind fix) but uses incompatible syntax. The `smores/parallel-effect` branch has `par` syntax and method sugar but is based on the old effect architecture.

## Goals / Non-Goals

**Goals:**
- Unify effect and trait syntax under the `:` type alias form
- Enable effect polymorphism for composable parallel/async APIs
- Bootstrap stdlib infrastructure (prelude, runtime primitives, .camp files)
- Implement full parallelism spec phases 1–5 (sequential through WASM threads)
- Generalize variant widening away from Throw-specific code

**Non-Goals:**
- Encode/Decode codec framework with formatting traits (deferred — simple Codec trait first)
- Official packages (Http, Database, etc.) — these are Camp-language packages built on top of stdlib
- SIMD optimization (parallelism phase 6)
- Dynamic dispatch / trait objects
- `@derive` expansion (requires comptime evaluation)

## Decisions

### D1: Effects as type aliases with `!` names

**Choice**: `Console! : { println!: |Str| -[Console!]-> {} }` — no `effect` keyword.

**Rationale**: Unifies effects with traits (both are structural record type aliases). The `!` suffix on the name distinguishes effects from traits at definition time. The parser routes `Name! : { ... }` to `CDecl_Effect` and `Name : { ... }` to `CDecl_Trait`. No new keywords needed.

**Alternatives considered**:
- Keep `effect` keyword: Adds a keyword for something that's structurally a type alias. Inconsistent with trait-as-record design.
- Use `!` as a modifier (not part of name): Requires two-token lookback. Breaks qualified calls like `Console!.println!`.

### D2: Throw! is a fully normal resumable effect

**Choice**: `Throw! : { throw!: |e| -[Throw!(e)]-> a }` in the prelude. Handlers may call `resume`.

**Rationale**: There is no principled reason Throw! cannot resume. Non-resuming is a handler implementation choice (the default runtime handler doesn't call resume), not a language constraint. Removing the non-resuming special case simplifies codegen: all handlers use the same arm signature, no `is_non_resuming` flag, no separate `handler_throw` signature.

**Alternatives considered**:
- Non-resuming Throw!: Requires a type-level distinction between resuming and non-resuming handlers, complicating the effect system with no practical benefit.
- Multi-shot Throw!: Breaks one-shot guarantee; complicates evidence passing.

### D3: Variant widening is general tag row unification

**Choice**: When two effect rows both contain `Throw!`, unify their type arguments via existing tag row unification. No Throw-specific widening code.

**Rationale**: `Throw!([NotFound])` and `Throw!([PermissionDenied])` unify to `Throw!([NotFound | PermissionDenied])` through the same mechanism as `[Ok(a) | Err(e)]` unification. Any effect with a tag union parameter (e.g., `Signal! : { emit!: |e| -[Signal!(e)]-> {} }`) gets widening for free.

### D4: Canonical desugaring for method sugar

**Choice**: `list.par_map!(f)` rewrites to `Parallel!.map!(list, f)` during canonicalization.

**Rationale**: UFCS trait dispatch cannot handle this because `par_map!` is an operation of the `Parallel!` effect, not a method on `List`. Effect dispatch produces `IR_Perform` (evidence passing), while trait dispatch produces direct `IR_Call`. Desugaring preserves the effect dispatch path naturally. The transformation is table-driven and extensible.

**Alternatives considered**:
- UFCS dispatch: Would require `List is Parallel`, conflating effects with traits. Even if faked, UFCS resolves to direct calls, not performs.
- Hardcode in parser: Less extensible; canonicalize is the right phase for desugaring.

### D5: Hybrid prelude (Odin types + .camp modules)

**Choice**: Odin-injected type constructors, tags, effect names, and operator functions. Actual module logic (List.map, Iter.filter, etc.) lives in .camp files embedded in the compiler binary.

**Rationale**: Odin injection is needed for types that require special typeck support (constructor arity, primitive representation). But Odin injection can't express real Camp logic (closures, pattern matching, generics). The .camp files provide the real implementations while the Odin prelude bootstraps the type environment.

### D6: Stdlib .camp files embedded in compiler binary

**Choice**: Embed .camp files at Odin build time using `#embed` or `embed_file`. Extract to temp dir (or read from memory) at runtime. Module system checks embedded stdlib after `src/`.

**Rationale**: No external file dependency. Users get stdlib automatically without installation. Same approach as Rust's `core`/`std` embedded in `rustc`.

### D7: Effect polymorphism via row variable unification

**Choice**: Effect row variables are generic type parameters with `is_effect: bool`. Row variable unification extends the existing record/tag row unification infrastructure. Composition: `-[Parallel! | e]->` unifies with `-[e]->` by adding `Parallel!`. Subtraction with variables: `handle Parallel! in body` where body has `-[Parallel! | e]->` produces `-[e]->`.

**Rationale**: This is Koka's approach — effect row polymorphism is the core feature that makes algebraic effects composable. The existing row unification for records and tag unions provides the implementation foundation.

### D8: Simple Codec trait first

**Choice**: Use a basic `Codec` trait with format-specific methods. Defer the `EncoderFormatting`/`DecoderFormatting` parameterized trait architecture.

**Rationale**: The formatting-trait architecture requires constrained trait parameters (possibly higher-kinded types), which the current trait system doesn't support. A simple `Codec` trait gets the stdlib working without blocking on type system extensions.

## Risks / Trade-offs

**[Effect polymorphism complexity]** → The biggest risk. Row variable unification for effects extends the type system in a non-trivial way. Mitigation: adapt the existing `fresh_effect_row`/`unify_effect_rows` infrastructure, which already handles concrete effect rows. Start with monomorphic effect rows, add variables incrementally with thorough testing.

**[Syntax migration is a flag day]** → Every e2e test using `effect IO { ... }` breaks. No easy way to support both syntaxes. Mitigation: do it in one commit, update all tests. The total scope is ~15 test files.

**[Stdlib .camp files can't bootstrap until compiler supports enough]** → List.camp needs generics, traits, effects, imports — all of Layers 1–4. Mitigation: write .camp files incrementally, starting with simplest modules (Result, Option) that need the fewest language features. First few modules are the integration test for the whole pipeline.

**[Layers 7–8 are Odin host code, not compiler passes]** → Multi-instance and WASM threads runtimes are a different skillset (wasmtime API, thread pool management). Mitigation: ship through Layer 6 first (sequential parallelism + async runtime), then tackle 7–8 as a focused effort.

**[Recursive definition + tag row kind fixes from stdlib-impl] → Cherry-pick the bugfixes, not the entire branch. The stdlib-impl branch has incompatible syntax and deleted the module system. Only the self_var/rec_vars and fresh_tag_row fixes are needed.

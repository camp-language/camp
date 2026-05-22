## Why

The compiler has basic algebraic effects working (evidence passing, CPS continuation capture, deep/shallow handlers), but the effect system is incomplete in three critical ways: (1) effects use a deprecated `effect` keyword syntax instead of the `:` type alias syntax that unifies them with traits, (2) there is no effect polymorphism (row variables as generic parameters), and (3) there is no stdlib infrastructure (prelude types, runtime primitives, .camp module files). Without these, the parallelism spec (Parallel!/Spawn!/Async! effects, par blocks, multi-instance runtime) and the packages spec (stdlib modules, codec framework) cannot be implemented.

## What Changes

- **BREAKING**: Remove `effect` keyword; effects become type aliases with `!` names (`Console! : { println!: |Str| -[Console!]-> {} }`)
- **BREAKING**: Effect operation type annotations become required
- **BREAKING**: Throw! becomes a fully normal resumable effect in the prelude (no non-resuming handler restriction)
- **BREAKING**: All effect names gain `!` suffix in code and specs (Parallel→Parallel!, Throw→Throw!, Console→Console!, etc.)
- Add parameterized effects: effects can have type parameters (`Throw!([NotFound | PermissionDenied])`)
- Add general variant widening: tag union type parameters on effects widen through normal tag row unification (not Throw-specific)
- Add effect polymorphism: effect row variables as generic parameters, row variable unification, row composition and subtraction with variables
- Add handler arm type verification against declared operation signatures
- Expand Odin-injected prelude with full type/tag/effect/operator declarations
- Add runtime WASM primitives for list ops, string ops, file I/O, env, time, random
- Create stdlib .camp files embedded in the compiler binary (List, Iter, Result, Option, Int, Str, Bool, Fmt, Eq, Ord, Hash, Path, Serialize)
- Create effect .camp files (Console!, Throw!, File!, Env!, Time!, Random!)
- Integrate stdlib module resolution into existing module system
- Add `par` keyword and block syntax (`par { e1, e2 }` → `Parallel!.all!([|| e1, || e2])`)
- Add `par for` loop syntax (`par for x in xs { body }` → `Parallel!.for_each!(xs, |x| body)`)
- Add collection method sugar via canonical desugaring (`list.par_map!(f)` → `Parallel!.map!(list, f)`)
- Add sequential handlers for Parallel!, Spawn!, Async! effects
- Add Async! WASI runtime (coroutine scheduler, poll bridge, structured concurrency)
- Add multi-instance Spawn! runtime (thread pool, closure serialization, chunk-based Parallel! handler)
- Add WASM threads runtime (shared memory, atomic IR nodes, in-process parallelism, runtime detection + fallback)

## Capabilities

### New Capabilities

- `effect-polymorphism`: Effect row variables as generic parameters, row variable unification, effect row composition and subtraction with variables
- `parameterized-effects`: Effects with type parameters; tag union parameters widen via general tag row unification
- `stdlib-infrastructure`: Hybrid prelude (Odin-injected types + .camp module files), runtime WASM primitives, stdlib .camp file embedding and resolution
- `par-syntax`: `par` keyword, `par { }` and `par for` block syntax, collection method sugar via canonical desugaring
- `async-runtime`: Coroutine scheduler, WASI poll bridge, structured concurrency, Time.sleep! via poll timeout
- `multi-instance-runtime`: Thread pool manager, closure serialization, Spawn!/Parallel! handlers via multi-instance
- `wasm-threads-runtime`: Shared memory codegen, atomic IR nodes, in-process parallelism, runtime detection and fallback chain

### Modified Capabilities

- `effects`: Remove `effect` keyword; effects as type aliases with `!` names; required operation type annotations; Throw! as normal resumable effect; handler arm type verification; updated implementation plan phases
- `parallelism`: Updated to use `!` effect names and `-[...]->` row syntax; effect definitions use `:` type alias syntax
- `packages`: Updated to use `!` effect names and `-[...]->` row syntax; simple Codec trait first (defer formatting-trait parameterization)

## Impact

- **Parser**: Remove `Kw_Effect`, add `Kw_Par`, extend `:` definition parsing for `!` names, parse `par` blocks
- **Typechecker**: Effect declarations as type aliases, parameterized effects, effect polymorphism (row variable unification), handler arm type verification, general variant widening
- **Canonicalize**: `par` block desugaring, collection method sugar table
- **Effect lowering**: Remove non-resuming handler special case, all handlers use same arm signature
- **Codegen**: Sequential handlers for Parallel!/Spawn!/Async!, Async! coroutine scheduler, multi-instance runtime, WASM threads runtime
- **Prelude**: Major expansion (types, tags, effects, operators)
- **Stdlib .camp files**: New directory `stdlib/` with Camp source files, embedded in binary
- **Module system**: Stdlib resolution path (check embedded dir after src/)
- **Runtime primitives**: New WASM functions for list, string, file, env, time, random operations
- **E2E tests**: All effect-related tests updated to new syntax

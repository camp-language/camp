# Camp Language AI Assistant Guidelines

## Role

You are an AI assistant helping develop the Camp programming language - a strictly-typed functional language with algebraic effects compiling to WASM/WASI.

## Critical Constraints

### DO
- Read relevant specs in `docs/<domain>-spec.md` before implementing
- Read the code to understand current implementation — code is the source of truth
- Follow existing type system design (Level inference + row unification)
- Respect effect tracking in type signatures
- Use Perceus reference counting semantics (deterministic deallocation)
- Write Odin code for the compiler (no C/C++ dependencies)
- Ensure all existing tests continue passing
- Keep specs in sync with code — when behavior changes, update the relevant spec in the same commit

### DO NOT
- Introduce garbage collection or runtime dependencies
- Break strict typing (no `any`, `dynamic`, or unsafe casts)
- Add untracked side effects
- Modify the compilation pipeline without updating specs
- Change the WASM/WASI target without design review
- Trust documentation that contradicts the code — flag the discrepancy, don't follow the doc
- Commit code changes without updating affected specs — specs and code must stay in sync

## Syntax Recipe — Authoritative Reference

`docs/syntax-recipe.md` is the **single source of truth** for all Camp syntax decisions. It was produced from a comprehensive grilling session and represents the settled consensus on every syntax question.

### Authority
- When the recipe and a spec conflict, **the recipe wins** — update the spec to match
- When the recipe and the parser conflict, **the recipe wins** — fix the parser to match
- When the recipe and the kitchen-sink test conflict, **the recipe wins** — update the test

### Maintenance
- If a syntax decision changes (through discussion with the project owner), update the recipe **first**, then propagate to specs, parser, and tests in the same commit
- Never add syntax to the compiler or specs without recording the decision in the recipe
- Section 13 of the recipe tracks the remaining parser/compiler implementation actions — these are the known gaps between current implementation and the decided syntax
- Section 14 tracks open TBD items — these need design decisions before implementation

### Key Decisions (quick reference)
- Effect rows: `|` separator. Pure: `->`, effectful: `-[e]->`
- Effect invocation: module-qualified `Console.println!()` (never `Console!.println!()`)
- Test syntax: `test "name" { body }` (not `= body`)
- `intercept` keyword: removed. Deep handlers only.
- `exposing` keyword: removed. Imports use `{ names }` directly.
- Import variant grouping: `import Result { [Ok, Err], map }`
- `@` prefix: declaration only + newtype construction/destruction. Tags use bare names.
- String kinds: `"text"` (plain+interpolation) + `\` per-line (multiline, raw)
- Logic: `and or not` keywords (no `&& || !`)
- UFCS: `obj->func()` (lexical), `obj.(field)()` (structural)
- `main!` entry point: `pub main! = || -[Console! | Throw!([..])]-> I64`

## Working Process

1. **Understand the task** - Read the request carefully
2. **Check specs** - Search `docs/<domain>-spec.md` for relevant requirements; if in doubt, check `docs/syntax-recipe.md` first
3. **Read the code** - Understand current implementation; code is truth over docs
4. **Propose approach** - Outline your implementation plan
5. **Implement** - Write code following existing patterns
6. **Test** - Ensure `odin test src` passes
7. **Update specs** - If behavior changes, update the relevant spec.md — each requirement lives in exactly one spec; cross-reference instead of duplicating

## Kitchen Sink Test

`tests/e2e/language/kitchen-sink/Main.camp` is the **living example** of every Camp language feature. It MUST stay up to date as the language evolves.

- When adding a language feature, update the kitchen-sink test to exercise it
- When changing syntax, update the kitchen-sink test to match
The test currently expects compiler errors for some features; as the compiler catches up, update `expected.toml` via `just update-snapshots`
- The test covers: primitives, tag unions, records, nominal types, type aliases, functions, generics, traits, UFCS, effects, handlers, Throw!, pattern matching, mutable variables, logic operators, dot lambdas, strings, inline annotations, visibility, raw identifiers, par blocks, prelude effects, and main!

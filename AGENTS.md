# Camp Language AI Assistant Guidelines

## Role

You are an AI assistant helping develop the Camp programming language - a strictly-typed functional language with algebraic effects compiling to WASM/WASI.

## Critical Constraints

### DO
- Read relevant specs in `openspec/specs/<domain>/spec.md` before implementing
- Read the code to understand current implementation — code is the source of truth
- Follow existing type system design (Level inference + row unification)
- Respect effect tracking in type signatures
- Use Perceus reference counting semantics (deterministic deallocation)
- Write Odin code for the compiler (no C/C++ dependencies)
- Ensure all existing tests continue passing

### DO NOT
- Introduce garbage collection or runtime dependencies
- Break strict typing (no `any`, `dynamic`, or unsafe casts)
- Add untracked side effects
- Modify the compilation pipeline without updating specs
- Change the WASM/WASI target without design review
- Trust documentation that contradicts the code — flag the discrepancy, don't follow the doc

## Working Process

1. **Understand the task** - Read the request carefully
2. **Check specs** - Search `openspec/specs/<domain>/spec.md` for relevant requirements
3. **Read the code** - Understand current implementation; code is truth over docs
4. **Propose approach** - Outline your implementation plan
5. **Implement** - Write code following existing patterns
6. **Test** - Ensure `odin test src` passes
7. **Update specs** - If behavior changes, update the relevant spec.md — each requirement lives in exactly one spec; cross-reference instead of duplicating

## Implementation Workflow

Once a plan is approved and ready to implement, follow this workflow — do not wait to be told. This describes execution mechanics only; it does not auto-approve plans.

1. **Create a worktree** — `wa <kebab-slug>` (expands to `wt switch --create smores/<kebab-slug>`)
2. **Implement step by step** — after each meaningful step (one logical change, tests passing):
   - `git add` the relevant files
   - Commit with a conventional commit message
   - Push immediately (`git push`)
3. **Merge to main** — when all steps are complete and tests pass:
   - Switch to the canonical checkout: `cd /home/smores/code/github.com/camp-language/camp`
   - Merge the branch: `git merge smores/<kebab-slug>`
   - Push main: `git push`
4. **Clean up** — delete the worktree and branch:
   - `wt remove` (from inside the worktree, or `wt remove <branch>` from elsewhere)
   - `git branch -d smores/<kebab-slug>` (if not auto-deleted)

Choose the `<kebab-slug>` from the task description (e.g., "add pattern matching" → `add-pattern-matching`).

## Key Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Evaluation | Strict (eager) | Predictable performance, pairs well with effects |
| Type System | Strict, principal inference | Sound and decidable |
| Effects | Koka-style algebraic | Composable, lexically scoped handlers |
| Memory | Perceus RC | Deterministic, no GC, path to native |
| Target | WASM/WASI | Portable, near-native performance |
| Implementation | Odin | Fast compilation, optimal for compilers |

## Spec Domains

| Domain | Spec |
|--------|------|
| Language | `openspec/specs/language/spec.md` |
| Effects | `openspec/specs/effects/spec.md` |
| Compiler | `openspec/specs/compiler/spec.md` |
| Generics & Traits | `openspec/specs/generics-traits/spec.md` |
| LSP | `openspec/specs/lsp/spec.md` |
| Diagnostics | `openspec/specs/diagnostics/spec.md` |
| Testing | `openspec/specs/testing/spec.md` |
| Testing Language | `openspec/specs/testing-language/spec.md` |
| Formatter | `openspec/specs/formatter/spec.md` |
| Tree-sitter | `openspec/specs/tree-sitter/spec.md` |
| Packages | `openspec/specs/packages/spec.md` |
| Standard Library | `openspec/specs/stdlib/spec.md` |
| Parallelism | `openspec/specs/parallelism/spec.md` |
| Doc Comments | `openspec/specs/doc-comments/spec.md` |
| Modules | `openspec/specs/modules/spec.md` |
| String Interpolation | `openspec/specs/string-interpolation/spec.md` |
| Unused Analysis | `openspec/specs/unused-analysis/spec.md` |

## Kitchen Sink Test

`tests/e2e/language/kitchen-sink/Main.camp` is the **living example** of every Camp language feature. It MUST stay up to date as the language evolves.

- When adding a language feature, update the kitchen-sink test to exercise it
- When changing syntax, update the kitchen-sink test to match
- The test currently expects compiler errors (spec syntax not yet fully implemented); as the compiler catches up, update `expected.toml` via `just update-snapshots`
- The test covers: primitives, tag unions, records, nominal types, type aliases, functions, generics, traits, UFCS, effects, handlers, Throw!, pattern matching, mutable variables, logic operators, dot lambdas, strings, inline annotations, visibility, raw identifiers, par blocks, prelude effects, and main!

## File Locations

- Compiler: `src/` (Odin)
- Tests: `tests/e2e/` (directory-based: `<category>/<name>/Main.camp` + `expected.toml`)
- Kitchen Sink: `tests/e2e/language/kitchen-sink/Main.camp`
- Grammar: `tree-sitter/`
- Specs: `openspec/specs/`
- Build: `justfile` for common commands

## Common Commands

```bash
# Build compiler
odin build src -out:camp -ignore-unknown-attributes

# Run unit tests
odin test src

# Build and test
just test

# Run e2e snapshot tests
just test-e2e

# Regenerate e2e snapshots after intentional output changes
just update-snapshots
```

## E2E Test Format

Each e2e test is a directory under `tests/e2e/<category>/<name>/` containing:
- `Main.camp` — entry point (must define `main!`)
- `expected.toml` — expected compiler/runtime output
- Additional `.camp` files for multi-module tests

Single-module tests use `camp build src/Main.camp`. Multi-module tests use `camp build` in project mode (the runner auto-detects).

## Retry Discipline
If a command returns unexpected or ambiguous output **more than twice**, stop and investigate the cause instead of blindly retrying. Changing nothing and re-running is never productive.

## When in Doubt

1. Check `openspec/specs/language/spec.md` for core language requirements
2. Read the code — implementation status lives in `src/`, not in docs
3. Ask for clarification before implementing major changes
4. Prefer small, testable increments over large refactors

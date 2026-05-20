# Camp Language AI Assistant Guidelines

## Role

You are an AI assistant helping develop the Camp programming language - a strictly-typed functional language with algebraic effects compiling to WASM/WASI.

## Critical Constraints

### DO
- Read relevant specs in `specs/` before implementing
- Follow existing type system design (Level inference + row unification)
- Respect effect tracking in type signatures
- Use Perceus reference counting semantics (deterministic deallocation)
- Write Odin code for the compiler (no C/C++ dependencies)
- Ensure all 99 existing tests continue passing

### DO NOT
- Introduce garbage collection or runtime dependencies
- Break strict typing (no `any`, `dynamic`, or unsafe casts)
- Add untracked side effects
- Modify the compilation pipeline without updating specs
- Change the WASM/WASI target without design review

## Working Process

1. **Understand the task** - Read the request carefully
2. **Check specs** - Search `specs/` for relevant design decisions
3. **Propose approach** - Outline your implementation plan
4. **Implement** - Write code following existing patterns
5. **Test** - Ensure `odin test src` passes
6. **Document** - Update specs if design changes

## Key Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Evaluation | Strict (eager) | Predictable performance, pairs well with effects |
| Type System | Strict, principal inference | Sound and decidable |
| Effects | Koka-style algebraic | Composable, lexically scoped handlers |
| Memory | Perceus RC | Deterministic, no GC, path to native |
| Target | WASM/WASI | Portable, near-native performance |
| Implementation | Odin | Fast compilation, optimal for compilers |

## File Locations

- Compiler: `src/` (Odin)
- Tests: `tests/` and `src/*/test.odin`
- Grammar: `tree-sitter/`
- Specs: `specs/`
- Build: `justfile` for common commands

## Common Commands

```bash
# Build compiler
odin build src -out:camp

# Run tests
odin test src

# Build and test
just test

# Format code (when implemented)
camp fmt
```

## When in Doubt

1. Check `specs/2026-05-18-camp-language-design.md` for core design
2. Check `specs/2026-05-19-implementation-status.md` for what's done
3. Ask for clarification before implementing major changes
4. Prefer small, testable increments over large refactors

# Camp Language Project

## Overview

Camp is a general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 117 unit tests + 101 e2e snapshot tests passing.

See `src/` for implementation status — code is the source of truth.

## Active Development Areas

1. **Compiler Correctness** — Known bugs in typechecker, closures, CPS, and RC (see `src/`)
2. **Algebraic Effects** — Making effects execute end-to-end in WASM (see `src/effect_lower.odin`, `src/cps.odin`)
3. **LSP Server** — IDE integration with diagnostics, hover, go-to-definition (see `src/lsp.odin`)
4. **Tree-sitter Grammar** — Syntax highlighting and parsing (see `tree-sitter/`)
5. **E2E Testing** — Snapshot testing framework (see `src/e2e/`)
6. **Formatter** — Automatic code formatting (see `src/format_*.odin`)

## Project Structure

```
camp/
├── src/           # Compiler source (Odin)
├── tests/         # Test suite
│   └── e2e/       # E2E snapshot tests
├── tree-sitter/   # Tree-sitter grammar
├── openspec/      # OpenSpec behavioral specifications
│   ├── specs/     # Specs by domain (spec.md only)
│   └── config.yaml
├── justfile       # Build commands
└── project.md     # This file
```

## Building & Testing

```bash
odin build src -out:camp
odin test src
just test
```

## Key Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Evaluation | Strict (eager) | Predictable performance, pairs well with effects |
| Type System | Strict, principal inference | Sound and decidable |
| Effects | Koka-style algebraic | Composable, lexically scoped handlers |
| Memory | Perceus RC | Deterministic, no GC, path to native |
| Target | WASM/WASI | Portable, near-native performance |
| Implementation | Odin | Fast compilation, optimal for compilers |

See [openspec/specs/](openspec/specs/) for behavioral specs per domain.

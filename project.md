# Camp Language Project

## Overview

Camp is a general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 117 unit tests + 101 e2e snapshot tests passing.

See [Implementation Status](openspec/specs/compiler/design.md#current-implementation-status) for detailed progress.

## Active Development Areas

1. **Compiler Correctness** — 8 known bugs in typechecker, closures, CPS, and RC (see [compiler design](openspec/specs/compiler/design.md))
2. **Algebraic Effects** — Making effects execute end-to-end in WASM (see [effects design](openspec/specs/effects/design.md))
3. **LSP Server** — IDE integration with diagnostics, hover, go-to-definition (see [LSP design](openspec/specs/lsp/design.md))
4. **Tree-sitter Grammar** — Syntax highlighting and parsing (see [tree-sitter design](openspec/specs/tree-sitter/design.md))
5. **E2E Testing** — Snapshot testing framework (see [testing design](openspec/specs/testing/design.md))
6. **Formatter** — Automatic code formatting (see [formatter design](openspec/specs/formatter/design.md))

## Project Structure

```
camp/
├── src/           # Compiler source (Odin)
├── tests/         # Test suite
│   └── e2e/       # E2E snapshot tests
├── tree-sitter/   # Tree-sitter grammar
├── openspec/      # OpenSpec specifications
│   ├── specs/     # Behavioral specs + technical designs by domain
│   ├── changes/   # Active change proposals
│   ├── config.yaml
│   └── AGENTS.md  # AI assistant guidelines
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

See [openspec/specs/](openspec/specs/) for detailed specs and designs per domain.

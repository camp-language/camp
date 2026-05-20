# Camp Language Project

## Overview

Camp is a general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 99 tests passing.

## Quick Links

- [Language Design Specification](specs/2026-05-18-camp-language-design.md)
- [Implementation Status](specs/2026-05-19-implementation-status.md)
- [Package Ecosystem](specs/2026-05-18-camp-package-ecosystem.md)
- [Algebraic Effects Implementation](specs/2026-05-20-algebraic-effects-implementation.md)

## Building

Requires [Odin](https://odin-lang.org).

```bash
odin build src -out:camp
```

## Testing

```bash
odin test src
```

## Active Development Areas

1. **Compiler Correctness** - Type checker, effect system, WASM codegen
2. **LSP Server** - IDE integration with diagnostics, hover, go-to-definition
3. **Tree-sitter Grammar** - Syntax highlighting and parsing
4. **E2E Testing** - Snapshot testing framework
5. **Formatter** - Automatic code formatting

## Project Structure

```
camp/
├── src/           # Compiler source (Odin)
├── tests/         # Test suite
├── tree-sitter/   # Tree-sitter grammar
├── docs/          # Documentation
├── specs/         # OpenSpec specifications
└── project.md     # This file
```

## AI Assistant Guidelines

When working on Camp:

1. **Read specs first** - Always check `specs/` for existing design decisions
2. **Type safety** - All code must be strictly typed; no `any` or unsafe casts
3. **Effect tracking** - Side effects must be tracked in type signatures
4. **WASM target** - All code generation targets WASM/WASI
5. **No GC** - Memory managed via Perceus reference counting

See `AGENTS.md` for detailed AI working guidelines.

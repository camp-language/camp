# camp

A general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 117 unit tests + 101 e2e snapshot tests passing.

## Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Evaluation | Strict (eager) | Predictable performance, pairs well with effects |
| Type System | Strict, principal inference | Sound and decidable |
| Effects | Koka-style algebraic | Composable, lexically scoped handlers |
| Memory | Perceus RC | Deterministic, no GC, path to native |
| Target | WASM/WASI | Portable, near-native performance |
| Implementation | Odin | Fast compilation, optimal for compilers |

## Building

Requires [Odin](https://odin-lang.org).

```bash
odin build src -collection:camp=src -out:camp
```

## Running

```bash
camp build <file.camp>    # Compile a Camp source file to .wasm
camp check <file.camp>    # Type-check (and run unused analysis) without codegen
camp fmt [paths...]       # Format source files in place (defaults to .); --check, --stdin
camp test [paths...]      # Run tests; --filter <substr>, --verbose
camp lsp                  # Start the language server (stdio)
```

### Example

```bash
echo 'main! = || -> I64 { 42 }' > hello.camp
camp build hello.camp     # Produces hello.wasm
wasmer run hello.wasm   # Exits with code 42
```

## Testing

```bash
odin test src             # Unit tests
just test                 # Build and run all tests (unit + e2e + tree-sitter)
just test-e2e             # E2E snapshot tests only
just update-snapshots     # Regenerate e2e snapshots after intentional output changes
```

## Project Structure

```
src/                  Compiler (Odin)
tests/e2e/            E2E snapshot tests
tree-sitter/          Tree-sitter grammar
docs/                 Syntax recipe, diagnostics catalog, design notes
justfile              Build and test commands
```

## Docs

| Doc | Purpose |
|-----|---------|
| [syntax-recipe.md](docs/syntax-recipe.md) | Authoritative syntax reference |
| [diagnostics-catalog.md](docs/diagnostics-catalog.md) | Compiler error codes and messages |
| [stdlib-design-notes.md](docs/stdlib-design-notes.md) | Stdlib API design rationale |

See [AGENTS.md](AGENTS.md) for AI assistant guidelines.

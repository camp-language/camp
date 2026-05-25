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
wasmtime run hello.wasm   # Exits with code 42
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
tests/e2e/            E2E snapshot tests (<category>/<name>/Main.camp + expected.toml)
tree-sitter/          Tree-sitter grammar
openspec/specs/       Design specifications
docs/                 Syntax recipe, diagnostics catalog, stdlib design notes
justfile              Build and test commands
```

## Specs

Specifications are organized using [OpenSpec](https://github.com/Fission-AI/OpenSpec) in the `openspec/` directory:

| Domain | Spec |
|--------|------|
| Language | [spec](openspec/specs/language/spec.md) |
| Effects | [spec](openspec/specs/effects/spec.md) |
| Compiler | [spec](openspec/specs/compiler/spec.md) |
| Generics & Traits | [spec](openspec/specs/generics-traits/spec.md) |
| LSP | [spec](openspec/specs/lsp/spec.md) |
| Diagnostics | [spec](openspec/specs/diagnostics/spec.md) |
| Testing | [spec](openspec/specs/testing/spec.md) |
| Testing Language | [spec](openspec/specs/testing-language/spec.md) |
| Formatter | [spec](openspec/specs/formatter/spec.md) |
| Tree-sitter | [spec](openspec/specs/tree-sitter/spec.md) |
| Packages | [spec](openspec/specs/packages/spec.md) |
| Standard Library | [spec](openspec/specs/stdlib/spec.md) |
| Parallelism | [spec](openspec/specs/parallelism/spec.md) |
| Doc Comments | [spec](openspec/specs/doc-comments/spec.md) |
| Modules | [spec](openspec/specs/modules/spec.md) |
| String Interpolation | [spec](openspec/specs/string-interpolation/spec.md) |
| Unused Analysis | [spec](openspec/specs/unused-analysis/spec.md) |

## AI Development

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development.

**OpenCode integration** (both available):

- **[opencode-plugin-openspec](https://github.com/Octane0411/opencode-plugin-openspec)** — adds the `openspec-plan` agent mode (read-only code, write access to spec files)
- **OpenSpec CLI** — install with `npm install -g @fission-ai/openspec@latest`, then run `openspec init --tools opencode` to get slash commands (`/opsx:propose`, `/opsx:apply`, `/opsx:archive`, etc.)

See [AGENTS.md](AGENTS.md) for AI assistant guidelines.

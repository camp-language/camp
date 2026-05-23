# camp

A general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 117 unit tests + 101 e2e snapshot tests passing.

## Building

Requires [Odin](https://odin-lang.org).

```bash
odin build src -out:camp
```

## Running

```bash
camp build <file.camp>    # Compile a Camp source file to .wasm
camp test                 # Run tests (not yet implemented)
camp fmt                  # Format source (not yet implemented)
camp check                # Type-check only (not yet implemented)
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
just test                 # Build and test
```

## Design

Specifications are organized using [OpenSpec](https://github.com/Fission-AI/OpenSpec) in the `openspec/` directory:

| Domain | Spec |
|--------|------|
| Language | [spec](openspec/specs/language/spec.md) |
| Effects | [spec](openspec/specs/effects/spec.md) |
| Compiler | [spec](openspec/specs/compiler/spec.md) |
| LSP | [spec](openspec/specs/lsp/spec.md) |
| Diagnostics | [spec](openspec/specs/diagnostics/spec.md) |
| Testing | [spec](openspec/specs/testing/spec.md) |
| Formatter | [spec](openspec/specs/formatter/spec.md) |
| Tree-sitter | [spec](openspec/specs/tree-sitter/spec.md) |
| Packages | [spec](openspec/specs/packages/spec.md) |
| Parallelism | [spec](openspec/specs/parallelism/spec.md) |

## AI Development

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development.

**OpenCode integration** (both available):

- **[opencode-plugin-openspec](https://github.com/Octane0411/opencode-plugin-openspec)** — adds the `openspec-plan` agent mode (read-only code, write access to spec files)
- **OpenSpec CLI** — install with `npm install -g @fission-ai/openspec@latest`, then run `openspec init --tools opencode` to get slash commands (`/opsx:propose`, `/opsx:apply`, `/opsx:archive`, etc.)

See [AGENTS.md](AGENTS.md) for AI assistant guidelines.

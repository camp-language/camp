# camp

A general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Lexer and parser are functional. Type checking and code generation are not yet implemented.

## Building

Requires [Odin](https://odin-lang.org).

```bash
odin build src -out:camp
```

## Running

```bash
camp build <file.camp>    # Compile a Camp source file
camp test                 # Run tests (not yet implemented)
camp fmt                  # Format source (not yet implemented)
camp check                # Type-check only (not yet implemented)
```

## Design

See [docs/superpowers/specs/2026-05-18-camp-language-design.md](docs/superpowers/specs/2026-05-18-camp-language-design.md) for the full language design specification.

## Testing

```bash
odin test src
```

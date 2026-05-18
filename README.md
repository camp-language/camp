# camp

A general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Full pipeline implemented: lexing, parsing, canonicalization, type checking (Level inference + row unification), effect safety enforcement, effect lowering, closure conversion, CPS transform, Perceus RC insertion, and WASM/WASI code generation. 99 tests passing.

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

## Design

See [docs/superpowers/specs/2026-05-18-camp-language-design.md](docs/superpowers/specs/2026-05-18-camp-language-design.md) for the full language design specification.

## Testing

```bash
odin test src
```

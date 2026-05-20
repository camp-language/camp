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

See [project.md](project.md) for the project overview and [specs/](specs/) for detailed design specifications.

Key specifications:
- [Language Design](specs/2026-05-18-camp-language-design.md)
- [Implementation Status](specs/2026-05-19-implementation-status.md)
- [Package Ecosystem](specs/2026-05-18-camp-package-ecosystem.md)

## Testing

```bash
odin test src
```

## AI Development

This project uses [OpenSpec](https://github.com/Octane0411/opencode-plugin-openspec) for AI-assisted development. The `openspec-plan` agent mode provides:

- Read-only access to implementation files (prevents premature coding)
- Write access to `project.md`, `AGENTS.md`, and `specs/**`
- Structured planning before implementation

To use: Open the project in OpenCode and select the `openspec-plan` agent mode.

See [AGENTS.md](AGENTS.md) for AI assistant guidelines.

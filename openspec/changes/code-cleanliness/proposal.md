# Code Cleanliness & Memory Management Overhaul

## Problem

The Camp compiler codebase has accumulated technical debt across three dimensions:

1. **Code smells**: Magic numbers, commented-out code, unused imports, duplicated format strings, inconsistent error handling, pervasive `#partial switch` catch-alls
2. **Architectural issues**: Monolithic files (codegen.odin 2678 lines, typecheck.odin 2992 lines), layer violations (codegen imports semantics), `os.exit` in library code preventing embedding, grab-bag packages (base, semantics)
3. **Memory management**: LSP JSON parse tree leak (unbounded growth), `os.exit` skipping arena cleanup, missing `defer` on type_store_destroy, inconsistent allocator usage, pointer-into-dynamic-array UAF risk

## Affected Spec Domains

- `compiler` — build pipeline error propagation, codegen decomposition
- `diagnostics` — constructor boilerplate, format string duplication
- `lsp` — JSON leak, error handling
- `testing` — test helper consolidation, test memory leaks

## Current Implementation Status

- Arena-based allocation works correctly for CLI compilation paths
- LSP has known JSON leak acknowledged in comment (server.odin:42-44)
- 41 `os.exit` calls prevent compiler reuse as library
- `type_store_destroy` does O(n) work that's a no-op under arena
- 14+ near-identical AST/IR traversal switches (~2000 lines of duplication)

## Goals

1. Fix all memory leaks (LSP JSON, test discovery strings, diagnostic collector)
2. Replace `os.exit` with error propagation for library embeddability
3. Decompose monolithic files into focused modules
4. Remove codegen→semantics layer violation
5. Reduce duplication via table-driven patterns and visitor/walk
6. Apply data-oriented design: index-based Type_Var access, sparse Inferred_Type fields
7. Clean up all trivial code smells (magic numbers, unused imports, etc.)

## Non-Goals

- Three-tier AST merge (Expr/CExpr/TExpr) — deferred, needs RFC
- Feature additions or language changes
- Performance optimization beyond DoD memory layout changes

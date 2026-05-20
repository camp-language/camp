# Camp Implementation Status

> Comprehensive audit of what's implemented, what's broken, and what's missing.

**Date:** 2026-05-19
**Tests:** 117 unit tests passing, 101 e2e snapshot tests passing
**Pipeline:** lexing → parsing → canonicalization → typechecking → lowering → effect lowering → closure conversion → CPS → RC insertion → WASM codegen

---

## Fully Working

### Front-End (Complete)

| Component | Status | Notes |
|-----------|--------|-------|
| Lexer | Complete | All tokens, keywords, operators, comments, `$` prefix, `..` |
| Parser | Complete | Pratt parser; all expression/declaration/pattern/type syntax including `handle`/`intercept` |
| Canonicalizer | Complete | Surface → canonical with field sorting, name resolution, deferred imports |
| Typechecker | Complete | Bidirectional inference with Level algorithm, effect rows, row polymorphism, tag unions, effect safety, `!` naming |
| Unification | Complete | Full row unification for records, tag unions, effect rows; occurs check |
| Diagnostic framework | Complete | Typed error variants, CLI renderer (TTY colors), LSP renderer |
| LSP server | Complete | go-to-definition, hover, diagnostics, document sync, symbol index |

### Infrastructure (Complete)

| Component | Status | Notes |
|-----------|--------|-------|
| E2E snapshot testing | Complete | 101 tests across 11 categories with TOML snapshots |
| CLI | Partial | `build` and `lsp` work; `test`, `fmt`, `check` are stubs |

### WASM Format (Complete)

| Component | Status | Notes |
|-----------|--------|-------|
| Binary encoding | Complete | LEB128, all sections, all instruction types |
| Runtime stubs | Complete | `camp_alloc`, `camp_dup`, `camp_drop`, `camp_print_str`, `camp_exit` |
| WASI imports | Complete | `fd_write`, `proc_exit`, `args_get`, `args_sizes_get` |

---

## Implemented But Broken (8 Known Bugs)

These have complete implementations that produce incorrect results. Tracked in `docs/superpowers/specs/2026-05-19-compiler-correctness-design.md`.

| Bug | ID | Phase | Impact | Scope |
|-----|-----|-------|--------|-------|
| Match pattern typechecking | C5 | Typecheck | Patterns never checked against scrutinee; pattern vars never bound; no exhaustiveness | ~90 lines in typecheck.odin |
| Closure body nil | C8 | Closure convert | Closures don't close over anything; body lost during lowering | ~90 lines across ir, lower, closure_convert |
| Non-name callee lowering | C7 | Lowering | Higher-order calls like `(f x) y` call nonexistent functions; no `call_indirect` | ~110 lines across lower, ir, closure_convert, rc, codegen |
| Perceus RC replaces vars | C9 | RC insertion | Every `IR_Var` replaced by `IR_Dup`/`IR_Drop`; no variable is ever actually read | ~90 lines in rc.odin |
| Missing handler evidence | M4 | Effect lowering | When no handler on evidence stack, argument silently omitted; calling convention mismatch | ~5 lines in effect_lower.odin |
| CPS no continuations | M5 | CPS | Continuation names threaded but never generate new functions; only `IR_Return` becomes tail call | ~60 lines in cps.odin |
| Generalization unsound | M9 | Types | `generalize_at_level` doesn't check children of `Inferred_Type` are also generalizable | ~45 lines in types.odin |
| IR_Crash node missing | H2 | IR/Lower | `CExpr_Crash` discards crash semantics; no `IR_Crash` in IR union | ~15 lines across 6 files |

**Implementation order** (from correctness spec): H2 → M4 → M9 → C5 → C8 → C7 → C9 → M5

---

## Codegen Incomplete (Critical)

Most IR expression types emit `Wasm_Unreachable` — they compile to a trap at runtime.

| IR Node | Codegen Status | What Breaks |
|---------|---------------|-------------|
| `IR_Match` | Unreachable | Pattern matching doesn't execute |
| `IR_Construct_Tag` | Unreachable | Tag union values can't be created |
| `IR_Construct_Record` | Unreachable | Record values can't be created |
| `IR_Field_Access` | Unreachable | Record field access doesn't work |
| `IR_Method_Call` | Unreachable | Trait/method dispatch broken |
| `IR_Handle` | Unreachable | Effect handlers don't execute |
| `IR_Perform` | Unreachable | Effect operations don't execute |
| `IR_Closure` | Unreachable | Closures can't be created at runtime |
| `IR_Drop_Reuse` | Unreachable | Perceus in-place reuse broken |
| `IR_Alloc_At` | Unreachable | Perceus reuse allocation broken |

**Working codegen:** `IR_Literal`, `IR_Var`, `IR_Let`, `IR_Call` (direct), `IR_If`, `IR_BinOp`, `IR_Return`, `IR_Dup`, `IR_Drop`

---

## Language Features Not Implemented

### Parser Missing

| Feature | Status |
|---------|--------|
| `for` loops | Keyword exists, no parsing |

### Entirely Absent (Defined in Spec)

| Feature | Spec Section | Notes |
|---------|-------------|-------|
| Newtypes (`UserId := U64`) | §3.6 | No `Decl_Newtype`, no `:=` operator, no construction/destruction |
| Traits (constraint solving, UFCS, `is` enforcement) | §3.10 | Parsed but no constraint solving, no method dispatch, no `is` verification |
| `@derive` expansion | §3.10, §10.2 | Recorded on decls but never expanded into trait impls |
| `$` mutable variables | §3.9 | Parsed as `$` + identifier but no mutation semantics, no enforcement |
| `Throw` built-in effect | §4.6, [effects impl](2026-05-20-algebraic-effects-implementation.md) | `Throw.throw!` and `Throw([..])` defined in spec but not implemented |
| Comptime evaluation | §5.7, §10.3 | Not started |
| Module system (import resolution, multi-file) | §8.1-8.2 | `Deferred_Import` recorded but never resolved; single-file compilation only |
| `camp.toml` parsing | §8.3 | Not started |
| `pub` visibility enforcement | §3.15 | Parsed but not checked |
| No-shadowing enforcement | §3.13 | Not implemented |
| Backtick raw identifiers | §3.16 | Not implemented |
| String methods (`.len()`, `.slice()`, etc.) | §7.3 | Not implemented |
| `for` loops with `$` mutation | §3.9 | Not implemented |
| `test`/`expect` execution | §11 | Keywords parsed but `camp test` is a stub |
| `camp fmt` | — | Stub only |
| `camp check` | — | Stub only |

### Standard Library (Entirely Absent)

All §7.3 types and modules need to be built in Camp itself:

- **Types:** `List(a)`, `Map(k, v)`, `Set(a)`, `Iter(a)`, `Bytes`, `Handle(a)`
- **Helpers:** `Result`, `Option` combinators
- **Traits:** `Display`, `Hash`, `Eq`, `Ord`, `Clone`, `Serialize`, `Deserialize`
- **Effects:** `File`, `Console` (partial via WASI), `Async`, `Env`, `Time`, `Random`
- **Prelude:** Auto-imported common types/tags/traits/effects

### Concurrency (Not Implemented)

| Feature | Spec Section | Notes |
|---------|-------------|-------|
| `Async` effect with `spawn!`/`join!`/`cancel!`/`yield!` | §9.3 | Not implemented |
| State machine extraction from CPS | §9.4 | Not implemented |
| WASM component model async bridge | §9.5 | Not implemented |
| Structured concurrency enforcement | §9.6 | Not implemented |
| Channel effect | §9.8 | Future stdlib |

### Memory Management Gaps

| Feature | Spec Section | Status |
|---------|-------------|--------|
| Destructive read / in-place reuse | §3.17, §6.1 | Codegen emits `unreachable` for `IR_Drop_Reuse`/`IR_Alloc_At` |
| Cycle collector | §6.3 | Not implemented |
| Pluggable allocator | §6.4 | Not implemented |

### Infrastructure Gaps

| Feature | Status |
|---------|--------|
| `camp repl` | Not implemented — needs interactive read-eval-print loop for the Camp language; should compile and execute expressions incrementally via the existing pipeline (lex → parse → canonicalize → typecheck → lower → codegen → wasmtime) |
| Package manager (git deps) | Not implemented — needs `camp.toml` parsing, dependency resolution, git-based fetching, lockfile generation, and multi-file compilation support; see also module system gaps in §8.1-8.2 |
| tree-sitter grammar | Directory scaffolded, grammar.js not written |
| Memory leaks | Significant leaks in type store, CPS, and RC unit tests |
| Content-hash per-file caching | Not implemented |
| Parallel compilation | Not implemented (single-threaded) |

---

## E2E Test Coverage Gaps

101 tests exist but only cover: execution basics, typechecking, errors, command-line, strings, records, tag-unions, pattern-matching, effects (syntax only), closures, generics.

**No e2e coverage for:** imports/modules, traits, newtypes, `$` mutation, `for` loops, `Throw` effect, effect polymorphism, row polymorphism in function signatures, `@derive`, comptime, `pub` visibility, shadowing enforcement, raw identifiers, async/concurrency, stdlib types, Perceus RC behavior.

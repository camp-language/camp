# Modules — Technical Design

## 1. Overview

The module system transforms Camp from a single-file compiler to a multi-file compiler with import resolution, visibility enforcement, and incremental compilation. The design follows the spec's existing architecture: per-file front-end phases (cacheable by content hash), a module graph combination phase, and a whole-program back-end.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Compilation Pipeline (Multi-File)                                  │
│                                                                     │
│  Phase 1: Discover     — Find src/, collect .camp files             │
│  Phase 2: Hash         — SHA256 per file                            │
│  Phase 3: Parse        — Per file, cache by hash    ┐              │
│  Phase 4: Canonicalize — Per file, cache by hash    ├ Front-end    │
│  Phase 5: Typecheck    — Per file, cache by dep hash ┘ (parallel)  │
│  Phase 6: Module Graph — Topo sort, import resolution              │
│  Phase 7: Combine IR   — Whole-program IR                          │
│  Phase 8: Lower → ... → Codegen  — Whole-program         ┘ Back-end│
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Project Discovery

### 2.1 Finding the Project Root

Walk up from CWD looking for a `src/` directory containing at least one `.camp` file. This is the project root. If not found after reaching `/`, error out.

### 2.2 File-to-Module Mapping

```
src/Main.camp           → module Main
src/List.camp           → module List
src/Result.camp         → module Result
src/Http/Server.camp    → module Http.Server
src/Http/Client.camp    → module Http.Client
```

Algorithm:
1. Walk `src/` recursively
2. For each `.camp` file, strip `src/` prefix and `.camp` suffix
3. Replace `/` with `.`
4. Build a `map[string]Module_Info` keyed by module name

### 2.3 Module Info

```odin
Module_Info :: struct {
    name:         string,        -- e.g. "Http.Server"
    path:         string,        -- e.g. "src/Http/Server.camp"
    content_hash: string,        -- SHA256 of file contents
    file:         ^ast.File,     -- parsed AST (or nil if cached)
    canonical:    ^canonical.CFile, -- canonical form (or nil if cached)
    typed:        ^Typed_File,   -- typecheck result (or nil if cached)
    imports:      []Deferred_Import, -- extracted from canonical form
    exports:      []Export_Info,  -- pub declarations
}
```

---

## 3. Content Hash Cache

### 3.1 Cache Key Strategy

| Phase | Cache Key | Scope |
|-------|-----------|-------|
| Parse | `SHA256(file_content)` | File-independent |
| Canonicalize | `SHA256(file_content)` | File-independent |
| Typecheck | `SHA256(file_content) ++ sorted(imports_hashes)` | Depends on imports |

Parse and canonicalize are deterministic per-file — same content always produces the same result. Typecheck depends on the types of imported symbols, so its cache key includes the hashes of imported modules.

### 3.2 Cache Location

`$XDG_CACHE_HOME/camp/` (default `~/.cache/camp/`).

Cache files:
```
~/.cache/camp/<sha256>.ast        -- serialized parsed AST
~/.cache/camp/<sha256>.canonical   -- serialized canonical form
~/.cache/camp/<dep_hash>.typed    -- serialized typecheck result
```

### 3.3 Cache Invalidation

- **Parse/Canonicalize:** Invalidate when file content hash changes. Simple and exact.
- **Typecheck:** Invalidate when file content hash changes OR any imported module's content hash changes. The invalidation set is the transitive closure of dependents in the module graph.
- **Cleanup:** Append-only. User can `rm -rf ~/.cache/camp/` manually. Future: LRU or size limit.

### 3.4 Why Content-Hash Keying

Go uses this model (`$GOCACHE`). Benefits:
- Same file content always hits the same cache entry, regardless of which project
- No need to track modification timestamps
- Works correctly across branch switches and git operations
- Cache entries are immutable — no invalidation races

---

## 4. Module Graph Construction

### 4.1 Building the Graph

After canonicalizing all files, extract `Deferred_Import` lists from each `CFile.imports`. Build a directed graph where an edge from A to B means "module A imports module B."

### 4.2 Topological Sort

Process modules in dependency order (leaves first). This ensures that when we typecheck module A, all of A's dependencies have already been typechecked and their export types are available.

Algorithm: Kahn's algorithm (BFS-based topo sort). Detects cycles naturally — if the result doesn't include all nodes, the remaining nodes form a cycle.

### 4.3 Cycle Reporting

When a cycle is detected, report it as a readable path: "cyclic dependency: A → B → C → A". Use DFS to find the actual cycle path, not just "cycle detected."

---

## 5. Import Resolution

### 5.1 Current State

Currently, `Canonical_Name` always has `module = NO_NAME` and `is_local = true`. Imports are recorded as `Deferred_Import` and ignored. The typechecker has no cross-module awareness.

### 5.2 Resolution Pass

After the module graph is built and topologically sorted, a new **import resolution** pass populates `Canonical_Name.module` and builds per-module scopes.

For each module in topological order:

1. **Start with local scope** — all declarations in the module
2. **Process each `Deferred_Import`:**

   | Import form | Effect on scope |
   |-------------|----------------|
   | `import List` | Add qualified entries: `List.map → Canonical_Name{module: "List", name: "map", is_local: false}` for every `pub` member of `List` |
   | `import List exposing [map]` | Add qualified entries (as above) PLUS unqualified alias: `map → Canonical_Name{module: "List", name: "map", is_local: false}` |
   | `import List as L` | Add qualified entries under alias: `L.map → Canonical_Name{module: "List", name: "map", is_local: false}` |
   | `import List exposing [map] as L` | Both unqualified `map` and qualified `L.map` |

3. **Conflict detection** — if an `exposing` name already exists in scope, error
4. **Visibility check** — verify all referenced names are `pub` in their defining module

### 5.3 Canonical_Name Update

```odin
Canonical_Name :: struct {
    module:   Intern_ID,  -- actual module ID (was always NO_NAME)
    name:     Intern_ID,  -- the local name
    is_local: bool,       -- false for imported names (was always true)
}
```

This single change propagates through the entire type system. When `module` is populated, the typechecker can look up cross-module types by `(module, name)`.

### 5.4 Export Info

Each module publishes its `pub` declarations:

```odin
Export_Info :: struct {
    name:       Intern_ID,      -- the exported name
    kind:       Export_Kind,    -- const, type, newtype, trait, effect, alias
    type_sig:   Inferred_Type,  -- the type signature (for typechecking consumers)
    is_local:   bool,           -- always false for exports
}
```

### 5.5 Resolution of Dot Expressions

`List.map(x)` is parsed as `Expr_Call(Expr_Field_Access(Expr_Var("List"), "map"), [x])`. During import resolution:

1. `Expr_Var("List")` resolves to the module name (not a variable)
2. `.map` resolves to `Canonical_Name{module: "List", name: "map"}`
3. The whole expression becomes a cross-module function call

This requires the typechecker to distinguish "List is a module name" from "List is a variable" during name resolution.

---

## 6. Visibility Enforcement

### 6.1 When to Check

Visibility is checked at two points:

1. **Import resolution** — when `import M exposing [name]` is processed, verify `name` is `pub` in M
2. **Qualified access** — when code in module A uses `M.name`, verify `name` is `pub` in M

### 6.2 What Counts as `pub`

- `pub` on `Decl_Const` → the function/value is exported
- `pub` on `Decl_Newtype` → the newtype constructor and all its tags are exported
- `pub` on `Decl_Trait` → the trait is exported
- `pub` on `Decl_Effect` → the effect is exported
- `pub` on `Decl_Alias` → the alias is exported

Private declarations (no `pub`) are accessible only within the defining module. The check is: if `Canonical_Name.module` differs from the current module, the referenced name must be `pub`.

---

## 7. Prelude Injection

### 7.1 Approach

The compiler injects builtin types and values directly into the type checker environment. No `Camp.camp` source file exists. This avoids bootstrapping issues — the prelude doesn't need to be compiled.

### 7.2 Injected Builtins

| Category | Names | Implementation |
|----------|-------|---------------|
| Types | `Bool`, `I64`, `U64`, `F64`, `Str`, `Unit` | `Inferred_Type` with `Constructor` tag, injected into `Type_Env` |
| Tags | `True`, `False` | Tag constructors owned by `Bool` newtype |
| Operators | `+`, `-`, `*`, `/`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`, `not` | Builtin function entries with appropriate type signatures |
| Functions | `println!`, `panic` | Builtin function entries with effect rows |

### 7.3 Future Migration

When a stdlib exists in Camp source code, many builtins can migrate to `src/Camp.camp`. The compiler would auto-inject `import Camp exposing [...]` at the top of every file. `import Camp exposing []` opts out. For now, direct injection is simpler.

### 7.4 Bool as Newtype

`Bool` is implemented as a newtype wrapping a tag union: `Bool := [True | False]`. This makes it consistent with the newtype system — `True` and `False` are tags owned by `Bool`. They require qualification (`Bool.True`) unless imported unqualified via the prelude.

The prelude auto-exposes `True` and `False`, so they're available unqualified by default.

---

## 8. Multi-File Typechecking

### 8.1 Per-File with Cross-Module Awareness

Typechecking remains per-file but now has access to imported modules' type signatures:

1. **Typecheck in topological order** — dependencies before dependents
2. **For each module**, load the export table of all imported modules
3. **Resolve cross-module references** using `Canonical_Name{module, name}` → look up in the export table
4. **Unify types** — structural types unify across modules; nominal types only unify with themselves

### 8.2 Cross-Module Unification

| Type kind | Cross-module behavior |
|-----------|----------------------|
| Structural record | Unifies by shape regardless of module |
| Structural tag union | Unifies by tags regardless of module |
| Nominal newtype | Only unifies with the same `Canonical_Name{module, name}` |
| Type variable | Binds to whatever is needed |
| Effect row | Unifies by effect names regardless of module |

### 8.3 Typecheck Cache Key

```
typecheck_hash = SHA256(
    file_content_hash ++
    sorted(imports_content_hashes)
)
```

If a dependency's content hash changes, the dependent's typecheck cache key changes and it gets re-typechecked. This is correct because imported type signatures may have changed.

---

## 9. Multi-File Lowering & Codegen

### 9.1 Combining IRs

After typechecking all modules, combine their IRs into a single whole-program IR:

1. Collect all `IR_Decl_Fn` and `IR_Decl_Const` from all modules
2. Namespace function names: `map` in module `List` → `List__map` in WASM
3. Resolve cross-module calls: `List.map(x)` in module `Main` → `call List__map(x)` in IR

### 9.2 Name Mangling

```odin
mangle_name :: proc(module: Intern_ID, name: Intern_ID) -> string {
    return fmt.tprintf("{}__{}", intern.resolve(module), intern.resolve(name))
}
```

Double underscore `__` separates module path from name. Dotted modules use single underscore: `Http.Server__handle` for `Http.Server.handle`.

### 9.3 Runtime Deduplication

Runtime helpers (`camp_alloc`, `camp_dup`, `camp_drop`, `camp_print_str`, `camp_exit`) are emitted once. Each module's IR references them by name; the final codegen emits exactly one copy.

### 9.4 Entry Point

The WASM `start` function (or the exported `main` function) calls `Main__main` — the mangled name of `main!` in the `Main` module.

---

## 10. New File Structure

New source files added to the compiler:

| File | Purpose | ~Lines |
|------|---------|:------:|
| `src/discovery.odin` | Project root discovery, file map, path→module mapping | 80 |
| `src/cache.odin` | Content hashing, cache read/write, invalidation | 120 |
| `src/module_graph.odin` | Dependency graph, topo sort, cycle detection | 150 |
| `src/import_resolve.odin` | Import resolution, scope building, visibility enforcement | 330 |
| `src/export_table.odin` | Per-module export info collection and lookup | 80 |

Modified existing files:

| File | Change | ~Lines |
|------|--------|:------:|
| `src/cli.odin` | Multi-file pipeline, discovery, caching | 100 |
| `src/typecheck.odin` | Prelude injection, cross-module type lookup | 60 |
| `src/lower.odin` | Cross-module call resolution, name mangling | 60 |
| `src/codegen.odin` | Namespaced WASM exports, runtime dedup | 40 |
| `src/context.odin` | Module map, export tables | 30 |

---

## 11. Error Catalog

| ID | Category | Message Template |
|----|----------|-----------------|
| M1 | Module | `module '{name}' not found` |
| M2 | Module | `cyclic dependency: {cycle_path}` |
| M3 | Import | `'{name}' is not exported from module '{module}'` |
| M4 | Import | `'{name}' imported from {module} conflicts with existing binding — use qualified access {module}.{name}` |
| M5 | Import | `'{name}' is ambiguous — imported from both {mod_a} and {mod_b}; use qualified access` |
| M6 | Entry | `entry point not found — expected src/Main.camp with pub main!` |
| M7 | Entry | `entry point module Main does not define pub main!` |
| M8 | Project | `no Camp source files found — expected a src/ directory` |

---

## 12. Design Decisions

| # | Decision | Chosen | Alternatives | Rationale |
|---|----------|--------|-------------|-----------|
| 1 | Cache location | `$XDG_CACHE_HOME/camp/` | Project-local `.camp/cache/`, OS temp | Go precedent; content-hash keyed; project-independent; gitignore-friendly |
| 2 | Cache key for typecheck | File hash + sorted import hashes | File hash only, timestamp | Imports affect typecheck results; must include them |
| 3 | Prelude implementation | Compiler-injected builtins | Source-file prelude (`Camp.camp`) | Avoids bootstrapping; simpler; can migrate later |
| 4 | Module path style | Dotted (`Http.Server`) from directory structure | Flat only, hierarchical namespaces | Directories organize code; dots are familiar from most languages |
| 5 | Name mangling | `Module__name` (double underscore) | `Module_name`, `Module.name` | Double underscore avoids collision with single underscores in names; WASM allows underscores |
| 6 | Entry point convention | `src/Main.camp` with `pub main!` | CLI flag `--main`, auto-detect | Convention over configuration; matches spec |
| 7 | Dependency resolution | Local files only (no git deps) | Git-based fetching from `camp.toml` | Smaller scope; package manager is separate |
| 8 | Cycle detection | Kahn's algorithm (topo sort) | DFS coloring, Tarjan | Detects cycles naturally; gives correct processing order |

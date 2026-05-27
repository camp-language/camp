# Deferred Parser Features (P3)

These six syntax recipe features are not yet implemented. They were
deferred from the compiler-gaps audit because each requires extensive
cross-cutting changes and careful design. All downstream pipeline stages
(except the parser) are either already prepared or need minimal changes.

---

## GAP-30: String Pattern Interpolation

**Syntax Recipe:** §5 — Pattern strings with `${expr}` interpolation

**Current state:**
- The lexer already produces `Interpolated_String_Literal` tokens
- The parser's expression path handles interpolated strings
- The pattern path treats interpolated string literals as a wildcard fallthrough (emits error)

**What needs to happen:**

1. **AST** (`src/frontend/ast.odin`): Add `Pattern_Interpolated_String` to
   the `Pattern` union, with a `parts: [dynamic]String_Part` field (reuse
   `String_Part` from `Expr_Interpolated_String`). Each part is either a
   `String_Segment` (literal text) or a `Pattern` (for `${…}` holes).

2. **Parser** (`src/frontend/parser.odin`): In `parse_pattern`, handle
   `.Interpolated_String_Literal` by iterating the string parts: literal
   segments become `String_Segment`, `${expr}` segments are parsed as
   patterns. Produce `Pattern_Interpolated_String`.

3. **Canonical** (`src/semantics/canonical.odin`): Add
   `CPattern_Interpolated_String` with `CPattern_String_Part` union.

4. **Typed** (`src/semantics/typed.odin`): Add `TPattern_Interpolated_String`.

5. **Canonicalize, typecheck, lower, format, analysis** — one case each.

**Design question:** Are interpolated parts in pattern position `Pattern`
or `Expr`? In the expression path, `${expr}` is an expression. In patterns,
it should probably be a pattern (e.g., `${x}` binds `x`). The parser must
decide which to produce.

---

## GAP-32: Effect Aliases (`effect alias E = Row`)

**Syntax Recipe:** §3 — `effect alias Name! = Effect_Row`

**Current state:**
- No AST node, parser case, or downstream handling exists
- Effects are declared with `effect Name! { op!(…) -> T }` syntax only

**What needs to happen:**

1. **AST** (`src/frontend/ast.odin`): Add `Decl_Effect_Alias` to the `Decl`
   union with fields: `name: base.Intern_ID`, `target: ^Type`, `is_pub: bool`,
   `doc_comment: string`, `span: base.Source_Span`.

2. **Parser** (`src/frontend/parser.odin`): After consuming the effect name
   (an `Upper_Id` ending with `!`), check for `=` (Eq token). If present,
   parse the right-hand side as a type (the target effect row). Produce
   `Decl_Effect_Alias`.

3. **Canonical** (`src/semantics/canonical.odin`): Add `CDecl_Effect_Alias`.

4. **Typed** (`src/semantics/typed.odin`): Add `TDecl_Effect_Alias`.

5. **Canonicalize** (`src/semantics/canonicalize.odin`): Add case to
   canonicalize the declaration, resolve the target type.

6. **Typecheck** (`src/semantics/check_decl.odin`): Resolve the alias target
   type via `convert_type_to_var`. Register the alias so that uses of the
   effect name resolve to the target row.

7. **IR/Lower** (`src/ir/lower.odin`): Skip — effect aliases have no runtime
   representation (pure type-level construct).

8. **Format, analysis, LSP, mono** — one trivial case each.

**Design question:** Should alias expansion happen eagerly in the typechecker
or lazily during effect row operations? Eager is simpler.

---

## GAP-33: Newtype Where-Clauses & Method Blocks

**Syntax Recipe:** §3 — `newtype Foo[T] where T: Ord { … }`

**Current state:**
- `Decl_Newtype` has `type_params` and `derive_targets`, but no
  `where_clauses` or `methods` fields
- Newtypes with type params parse but where-clauses and method blocks
  are parse errors

**What needs to happen:**

1. **AST** (`src/frontend/ast.odin`):
   - Add `where_clauses: [dynamic]Where_Clause` to `Decl_Newtype`
   - Add `Newtype_Method :: struct { name: base.Intern_ID, params: [dynamic]Func_Param, return_type: ^Type, body: Expr, span: base.Source_Span }`
   - Add `methods: [dynamic]Newtype_Method` to `Decl_Newtype`

2. **Parser** (`src/frontend/parser.odin`):
   - After parsing type params, check for `where` keyword and parse
     where-clauses (same pattern as const declarations)
   - After the inner type, check for `{` and parse method declarations:
     each method is `name(params): ReturnType = body`

3. **Canonical, typed** — propagate `where_clauses` and `methods` through
   `CDecl_Newtype` and `TDecl_Newtype`.

4. **Canonicalize** — propagate fields.

5. **Typecheck** (`src/semantics/check_decl.odin`):
   - Where-clauses: apply trait constraints to the type params (same
     machinery as const/lambda where-clauses)
   - Methods: typecheck each method body with `Self` bound to the newtype

6. **IR/Lower** — methods become top-level functions with the newtype name
   as a prefix (e.g., `newtype Foo` with method `bar` becomes `Foo_bar`).

**Design question:** Should newtype methods be resolved via the trait impl
system or be standalone? The `is` impl blocks are already the trait
mechanism, so newtype methods might be syntactic sugar for `is` impls.

---

## GAP-37: Record Update Syntax (`{ record | field = value }`)

**Syntax Recipe:** §4 — `{ expr | field: value, ... }`

**Current state:**
- `Expr_Record_Update` AST node exists in `ast.odin`
- `typecheck_record_update` in `check_expr.odin` handles it
- `lower_trecord_update` in `ir/lower.odin` handles it
- `format_expr_record_update` in `format/expr.odin` handles it
- Only the **parser** is missing

**What needs to happen:**

1. **Parser** (`src/frontend/parser.odin`): In `parse_record_expr`, after
   parsing `{`, peek ahead. If the first element is an expression (not a
   `name:` or `name` field pattern) followed by `|` (Pipe token):
   - Consume the record expression
   - Consume `|`
   - Parse `field = value` pairs as field updates
   - Produce `Expr_Record_Update{record = expr, updates = [{name, value}, …], span = …}`

2. **Read the Expr_Record_Update struct** in `ast.odin` to verify the
   exact field names and types before writing the parser code.

**Complexity:** Distinguishing `{ expr }` (block expression) from
`{ expr | … }` (record update) from `{ ..expr, … }` (record with spread)
from `{ name: value }` (record literal) requires lookahead. The current
`parse_block_or_record` function handles this — the record update path
needs to be inserted before the field-parsing fallthrough.

---

## GAP-38: Type Wildcard `_` in Type Position — COVERED BY GAP-36

Already implemented. The `Type_Wildcard` AST node was dead code; GAP-36
activated it by adding `_` recognition in `parse_type`.

---

## GAP-39: Pattern_Record `..rest` Field — COVERED BY GAP-39

Already implemented. The `rest` field on `Pattern_Record` accepts
`..name` syntax after `..` in a record pattern.

---

## Implementation Guidance

### Order by effort

| # | Effort | Files |
|---|--------|-------|
| GAP-37 | Small (~1h) | 1 file (parser only, downstream ready) |
| GAP-32 | Medium (~2h) | 6+ files (new Decl variant, full pipeline) |
| GAP-33 | Large (~4h) | 8+ files (new fields, parser, typecheck, lower) |
| GAP-30 | Medium (~2h) | 8+ files (new Pattern variant, full pipeline) |

### Recommended order

1. **GAP-37 first** — highest leverage; downstream is ready, only parser
   needs work. Unlocks functional record updates immediately.
2. **GAP-30 second** — enables string pattern matching, a common use case.
3. **GAP-32 third** — effect aliases are useful for complex effect rows.
4. **GAP-33 last** — newtype methods are syntactic sugar; `is` impl
   blocks already provide the same functionality.

### Pattern for adding a new AST variant

Every new `Decl`/`Expr`/`Pattern` union variant requires updates in these
files (use the existing variants as templates):

1. `src/frontend/ast.odin` — union member + struct
2. `src/frontend/parser.odin` — parse case
3. `src/semantics/canonical.odin` — canonical union + struct
4. `src/semantics/canonicalize.odin` — canonicalize case
5. `src/semantics/typed.odin` — typed union + struct
6. `src/semantics/check_decl.odin` or `check_expr.odin` or
   `check_control.odin` — typecheck case
7. `src/ir/lower.odin` — lower case (skip for type-only constructs)
8. `src/format/decl.odin` or `format/expr.odin` — format case
9. `src/mono/mono.odin` — monomorphization (skip for non-generic)
10. `src/analysis/unused.odin` — unused analysis (add to skip list)
11. `src/lsp/symbol_index.odin` — LSP (add to skip list)

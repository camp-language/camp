---
# camp-mfkq
title: Parse where clauses on Decl_Newtype and Decl_Trait
status: todo
type: task
priority: normal
created_at: 2026-06-27T17:22:44Z
updated_at: 2026-06-27T17:22:44Z
---

Source: docs/language-spec.md §2 Function Types and §3 Nominal Types.

The recipe (§3, language-spec.md:142,145) shows `where` clauses on nominal type declarations:

    @Name(params) derives Trait1, Trait2 where a is Eq, e is Debug: pub [Ok(a) | Err(e)] { methods }

Order: `@Name(params)` → `derives ...` → `where ...` → `:` → body → `{ methods }`.

## Gap
`Decl_Newtype` (`src/frontend/ast.odin:85-94`) and `Decl_Trait` (`ast.odin:60-67`) have **no `where_clauses` field**, and the newtype parser (`src/frontend/parser.odin:3180-3211`) and trait parser (`parser.odin:3014-3058`) never check `.Kw_Where`. So `where` on nominal/trait declarations fails to parse despite the recipe prescribing it.

`Decl_Const` (`ast.odin:24`) and `Expr_Lambda` (`ast.odin:272`) already have `where_clauses` slots and parse paths — use them as the template.

## Work
1. Add `where_clauses: [dynamic]Where_Clause` to `Decl_Newtype` and `Decl_Trait` AST nodes (`src/frontend/ast.odin`) and the canonical equivalents (`src/semantics/canonical.odin`).
2. Parse `where` in the newtype and trait parsers (`src/frontend/parser.odin`), in the position the recipe prescribes (after `derives`, before `:` for newtypes).
3. Plumbed through canonicalize (`src/semantics/canonicalize.odin` — see how decl-level where-clauses fold into lambda type-param constraints at canonicalize.odin:121-159) and typecheck.
4. Tests: E2E exercise of a nominal type with a `where` clause; unit test if a programmatic harness fits.

## Non-goal
Do not add `where` to function *type annotations* — that is intentionally banned (recipe:112, now reworded). `where` lives on declaration binders only.

## Reference
Recipe §2 Function Types (language-spec.md:112) states the principle: constraints attach to binders that introduce type variables, not to structurally-equated type annotations.

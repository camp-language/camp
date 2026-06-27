---
# camp-9635
title: Review Nominal Type Construction section for under-specification
status: todo
type: task
priority: normal
created_at: 2026-06-27T23:17:14Z
updated_at: 2026-06-27T23:17:14Z
---

Source: docs/language-spec.md §4 "Nominal Type Construction" (lines ~518-524) and §3 "Nominal Types" (lines ~173-191).

The section currently oversimplifies nominal construction syntax and rules. Several parser-supported forms are undocumented, and the `@`-prefix rule is internally inconsistent.

## Current text (§4 Nominal Type Construction, language-spec.md:518-524)
- Tag variants: `Ok(42)`, `Err("oops")`, `None` (no `@` prefix)
- Newtypes: `@UserId(42)` — `@` prefix distinguishes nominal type construction from tag construction
- Rule: `@` is used when the constructor name IS the type name (newtype pattern: `@UserId` type has `UserId` constructor). When they differ (like `@Result` type with `Ok`/`Err` constructors), no `@` needed.
- From outside module: `Result.Ok(42)` or `Ok(42)` if imported via `import Result { [Ok, Err], ... }`

## Gaps found

1. **Multi-payload newtype construction is undocumented.** Recipe (line 520) only shows single-payload `@UserId(42)`. Parser fully supports multi-arg payloads: `Expr_Nominal_Construct.payload` is a `[dynamic]Expr` (parser loop at src/frontend/parser.odin:1010-1022). Add a multi-payload example (e.g. `@Point(x, y)` or `@Result(Ok, value)`). Note related bean camp-ityu (completed) documented a historical codegen trap for multi-payload nominal constructs — the feature is real and used.

2. **Qualified `@TypeName.Variant(...)` form is under-specified.** Line 524 documents `Result.Ok(42)` only for the BARE (no-`@`) tag construct. Parser supports the `@`-prefixed qualified form (`parser.odin:1004-1008`): `@Result.Ok(42)` parses (test at src/test_parser.odin:444). The recipe never shows `@`-prefixed qualified nominal construction. The relationship between "no `@` needed when names differ" (line 523) and qualified `@Result.Ok` (which has `@` AND a differing variant) is internally inconsistent — a reader cannot tell when `@Result.Ok(42)` vs `Result.Ok(42)` is correct.

3. **`@` for pattern destruction is barely documented.** Line 521 mentions "newtype construction/destruction" but §4 covers only construction. §5 Patterns (language-spec.md:529-564) does not show `@TypeName(...)` pattern syntax. Parser handles `@TypeName.Variant(pattern)`, `@TypeName(pattern)`, and bare `@TypeName` patterns at src/frontend/parser.odin:2330-2361. Add a destruction example to §5.

4. **"constructor name == type name" rule ambiguous for multi-variant nominals.** Line 522-523 frames the `@` rule around the newtype single-variant pattern. Does not state how to construct a multi-variant nominal where one variant coincides with the type name, or how `@` interacts with qualified variants. Clarify or provide a decision tree.

5. **Bare `@Name` no-payload form.** Parser (parser.odin:996-1032) handles `@None` / bare `@Name` with following non-`(` token as an empty-payload `Expr_Nominal_Construct`. The recipe does not distinguish this from the no-payload tag form `None` (line 518, no `@`). When is bare `@Name` valid vs `Name`?

## Work
This bean is a DESIGN REVIEW, not implementation. The output should be a recorded set of decisions in docs/language-spec.md that:
(a) clarify when `@` is required / optional / forbidden across: single-payload newtype, multi-payload newtype, qualified variant, bare no-payload, cross-module access;
(b) reconcile the `@Result.Ok(42)` (qualified + `@`) form with the "no `@` needed when names differ" rule;
(c) add a destruction example to §5 Patterns;
(d) add a multi-payload construction example to §4.

After the spec is clarified, if parser/typecheck behavior diverges from the clarified rules, file implementation beans (separate) referencing the new spec text.

## Inputs
- docs/language-spec.md §3 Nominal Types, §4 Nominal Type Construction, §5 Patterns
- src/frontend/parser.odin:996-1032 (parser_parse_nominal_construct), :2330-2361 (pattern side)
- src/frontend/ast.odin (Expr_Nominal_Construct)
- src/test_parser.odin:422,439,444 (existing parser tests for nominal construct)
- .beans/camp-ityu (historical multi-payload codegen trap — confirms feature is real)

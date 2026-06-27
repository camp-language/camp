---
# camp-h9x1
title: Wire C0908 unused type param check (nominal types + aliases + effects)
status: todo
type: task
priority: normal
created_at: 2026-06-27T17:28:09Z
updated_at: 2026-06-27T17:28:09Z
---

Source: docs/language-spec.md §2 "Type Parameters (unused / phantom)" (added 2026-06-27).

The recipe now codifies the rule:
- Unused type params in ALIAS declarations → compile error.
- Unused type params in EFFECT declarations → compile error.
- Unused type params in NOMINAL type declarations → C0908 warning, UNLESS prefixed with `_` (phantom type parameter, e.g. `@Phantom(_a): pub [Tag]`).

## Existing scaffolding
- Diagnostic C0908 UNUSED TYPE PARAMETER already exists (docs/diagnostics-catalog.md §10.9). Constructor `diag_unused_type_parameter` at src/diagnostics/constructors.odin:2132-2144 — defined but with ZERO call sites.
- `_a` already parses as a Type_Variable retaining the underscore name (src/frontend/parser.odin:2522-2529). Newtype params are stored as raw Intern_IDs (src/semantics/canonical.odin:85). Detecting a `_` prefix is a string check — no AST change needed.
- Value-level precedent for `_`-as-discard convention: C0210, C0900 "Prefix with `_` to mark intentionally unused". Extending to type-param position is consistent.

## Work (nominal types — implement now)
For Decl_Newtype in src/semantics/check_decl.odin:339-413 (typecheck_newtype_decl):
1. After converting the inner type (convert_type_to_var at line 349), walk d.inner_type collecting referenced type-param IDs.
2. For each d.type_params[i] not referenced AND not `_`-prefixed, emit C0908 via diag_unused_type_parameter.
3. `_`-prefixed unused params are silently allowed (phantom types).

## Work (aliases — blocked on prerequisite bean)
Alias unused-param enforcement is blocked on a parser gap: parameterized alias syntax (`AliasName(a): List(a)`) is documented in the recipe (§2 Type Aliases) but parser_parse_const_decl (src/frontend/parser.odin:417) never fills type_params for the alias path — all kitchen-sink alias examples are commented out (tests/e2e/language/kitchen-sink/Main.camp:128-130). This bean should track the alias unused-param check as a follow-on once the parameterized alias parsing bean (separate, not yet created) lands.

## Work (effects)
Decl_Effect has type_params parsed via `<T,U>` (src/frontend/parser.odin:451-483). Apply the same compile-error rule as aliases: every declared effect type param must be referenced in at least one operation signature. Effects are transparent, so phantom params carry no information (unlike nominal types).

## Severity
C0908 is currently a Warning in the catalog — appropriate for nominal types. The alias/effect unused-param ERROR needs either a new code in the C10xx range (unused errors) or a severity-parameterized emission of C0908. Recommend a new C10xx code for the alias/effect error case to match the catalog's warning(C09xx) vs error(C10xx) split.

## Tests
- E2E: nominal type with unused non-`_` param → C0908 warning. Nominal type with `_`-prefixed unused param → no diagnostic. Alias/effect with unused param → error (once parsing exists for aliases).
- Unit: programmatic verification if a harness fits.

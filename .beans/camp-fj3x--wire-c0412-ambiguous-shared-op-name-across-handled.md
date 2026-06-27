---
# camp-fj3x
title: Wire C0412 ambiguous shared op name across handled effects
status: todo
type: task
priority: normal
created_at: 2026-06-27T22:36:34Z
updated_at: 2026-06-27T22:36:34Z
---

Source: docs/language-spec.md §4 "Handle" (rule added 2026-06-27).

## Rule
It is a compile error for a multi-effect `handle` block to handle two or more effects that declare operations with the same name. The clause syntax `.op(resume, args) => body` carries no effect qualifier (Handler_Arm.op at src/frontend/ast.odin:487-492 is just the bare op name), so a shared op name is ambiguous.

## Current behavior (the bug)
typecheck_synth ^CExpr_Handle at src/semantics/typecheck.odin:836-852 iterates `for eff in e.effects`, looks up `store.effect_ops[key]` for each effect, and on the first effect whose op sigs contain `arm.op`, sets `owner_effect_name` and `break`s. If two handled effects both declare an op with the same name, the clause silently binds to whichever effect appears first in `e.effects`. No ambiguity check, no error. Cross-effect op-name collision is also NOT checked at the effect-definition level — `store.effect_ops` is keyed per-effect (check_decl.odin:118) so global collision isn't visible there.

## Work
1. Add diagnostic C0412 AMBIGUOUS HANDLER OPERATION to docs/diagnostics-catalog.md §4. Constructor in src/diagnostics/constructors.odin. Message names the conflicting op and the candidate effects (e.g. "operation `.op` is declared by both `E!` and `F!` — split into separate handle blocks or rename the op").
2. In the ^CExpr_Handle arm of typecheck_synth (src/semantics/typecheck.odin:836-852), replace the break-on-first-match resolution: for each `arm`, collect ALL effects in `e.effects` whose `store.effect_ops` contain `arm.op`. If count > 1, emit C0412 and skip emitting the clause (or pick first and continue — but the error is the point).
3. If count == 0, the existing C0404 (EFFECT NOT IN SCOPE / unknown op) path already applies.
4. If count == 1, current behavior is preserved.

## Tests
- E2E: two effects each declaring an op with the same name, handled in a single `handle` block → C0412 error.
- E2E: two effects with disjoint op names + a single shared-name op, handled together → C0412 still fires (only the shared op is ambiguous).
- E2E: same two effects handled in SEPARATE `handle` blocks (one each) → compiles fine (the escape hatch).
- E2E: single effect with a unique op name → no diagnostic (regression guard).
- Unit: programmatic resolution test if a harness fits.

## Recipe cross-reference
docs/language-spec.md §4 "Handle" — the multiple-effects clause now documents this rule. recipe:457 was also corrected: the clause head is `.op(resume, args)`, not `.op!` (the `!` was schematic, not literal parser syntax).

## Non-goal
No new effect-qualification syntax for handler clauses (e.g. `Effect.op(...)`) is being added — the escape hatch is "split into separate handle blocks." If a qualification syntax is wanted later, that's a separate recipe change.

---
# camp-de8q
title: Review Par Block design against record builder proposal
status: todo
type: task
priority: normal
created_at: 2026-06-27T22:34:27Z
updated_at: 2026-06-27T22:34:27Z
---

Source: docs/language-spec.md §4 "Par Blocks" vs docs/ideas/record-builder-and-applicative-composition.md.

## Context

Camp's par block syntax (recipe §4, language-spec.md:433-444):

    par { x: e1, y: e2, z: e3 }
    par for x in xs { body }

Currently: named entries only, returns a record `{ name: T1, ... }`. `par for` returns `{}`. Fail-fast, effects handled outside the block.

The record-builder idea doc proposes a *separate* syntax for composing wrapped values into a record (doc:4.2, line 259):

    { combinator <- field1: expr1, field2: expr2, ... }

desugared to nested `map2` calls — applicative composition without HKTs.

## Why review now

These two features share a surface shape: "named entries producing a record." If both land, Camp will have two record-shaped construction forms:

1. `par { name: expr, ... }` — concurrency, record-typed result, fail-fast
2. `{ map2 <- name: expr, ... }` — applicative composition via a combinator

This is worth a design review BEFORE either becomes load-bearing, because:

- **Surface ambiguity risk.** Both use `{ name: expr, ... }` donation. The record builder introduces `<-` as the differentiator; par uses the `par` keyword. A reader could mistake one for the other.
- **Semantic overlap.** `par` is "evaluate branches concurrently and collect into a record." A record builder over a concurrency combinator (e.g. a `par_map2`) subsumes `par`'s record construction. Conversely `par` over effectful branches already interacts with `map2`-style composition because effects must be handled outside.
- **Failure semantics.** `par` is fail-fast (recipe:442). The record-builder doc explicitly addresses error accumulation vs fail-fast (doc §6, line 612-619), with `Validate!` for accumulate and `map2_result` for fail-fast. If `par` is fail-fast and record builders can be either, the par block looks like a special case of "record builder with a concurrency combinator + fail-fast strategy."
- **`par for`** (returns `{}`, like `for` — recipe:441) has no analog in the record-builder proposal. Need to decide whether `par for` stays a distinct form or folds under a different mechanism.

## What the review should decide

1. **Coexistence or unification.** Keep `par { ... }` as syntax sugar for a specific concurrency combinator + record builder, OR keep them as orthogonal features with clearly distinct syntax.
2. **Differentiator clarity.** If both stay, is `par` vs `<-` enough to disambiguate, or is there a cleaner boundary (e.g. par blocks require `par` keyword, record builders reuse record-literal syntax with `<-`)?
3. **Failure strategy for `par`.** Should `par`'s fail-fast be a property of the concurrency strategy only, leaving accumulation to a `Validate!` handler — consistent with the doc's "effects and builders are orthogonal" framing (doc:601-606)? Or does `par` need its own accumulation knob?
4. **`par for` scope.** Is `par for` load-bearing as a record-less concurrent iteration, or a candidate for removal/folding once record builders exist?
5. **Effect interaction.** Recipe:443 says effects in par branches handled outside the block. Does a record builder over an effectful combinator interact with this constraint — e.g., can a builder's combinator itself be effectful?

## Inputs to the review
- docs/language-spec.md §4 Par Blocks (language-spec.md:433-444) and §3 Record Types / record construction (recipe:418 mentions `..spread` in construction).
- docs/ideas/record-builder-and-applicative-composition.md — full design doc.
- docs/discovering-gaps.md and docs/process-backlog.md for review process.
- No existing bean covers this intersection; this bean IS the tracker.

## Outcome
A recorded design decision (update docs/language-spec.md §4 with the clarified Par Block scope, and either cross-reference or fold into the record-builder idea doc). May open implementation beans as follow-ons.

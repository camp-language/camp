## ADDED Requirements

### Requirement: par Block Syntax

The `par` keyword SHALL introduce a block that desugars to `Parallel!.all!`. The `par { e1, e2, e3 }` block SHALL desugar to `Parallel!.all!([|| e1, || e2, || e3])` and return a tuple of each expression's result type. The `par for x in xs { body }` block SHALL desugar to `Parallel!.for_each!(xs, |x| body)`.

#### Scenario: par block returns typed tuple

- **GIVEN** `par { compute_alpha!(), compute_beta!() }` where alpha returns `Int` and beta returns `Str`
- **WHEN** the block executes
- **THEN** the result type SHALL be `(Int, Str)` — a tuple preserving each expression's type

#### Scenario: par for desugars to for_each

- **GIVEN** `par for r in records { process_record!(r) }`
- **WHEN** canonicalization runs
- **THEN** it SHALL be equivalent to `Parallel!.for_each!(records, |r| process_record!(r))`

### Requirement: Collection Method Sugar

`List(a)` SHALL provide `par_map!`, `par_filter!`, `par_reduce!`, and `par_for_each!` methods that desugar to `Parallel!` effect operations at canonicalization. The receiver moves from being the method target to being the first argument of the effect operation.

#### Scenario: Method sugar desugars correctly

- **GIVEN** `records.par_map!(|r| process!(r))`
- **WHEN** canonicalization runs
- **THEN** it SHALL be equivalent to `Parallel!.map!(records, |r| process!(r))` with `Parallel!` in the effect row

#### Scenario: Method chaining

- **GIVEN** `records.par_map!(|r| process!(r)).par_filter!(|r| r.is_valid())`
- **WHEN** canonicalization runs
- **THEN** each method SHALL desugar to a `Parallel!` operation and the effect row SHALL accumulate `Parallel!`

### Requirement: Method Sugar Is Canonical Desugaring

Collection method sugar for effects SHALL be implemented as a canonical desugaring pass, not as UFCS trait dispatch. The desugaring SHALL be table-driven, mapping method names to (effect name, operation name) pairs.

#### Scenario: Desugaring preserves effect dispatch

- **GIVEN** `list.par_map!(f)` desugars to `Parallel!.map!(list, f)`
- **WHEN** the desugared code is compiled
- **THEN** `Parallel!.map!` SHALL be an effect perform (dispatching through evidence), not a direct function call

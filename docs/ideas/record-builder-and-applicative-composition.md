# Record Builders and Applicative Composition for Camp

**Status**: Idea / brainstorm\
**Date**: 2026-06-07\
**Context**: Exploring how Camp could support ergonomic construction of records from effectful, optional, or validated
field computations — the "applicative functor" pattern.

______________________________________________________________________

## 1. The Problem

Given independent computations that each produce one field of a record — some of which may fail, be effectful, or live
inside a wrapper type — how do you compose them into a single record?

Concrete examples:

- **Validation**: parse_name, parse_age, parse_email each return `Result(Str, Str)`. You want
  `Result({ name: Str, age: I64, email: Str }, List(Str))` — accumulating all errors, not just the first.
- **Optional fields**: lookups in a map each return `Option(T)`. You want `Option({ x: I64, y: I64 })` — `Some` only if
  all fields are present.
- **Parser combinators**: each sub-parser produces one field. You want a parser for the whole record.
- **State composition**: each sub-computation carries independent state. You want a combined state transformer.

In Haskell/Scala/PureScript, this is solved by `Applicative` typeclasses and `<$>/<*>` or `liftA2`. Camp has no
higher-kinded types (HKTs), so those mechanisms don't translate directly. This doc explores two complementary
Camp-native approaches.

______________________________________________________________________

## 2. Cross-Language Survey

### 2.1 PureScript: `sequenceRecord` + `Record.Builder`

PureScript has the most directly relevant mechanism. `sequenceRecord` turns a record of wrapped values into a wrapped
record:

```purescript
sequenceRecord { name: Just "Joe", age: Just 30 }
-- => Just { name: "Joe", age: 30 }

sequenceRecord { name: Just "Joe", age: Nothing }
-- => Nothing
```

This uses `Apply` (applicative) under the hood via row-type reflection (`RowToList`). It's fully generic over any
`Apply` functor.

`Record.Builder` provides composable incremental record construction via a `Category` instance.

**Tradeoffs**: Fully type-safe via row types, but requires heavy type-level machinery (RowList, RowToList constraints).

### 2.2 Scala / Cats: `.mapN` on `Validated`

```scala
case class Form(name: String, age: Int, email: String)

(validateName(input),
 validateAge(input),
 validateEmail(input)).mapN(Form)
// ValidatedNec — accumulates ALL errors, not fail-fast
```

`.mapN` lifts a case class constructor over N validated values. `Validated` is an `Applicative` but explicitly NOT a
`Monad` — this enforces error accumulation vs. fail-fast (`Either`).

**Tradeoffs**: Familiar syntax, error accumulation, but `.mapN` is arity-limited and requires separate types for
fail-fast vs. accumulating.

### 2.3 Haskell: `Constructor <$> f1 <*> f2 <*> f3`

```haskell
env = GameEnvironment <$> player <*> debug
```

Standard applicative builder. No special syntax — just the `<*>` combinator. GHC's `OverloadedRecordDot` (9.2+) helps
with access/update but not construction.

**Tradeoffs**: Concise for small records, but scales poorly (visually noisy for 5+ fields). No built-in accumulation
strategy.

### 2.4 F# / OCaml: Copy-and-Update

```fsharp
let p = { Person.Default with Name = "Alice"; Age = 30 }
```

Start from defaults, override fields. No effectful/applicative construction.

### 2.5 Roc: Record Builder Sugar (`: <-`)

Roc's record builder syntax is the most directly relevant precedent for Camp.

```elm
{ chain_parsers <-
    month: parse_with(Ok),
    day: parse_with(Str.to_u64),
    year: parse_with(Str.to_u64),
}
|> build_segment_parser
```

This desugars to nested `map2` calls:

```elm
chain_parsers(
    parse_with(Ok),
    chain_parsers(
        parse_with(Str.to_u64),
        parse_with(Str.to_u64),
        |day, year| (day, year),
    ),
    |month, (day, year)| { month, day, year },
)
```

The combinator (`chain_parsers`) has type `F(a), F(b), (a, b -> c) -> F(c)` — a `map2`/`liftA2`. The syntax sugar nests
these calls automatically, building up a record.

**Key insight**: This does NOT require HKTs. The combinator is a concrete function for a specific wrapper type. Each
wrapper type (`Result`, `Option`, `Parser`, etc.) provides its own `map2`.

The [Weaver CLI library](https://github.com/smores56/weaver) uses this pattern to build type-safe CLI arg parsers
without macros — each option/param registers itself as a field in the builder.

______________________________________________________________________

## 3. Approach A: `Validate!` Effect (Handler-as-Applicative)

### 3.1 Core Idea

Instead of a new `Applicative` typeclass, use Camp's existing algebraic effects + deep handlers to implement
error-accumulating validation. The **handler IS the applicative strategy** — it controls whether you fail-fast (use
`Throw!`) or accumulate errors (use `Validate!`).

### 3.2 Effect Definition

Following the parameterized effect pattern (like `Throw!(e)`):

```
Validate!(e) : {
  invalid! : |e| -> {},
}
```

- Parameterized by error type `e`
- `invalid!` takes an error value, returns `{}` (unit)
- Unlike `raise!`, `invalid!` is designed to be resumed — it signals a problem but doesn't abort

### 3.3 The `accumulate` Bridge

Analogous to `Result.catch` for `Throw!`:

```
pub accumulate :: |action: || -[Validate!(e)]-> a| -> Result(a, List(e))
pub accumulate = |action| {
  $errors: List(e) = []
  handle Validate! in {
    result = action()
    if List.is_empty($errors) { Ok(result) } else { Err($errors) }
  } with {
    .invalid!(resume, err) => {
      $errors = List.append($errors, err)
      resume({})
    }
  }
}
```

How it works:

1. `$errors` is a mutable list, initialized empty
1. The handler arm for `.invalid!` appends the error and **resumes** — this is the critical difference from `Throw!`
   handlers which typically don't resume
1. When the body finishes (no more effect calls), it reads `$errors` and wraps the result
1. Deep handler semantics guarantee the arm is reinstalled after each `resume`, so every `invalid!` call gets collected
1. The body's final expression sees all accumulated mutations

### 3.4 Example: Form Validation

```
import Validate { [Validate!], accumulate }

@FormData : pub { name: Str, age: I64, email: Str }

validate_form :: |input: Raw| -[Validate!(Str)]-> @FormData
validate_form = |input| {
  name = require_non_empty(input.name, "name is required")
  age = require_positive(input.age, "age must be positive")
  email = require_valid_email(input.email, "invalid email format")
  @FormData({ name: name, age: age, email: email })
}

require_non_empty :: |value: Str, err: Str| -[Validate!(Str)]-> Str
require_non_empty = |value, err| {
  if Str.is_empty(value) { Validate.invalid!(err) }
  value
}

require_positive :: |value: I64, err: Str| -[Validate!(Str)]-> I64
require_positive = |value, err| {
  if value <= 0 { Validate.invalid!(err) }
  value
}
```

Running it:

```
result = accumulate(|| validate_form(bad_input))
// Err(["name is required", "age must be positive", "invalid email format"])
```

### 3.5 The Placeholder Value Subtlety

When `require_non_empty` calls `Validate.invalid!(err)`, it still returns `value` (which is `""`). The record gets
constructed with `name: ""` even though it's invalid. This differs from Haskell's applicative where an invalid field
can't produce a value at all.

This is acceptable because:

- The `Result` wrapping (`Err(errors)`) tells the caller not to trust the record
- The alternative (requiring a "dummy" value of the right type) is the `panic("dummy")` problem
- In practice, the placeholder values are never used — the caller pattern-matches on `Ok`/`Err`

For stronger guarantees, validators can use `Option` fields or early-return via `Throw!`.

### 3.6 Composing with Other Effects

`Validate!` composes naturally via effect rows:

```
create_user :: |input| -[Validate!(Str) | Throw!(DbError) | Console!]-> {}
create_user = |input| {
  form_result = accumulate(|| validate_form(input))
  match form_result {
    Ok(form) => {
      db = Db.insert!(form)     // can Throw!(DbError)
      Console.println!("Created: ${form.name}")
    }
    Err(errors) => {
      for err in errors { Console.println!("  - ${err}") }
    }
  }
}
```

`accumulate` handles `Validate!` locally — it's subtracted from the row. The remaining effects (`Throw!`, `Console!`)
propagate to the caller.

### 3.7 Comparison: `Validate!` vs. Dedicated Syntax

| Aspect              | `Validate!` effect                                | Haskell `Validated` / Scala `.mapN`       |
| ------------------- | ------------------------------------------------- | ----------------------------------------- |
| Strategy at handler | Same code, swap `Throw!` \<-> `Validate!`         | Different types (`Either` vs `Validated`) |
| No new syntax       | Uses existing effect/handler machinery            | Needs `<$>`, `<*>`, `.mapN`, typeclasses  |
| Row composition     | `-[Validate! \| Throw! \| Console!]->` just works | Need monad transformer stacks             |
| Accumulation        | Handler decides — accumulate or fail-fast         | Baked into the type                       |
| Discoverability     | `accumulate` + `catch` are regular functions      | Need to know the typeclass hierarchy      |

The main tradeoff: Camp's approach is **handler-centric** (strategy at call site), while Haskell's is **type-centric**
(strategy in the return type).

### 3.8 Stdlib, Not Prelude

`Validate!` should live in `stdlib/Validate.camp`, not the prelude. Prelude effects get special compiler treatment
(injected without imports, runtime-handled). `Validate!` is application-level logic:

```
import Validate { [Validate!], accumulate }
```

______________________________________________________________________

## 4. Approach B: Record Builder Sugar (The `map2` Pattern)

### 4.1 Motivation

The `Validate!` effect handles error accumulation, but the broader problem — composing wrapped values into a record —
applies to `Result`, `Option`, `List`, parsers, state transformers, and more. A syntax sugar that desugars to `map2`
calls handles ALL of these uniformly, without effects.

This is Roc's record builder pattern, adapted for Camp.

### 4.2 Syntax

```
{ combinator <- field1: expr1, field2: expr2, ..., fieldN: exprN }
```

- `combinator`: identifier or dot-qualified name (e.g., `map2`, `Result.map2`)
- At least 1 field required
- Field punning supported: `{ f <- x, y }` = `{ f <- x: x, y: y }`
- No spread allowed inside a builder (constructing a new record, not updating)

### 4.3 Token

New `.Left_Arrow` token (`<-`). Currently unused in Camp. In the lexer (`src/frontend/lexer.odin:322`), the `<` branch
handles `<=` and `<<`. Add a check for `-`:

```
if ch == '<' {
    l.pos += 1
    if l.source[l.pos] == '-' {
        l.pos += 1
        return .Left_Arrow      // NEW
    }
    if l.source[l.pos] == '=' { return .Lt_Eq }
    if l.source[l.pos] == '<' { return .Lt_Lt }
    return .Lt
}
```

### 4.4 Desugaring Rules

**1 field** — `map1` equivalent (the combinator acts as `fmap`):

```
{ f <- x: e1 }
→ f(e1, |x| { x: x })
```

Combinator type: `|F(a), |a| -> b| -> F(b)`

**2 fields** — direct `map2`:

```
{ f <- x: e1, y: e2 }
→ f(e1, e2, |x, y| { x: x, y: y })
```

Combinator type: `|F(a), F(b), |a, b| -> c| -> F(c)`

**3 fields** — left-nesting with record spread:

```
{ f <- x: e1, y: e2, z: e3 }
→ f(f(e1, e2, |x, y| { x: x, y: y }), e3, |acc, z| { ..acc, z: z })
```

**4 fields** — same pattern:

```
{ f <- a: e1, b: e2, c: e3, d: e4 }
→ f(
    f(f(e1, e2, |a, b| { a: a, b: b }), e3, |acc, c| { ..acc, c: c }),
    e4,
    |acc, d| { ..acc, d: d }
  )
```

**N fields** — recursive rule:

- Innermost: `f(e1, e2, |f1, f2| { f1: f1, f2: f2 })`
- Each subsequent field `fi`: wrap in `f(prev, ei, |acc, fi| { ..acc, fi: fi })`

Evaluation order is left-to-right (Camp is strict, so arguments evaluate before the function is called).

### 4.5 AST Changes

New node in `src/frontend/ast.odin`:

```
Expr_Record_Builder :: struct {
    combinator: Expr,
    fields:     [dynamic]Record_Field,
    span:       base.Source_Span,
}
```

Reuses the existing `Record_Field` struct:

```
Record_Field :: struct {
    name:  base.Intern_ID,
    value: Expr,
    span:  base.Source_Span,
}
```

### 4.6 Parser Changes

In `parser_parse_record_expr` (`src/frontend/parser.odin:1667`), after parsing the first identifier (line 1695-1696),
check if the next token is `.Left_Arrow`:

```
// After parsing name_tok:
if p.current.kind == .Left_Arrow {
    // Switch to builder mode — name_tok is the combinator
    parser_advance(p)
    // Parse remaining fields as field: expr pairs (or punned)
    // Require at least 1 more field
    // Return Expr_Record_Builder
}
// Otherwise, continue with existing record field parsing
```

For dot-qualified combinators (`Result.map2`), after seeing the first identifier + `.`, peek ahead: if it's
`Identifier <-`, parse the dotted name as the combinator. Otherwise fall back to field access.

### 4.7 Desugar Pass

A new pass in canonicalize (`src/semantics/canonicalize.odin`) converts `Expr_Record_Builder` to nested `Expr_Call`:

```
desugar_builder(builder) -> Expr_Call:
    if fields.count == 1:
        // map1: f(expr, |x| { x: x })
        return Call(builder.combinator, [
            field1.value,
            Lambda([field1.name], Record([(field1.name, Identifier(field1.name))]))
        ])

    if fields.count == 2:
        // map2: f(e1, e2, |x, y| { x: x, y: y })
        return Call(builder.combinator, [
            field1.value,
            field2.value,
            Lambda([field1.name, field2.name],
                Record([(f1, Id(f1)), (f2, Id(f2))]))
        ])

    // N > 2: left-nesting
    inner = Call(builder.combinator, [
        field1.value,
        field2.value,
        Lambda([field1.name, field2.name],
            Record([(f1, Id(f1)), (f2, Id(f2))]))
    ])
    for i in 3..N:
        acc = fresh_name("acc")
        inner = Call(builder.combinator, [
            inner,
            field[i].value,
            Lambda([acc, field[i].name],
                Record_Update(acc, [(field[i].name, Id(field[i].name))]))
        ])
    return inner
```

### 4.8 Syntax Disambiguation

The builder syntax `{ combinator <- field: expr, ... }` is unambiguous with all existing `{ }` constructs:

| Construct                     | Token sequence      | Conflict?               |
| ----------------------------- | ------------------- | ----------------------- |
| Record literal `{ x: e }`     | `Identifier : Expr` | No — `:` vs `<-`        |
| Record punning `{ x }`        | `Identifier`        | No — no `<-`            |
| Record update `{ ..r, x: e }` | `.. Expr , ...`     | No — starts with `..`   |
| Block expression `{ stmt }`   | Various             | No — no `Identifier <-` |
| Unit `{}`                     | Empty               | No braces               |
| Record pattern `{ x, y }`     | Pattern context     | No `<-` in patterns     |
| Record type `{ x: Str }`      | Type context        | No `<-` in types        |

The parser sees `{`, parses an identifier, and checks the next token:

- `:` → record field (existing)
- `<-` → record builder (new)
- `,` or `}` → punned field (existing)

One-token lookahead, no ambiguity.

### 4.9 Examples

**Error-accumulating validation** (without effects):

```
map2_result :: |Result(a, e), Result(b, e), |a, b| -> c| -> Result(c, e)
map2_result = |ra, rb, f|
  match [ra, rb] {
    [Ok(a), Ok(b)] => Ok(f(a, b))
    [Err(e1), Err(e2)] => Err(List.concat(e1, e2))
    [Err(e), _] => Err(e)
    [_, Err(e)] => Err(e)
  }

parse_form :: |input: Str| -> Result({ name: Str, age: I64 }, List(Str))
parse_form = |input| {
  { map2_result <- name: parse_name(input), age: parse_age(input) }
}
```

**Optional composition**:

```
map2_option :: |Option(a), Option(b), |a, b| -> c| -> Option(c)

find_point :: |data: Map(Str, I64)| -> Option({ x: I64, y: I64 })
find_point = |data| {
  { map2_option <- x: Map.get(data, "x"), y: Map.get(data, "y") }
}
```

**Parser combinators** (Weaver-style):

```
map2_parser :: |Parser(a), Parser(b), |a, b| -> c| -> Parser(c)

date_parser :: Parser({ month: Str, day: I64, year: I64 })
date_parser = {
  { map2_parser <-
    month: parse_word(),
    day: parse_int(),
    year: parse_int()
  }
}
```

**Explicit state-passing** (no effects needed):

```
map2_state :: ||s| -> (a, s), ||s| -> (b, s), |a, b| -> c| -> ||s| -> (c, s)
map2_state = |sa, sb, f|
  |s0| {
    (a, s1) = sa(s0)
    (b, s2) = sb(s1)
    (f(a, b), s2)
  }

form_state :: ||{ x: I64, y: Str }| -> ({ x: I64, y: Str }, { x: I64, y: Str })
form_state = {
  { map2_state <- x: use_state(0), y: use_state("hello") }
}
```

**Single field** (map1):

```
map_result :: |Result(a, e), |a| -> b| -> Result(b, e)

wrapped_name :: |input: Str| -> Result({ name: Str }, Str)
wrapped_name = |input| {
  { map_result <- name: parse_name(input) }
}
// → map_result(parse_name(input), |name| { name: name })
```

______________________________________________________________________

## 5. The `State!(a)` Composition Question

### 5.1 The Problem

Can effects compose independent stateful "slots" into a record state? E.g.,

```
// Hypothetical:
record_state({ x: use_state!(init_x), y: use_state!(init_y) })
// → State!({ x: TypeX, y: TypeY })
```

### 5.2 Why Effects Don't Support This Directly

Three hard constraints from `docs/effects-spec.md`:

**Constraint 1 — Different effects** (line 60-62):

> `State!(Int)` and `State!(Str)` are different effects — unification SHALL fail

They can't coexist in the same effect row. `-[State!(I64) | State!(Str)]->` is a type error.

**Constraint 2 — Subtraction by name** (line 244):

> For parameterized effects, subtraction removes the effect regardless of its type arguments

`handle State!` catches ALL `State!` variants. You can't nest handlers to catch `State!(I64)` separately from
`State!(Str)`.

**Constraint 3 — No effect-qualified handler arms**:

```
handle E!, F! in body with {
  .op!(resume, args) => ...   // which effect's .op! is this?
}
```

If two effects share an operation name (both have `get!`), the handler can't distinguish them. There's no
`.State!(I64).get!(resume)` syntax.

### 5.3 What DOES Work

**Approach 1: Single record-typed State!**

The pragmatic solution — make the state type a record from the start:

```
State!(s) : {
  get! :: || -[State!(s)]-> s,
  put! :: |s| -[State!(s)]-> {},
}

run_state :: |init: s, action: || -[State!(s)]-> a| -> (a, s)
run_state = |init, action| {
  $state: s = init
  handle State! in {
    result = action()
    (result, $state)
  } with {
    .get!(resume) => resume($state),
    .put!(resume, new_state) => {
      $state = new_state
      resume({})
    }
  }
}

form :: -[State!({ name: Str, age: I64 })]-> {}
form = {
  state = State.get!()
  Console.println!("Name: ${state.name}")
  State.put!({ ..state, name: "Alice", age: 30 })
}

result = run_state({ name: "", age: 0 }, form)
```

No composition needed — the state IS the record.

**Approach 2: Record builder with explicit state-passing**

Use the `map2` record builder (Section 4) with explicit state transformer functions:

```
map2_state :: ||s| -> (a, s), ||s| -> (b, s), |a, b| -> c| -> ||s| -> (c, s)

composed :: ||{ x: I64, y: Str }| -> ({ x: I64, y: Str }, { x: I64, y: Str })
composed = {
  { map2_state <- x: use_state(0), y: use_state("hello") }
}
```

This works without effects at all — state is threaded explicitly through the `map2_state` combinator.

### 5.4 Design Implications

Camp's effects and the record builder pattern are **complementary but orthogonal**:

- **Effects** handle side effects (IO, state, errors) via handlers — they're about **control flow**
- **Record builders** compose wrapped values via `map2` — they're about **data construction**

For `State!` specifically, the single-record-typed approach (Approach 1) is the pragmatic Camp solution. For general
applicative composition, the record builder (Approach 2) covers the broader set of use cases.

______________________________________________________________________

## 6. How the Two Approaches Relate

| Use case                      | Best approach                    | Why                                                               |
| ----------------------------- | -------------------------------- | ----------------------------------------------------------------- |
| Error-accumulating validation | `Validate!` effect               | Natural fit — effects for side effects, handler controls strategy |
| Error-accumulating validation | `map2_result` + builder          | Alternative — no effects needed, purely functional                |
| Optional field composition    | `map2_option` + builder          | `Option` isn't an effect, builder is the natural fit              |
| Parser combinators            | `map2_parser` + builder          | Same pattern as Weaver, purely functional                         |
| State composition             | Single `State!` with record type | Pragmatic — effects handle state naturally                        |
| State composition             | `map2_state` + builder           | Alternative — explicit state-passing, no effects                  |

Both approaches can coexist. The `Validate!` effect is ergonomically superior for validation use cases (the handler
decides the strategy, business logic doesn't change). The record builder is more general — it works with any type that
has a `map2`.

A user doing form validation might use `Validate!`:

```
// Handler decides strategy — same business logic for accumulate or fail-fast
form = accumulate(|| validate_form(input))
```

While a user composing optional lookups would use the record builder:

```
// No effects involved — just Option + map2
point = { map2_option <- x: Map.get(data, "x"), y: Map.get(data, "y") }
```

______________________________________________________________________

## 7. Implementation Checklist

### 7.1 Record Builder Sugar

- [ ] Add `.Left_Arrow` token kind to `src/base/token.odin`
- [ ] Add `<-` lexing in `src/frontend/lexer.odin` (in the `<` branch)
- [ ] Add `Expr_Record_Builder` AST node in `src/frontend/ast.odin`
- [ ] Modify `parser_parse_record_expr` in `src/frontend/parser.odin` to detect `<-`
- [ ] Add builder desugaring in `src/semantics/canonicalize.odin`
- [ ] Add language spec section for record builders
- [ ] Add language spec section for record builders
- [ ] Add e2e tests: 1, 2, 3, 4+ field builders
- [ ] Add e2e tests: punning, dot-qualified combinator, error cases
- [ ] Add e2e tests: `map2_result` validation example
- [ ] Update kitchen-sink test

### 7.2 `Validate!` Effect

- [ ] Create `stdlib/Validate.camp` with effect definition
- [ ] Implement `accumulate` bridge function
- [ ] Add stdlib tests for `Validate!`
- [ ] Add language spec reference
- [ ] Add e2e tests: accumulation, composition with other effects
- [ ] Update kitchen-sink test

______________________________________________________________________

## 8. Open Questions

1. **Combinator scope**: Should the combinator be restricted to identifiers / dot-qualified names, or allow arbitrary
   expressions? Restricting keeps parsing simple; allowing is more general.

1. **`map2` convention**: Should Camp establish a naming convention for `map2` functions? E.g., `TypeName.map2` —
   `Result.map2`, `Option.map2`, `Parser.map2`.

1. **Accumulation strategy for `map2_result`**: The example uses `List.concat(e1, e2)` to merge errors. Should this be
   configurable (via a `Semigroup`-like trait)? Or should `map2_result` just keep the first error?

1. **Error recovery in `Validate!`**: After `invalid!` is called and the handler resumes, the body continues with a
   placeholder value. Should there be a way to short-circuit the body (abort remaining field computations) while still
   collecting errors? This would require a more complex handler that tracks a "poisoned" flag.

1. **Record builder + open records**: Should `{ f <- x: e1, y: e2, .. }` (open record result) be supported? This would
   let builders compose partial records.

1. **Effect-qualified handler arms**: If Camp ever added syntax like
   `handle State!(I64), State!(Str) in body with { State!(I64).get!(resume) => ... }`, the state composition approach
   would change significantly. This is a broader design question about whether parameterized effects should be
   independently handleable.

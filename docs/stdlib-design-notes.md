# Camp Standard Library — Design Notes

> Working document capturing all design decisions, open questions, and proposed APIs from the stdlib design grilling
> session. This is NOT a spec — it's the research and reasoning that will inform spec updates.

______________________________________________________________________

## 1. Decisions Made

### D1: Drop `Option`, keep `Result` + `Throw!`

Three error/absence mechanisms (Option + Result + Throw!) is too many. Two is right.

- **Can't drop Throw!** — effects are core to Camp's identity
- **Can't drop Result** — data vs control flow distinction: Result is storable, pure, local; Throw! is propagating,
  effectful
- **So Option goes** — eliminates Option↔Result impedance mismatch, one set of combinators, specific error tags replace
  None's ambiguity

Non-failure optionality uses domain-specific tag unions: `[Loading, Loaded(Artist)]` instead of `Option(Artist)`.

Camp differs from Roc (no error type inference, no optional record fields), but tag unions make
`Result(a, [SpecificTag])` ergonomic.

### D2: `Iter.next` uses `[Yield(a) | Done]` (tentative)

Iteration being "done" isn't an error — Result framing is semantically wrong. Domain-specific tag unions beat generic
wrappers for non-failure optionality. May revisit if pattern matching ergonomics are bad.

### D3: Error tags — specific per operation (Pattern A)

`Dict.get` returns `Result(v, [KeyNotFound])`, `List.first` returns `Result(a, [ListWasEmpty])`. Tags are naturally
module-qualified via Camp's module system. No collision risk, composes with effect rows.

### D4: Throw! vs Result boundary

- **Result** for locally-handled, pure, data-level errors
- **Throw!** for propagated, effectful, action-level errors
- Bridge functions: `Result.catch` (Throw!→Result) and `Result.unwrap!` (Result→Throw!)

### D5: Naming convention for effect/result variants

- `foo!` — Throw! version (propagates errors as effects)
- `try_foo` — Result version (returns errors as values)

### D6: Result API (final)

```
@Result : (a, e) [Ok(a) | Err(e)]

-- Core combinators
map        : (Result(a, e), (a) -> b) -> Result(b, e)
map_err    : (Result(a, e), (e) -> f) -> Result(a, f)
and_then   : (Result(a, e), (a) -> Result(b, e)) -> Result(b, e)
or_else    : (Result(a, e), (e) -> Result(a, f)) -> Result(a, f)

-- Predicates
is_ok      : Result(a, e) -> Bool
is_err     : Result(a, e) -> Bool

-- Unwrapping
unwrap           : Result(a, e) -> a                          -- crashes on Err
unwrap_or        : Result(a, e), a -> a
unwrap_or_else   : Result(a, e), (e) -> a -> a
unwrap_or_default : Result(a, e) -> a                         -- requires Default
unwrap!          : Result(a, e) -> -[Throw!(e)]-> a           -- throws Err

-- Effect bridging
catch      : (|| -[Throw!(e)]-> a) -> Result(a, e)

-- Boolean
or         : Result(a, e), Result(a, e) -> Result(a, e)

-- Filtering
filter     : Result(a, e), (a) -> Bool, e -> Result(a, e)

-- Flattening
flatten    : Result(Result(a, e), e) -> Result(a, e)

-- Conversion
to_list    : Result(a, e) -> List(a)
from_list  : List(a) -> Result(a, [EmptyList])
```

Prelude includes `Ok`, `Err` via `import Result { [Ok, Err] }`.

### D7: Collections — types and ordering

- **List** — immutable linked list (Priority 1)
- **Map** — ordered tree map (Priority 1) — MUST be ordered for referential transparency (hash maps have
  non-deterministic iteration order)
- **Set** — ordered tree set (Priority 1)
- **Iter** — lazy iterator (Priority 1)
- **Bytes** — contiguous byte buffer (Priority 1)
- **Str** — UTF-8 string (Priority 1)
- **Array** — deferred to future design task (needs const generics, mutability semantics)
- **StringBuilder** — deferred to future consideration

### D8: List API — lean, Iter does the rest

"One way to do things" principle. List is for construction, structural access, and conversion. Iter is for all
transformation.

```
-- Construction
empty       : List(a)
singleton   : a -> List(a)
append      : List(a), List(a) -> List(a)

-- Structural queries
length      : List(a) -> I64
is_empty    : List(a) -> Bool

-- Head/tail access
first       : List(a) -> Result(a, [ListWasEmpty])
last        : List(a) -> Result(a, [ListWasEmpty])
rest        : List(a) -> Result(List(a), [ListWasEmpty])

-- Sorting (needs full collection)
sort        : List(a) -> List(a)                           -- requires Ord
sort_by     : List(a), (a, a) -> Order -> List(a)

-- Conversion (gateway to Iter)
to_iter     : List(a) -> Iter(a)       -- via IntoIter trait
from_iter   : Iter(a) -> List(a)       -- via FromIter trait
```

### D9: Traits — final inventory

**Derivable:** `Eq`, `Ord`, `Hash`, `Debug`, `Default` **Not derivable:** `Display` **Collection:** `IntoIter(a)`,
`FromIter(c, a)` **Codec:** `Encode(a, f)`, `Decode(a, f)` **Conversion:** `From(source, target)`,
`TryFrom(source, target, e)`

**Eliminated:** `Clone`, `Copy` — Camp is auto-memory-managed (Perceus RC) and immutable. Values are always shared by
reference; "cloning" is meaningless.

```
Eq(a) : {
  eq : (a, a) -> Bool
}

Ord(a) : is Eq(a) {
  compare : (a, a) -> Order
}

@Order : [Less | Equal | Greater]

Hash(a) : {
  hash : (a, Hasher) -> Hasher
}

Debug(a) : {
  debug : a -> Str
}

Display(a) : {
  to_str : a -> Str
}

Default(a) : {
  default : a
}

IntoIter(a) : {
  to_iter : Self(a) -> Iter(a)
}

FromIter(c, a) : {
  from_iter : Iter(a) -> c
}

From(source, target) : {
  from : source -> target
}

TryFrom(source, target, e) : {
  try_from : source -> Result(target, e)
}
```

### D10: Numeric types — comprehensive

I8, I16, I32, I64, U8, U16, U32, U64, F32, F64 (10 types total).

### D11: Numeric literal inference — pragmatic

Default I64/F64 for unannotated literals, context unification resolves when type is known. Evolve toward Roc-style
polymorphic literals later.

### D12: String types — Str + Bytes

- `Str` = validated UTF-8, flat buffer, immutable
- `Bytes` = raw bytes, no encoding guarantee
- `StringBuilder` deferred

### D13: Map/Set API decisions

- `Map.update` — yes, included in v1
- `Map.keys` / `Map.values` — return `Iter`, not `List`
- Set operations (`union`, `intersection`, `difference`, `symmetric_difference`, `is_subset`, `is_disjoint`) — on Set
  directly, not through Iter

### D14: Effect module naming convention

- `foo!` for Throw! version, `try_foo` for Result version
- `File.exists!` — effectful but can't fail, no `try_` variant needed

### D15: Log! is message-only

`Log.debug!/info!/warn!/error! : Str -> -[Log!]-> ()`. Structured logging is a package concern.

### D16: Order is structural

`[Less | Equal | Greater]`, not nominal. No prelude slot. Convenience functions as free functions in Ord module if
needed.

### D17: Prelude finalized

8 auto-imported modules: `List`, `Map`, `Set`, `Iter`, `Bytes`, `Result`, `Str`, `Bool`. All 10 numeric types: `I8`,
`I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`. Constructors: `Ok`, `Err`, `True`, `False`. 10 traits:
`Eq`, `Ord`, `Hash`, `Debug`, `Display`, `Default`, `IntoIter`, `FromIter`, `From`, `TryFrom`. Effects: `Throw!`,
`Console!`. Language operators.

### D18: Str API

`Str.length` counts graphemes, `Str.slice` is grapheme-safe, `to_lower`/`to_upper` are Unicode,
`split_first`/`split_last` return `Result((Str, Str), [NotFound])`.

### D19: Bytes API

Lean module (construction, queries, access, slicing, concat). Conversions via traits: `From(Str, Bytes)` infallible,
`TryFrom(Bytes, Str, [InvalidUtf8])` fallible, `List(U8) ↔ Bytes` via IntoIter/FromIter pipeline. Encoding modules
(Base64, Hex, etc.) stay separate.

### D20: Map API details

`Map.update` callback uses `Result(v, [KeyNotFound]) -> Result(v, [KeyNotFound])` (same tag as Map.get). `Map.union` is
left-biased for v1. `Map.min`/`Map.max` included (O(log n) on ordered tree), return `Result((k, v), [EmptyMap])`.

### D21: Set API details

`Set.min`/`Set.max` included, return `Result(a, [EmptySet])`. `Set.map` requires `Ord` on output type. Set is
implemented as `Map(a, ())` internally.

### D22: Iter carries effect row

`Iter(a, e)` with effect row parameter. No standalone `collect` — use `FromIter.from_iter` via UFCS. No `Iter.sorted` —
compose through List.

### D23: Effect module API details

`FileErr` keeps `IoErr` as catch-all for v1 (can add specific tags later). Only `foo!` variants for effect modules — use
`Result.catch` for Result. `Env.try_get : Str -> -[Env!]-> Result(Str, [VarNotFound])` returns Result, not Throw!.

### D24: Duration and DateTime

Duration is Rust-style two-field struct `{ secs: I64, nanos: I64 }` (signed, ~584B yr range). DateTime is a **separate
package** (not stdlib), designed following jiff crate philosophy (civil types, Zoned as primary, IANA tzdb, Span for
calendar arithmetic, DST-safe).

### D25: Path is opaque type

`Path` is opaque, normalized on construction. `Path.new : Str -> Path`.

### D26: Encode/Decode codec (tentative)

Encode is format-agnostic (produces intermediate `Encoding` tree). Decode is format-specific (separate traits per
format). `derives Encode, Decode` generates impls. Rich `DecodeError` with path tracking. **Tentative** — revisit when
trait system matures (no method generics means Roc-style fully format-agnostic isn't possible).

### D27: Num module with submodules

`Num` is the namespace, each numeric type is a submodule: `Num.I64.abs`, `Num.I32.max`, `Num.F64.sqrt`, etc. No
standalone `Int` module.

### D28: Fmt module

`Fmt` houses `Display`/`Debug` traits. Format specifiers (padding, alignment) go in interpolation syntax as a language
feature (e.g., `"{x:>10}"`).

### D29: Hasher is opaque

`Hasher` is opaque (SipHash-1-3 internally). `Hash(a)` stays single-parameter. Custom hashing is a package concern.

### D30: Flat module organization

Flat modules except `Num` and `Crypto`. `Json.encode`/`Json.decode` are functions in the `Json` module. Encoding modules
stay separate. **Future decision point:** consider Zig-style nested type/module naming where `Foo.Bar` can be either a
submodule or a type within the namespace.

### D31: Unboxed enum representation (camp-9xi6)

Closed tag unions whose every variant has no payload (e.g. `[Less | Equal | Greater]`, `@Color : [Red | Green | Blue]`)
are represented as **immediate i32 variant ordinals** rather than heap-allocated cells. This eliminates per-value
allocation and reference-counting overhead for these types.

**Rule:** A tag union is immediate (`is_heap = false`) when ALL of the following hold:

1. The row is **closed** (syntactic `[A | B | ...]` or prelude-synthesized)
1. Every variant has an **empty payload**
1. All sub-rows (if the row was unified with another row) also satisfy (1) and (2)

Open rows (bare tags before unification, list literals, match patterns, generic instantiation) and any union with at
least one payloaded variant remain **boxed** (heap-allocated cells with tag byte + payload).

**Ordinals:** Variant ordinals are derived from declaration order (0-indexed). `Bool` remains special-cased (`True` = 1,
`False` = 0) via `IR_Literal_Bool`/`IR_Pat_Bool`/`Match_Kind.Bool`; closed no-payload tag unions use a parallel codegen
path (`IR_Construct_Tag` with `is_heap=false` emitting `i32.const <ordinal>`, match dispatch reading the immediate
directly).

______________________________________________________________________

## 2. Open Questions (All Resolved)

### Q1: Log! structured data — **RESOLVED → D15**

Message-only: `Log.debug!/info!/warn!/error! : Str -> -[Log!]-> ()`. Structured logging is a package concern.

### Q2: Prelude design — **RESOLVED → D17**

8 auto-imported modules (List, Map, Set, Iter, Bytes, Result, Str, Bool), all 10 numeric types, Ok/Err/True/False
constructors, 10 traits, Throw! + Console! effects, language operators.

### Q3: Str API — **RESOLVED → D18**

`Str.length` counts graphemes, `Str.slice` is grapheme-safe, `to_lower`/`to_upper` are Unicode,
`split_first`/`split_last` return `Result((Str, Str), [NotFound])`.

### Q4: Bytes API — **RESOLVED → D19**

Lean module. Conversions via traits (From/TryFrom/IntoIter/FromIter). Encoding modules stay separate.

### Q5: Map API — **RESOLVED → D20**

`Map.update` uses `Result(v, [KeyNotFound])` callback. `Map.union` is left-biased. `Map.min`/`Map.max` included.

```
-- Construction
Map.new : Map(k, v)
Map.singleton : k, v -> Map(k, v)
Map.from_list : List((k, v)) -> Map(k, v)     -- via FromIter

-- Lookup
Map.get : k, Map(k, v) -> Result(v, [KeyNotFound])
Map.contains : k, Map(k, v) -> Bool            -- requires Eq
Map.size : Map(k, v) -> I64

-- Modification (return new Map)
Map.insert : k, v, Map(k, v) -> Map(k, v)
Map.remove : k, Map(k, v) -> Map(k, v)
Map.update : k, (Result(v, [KeyNotFound]) -> Result(v, [UpdateRemoved])) -> Map(k, v)

-- Transformation
Map.map : Map(k, v), (v) -> w -> Map(k, w)
Map.filter : Map(k, v), (k, v) -> Bool -> Map(k, v)
Map.fold : Map(k, v), b, (b, k, v) -> b -> b

-- Conversion
Map.to_iter : Map(k, v) -> Iter((k, v))        -- via IntoIter
Map.keys : Map(k, v) -> Iter(k)
Map.values : Map(k, v) -> Iter(v)

-- Set-like operations (ordered maps can do these efficiently)
Map.union : Map(k, v), Map(k, v) -> Map(k, v)          -- left-biased on conflict
Map.intersection : Map(k, v), Map(k, v) -> Map(k, v)
Map.difference : Map(k, v), Map(k, v) -> Map(k, v)
```

**RESOLVED:** Map.update uses `Result(v, [KeyNotFound]) -> Result(v, [KeyNotFound])` (same tag as Map.get). Map.union is
left-biased for v1. Map.min/max included.

### Q6: Set API — **RESOLVED → D21**

Set.min/max included, Set.map requires Ord on output. Set is `Map(a, ())` internally.

```
-- Construction
Set.new : Set(a)
Set.singleton : a -> Set(a)
Set.from_list : List(a) -> Set(a)              -- via FromIter

-- Queries
Set.contains : a, Set(a) -> Bool                -- requires Eq
Set.size : Set(a) -> I64
Set.is_empty : Set(a) -> Bool

-- Modification
Set.insert : a, Set(a) -> Set(a)
Set.remove : a, Set(a) -> Set(a)

-- Set operations
Set.union : Set(a), Set(a) -> Set(a)
Set.intersection : Set(a), Set(a) -> Set(a)
Set.difference : Set(a), Set(a) -> Set(a)
Set.symmetric_difference : Set(a), Set(a) -> Set(a)
Set.is_subset : Set(a), Set(a) -> Bool
Set.is_disjoint : Set(a), Set(a) -> Bool

-- Transformation
Set.map : Set(a), (a) -> b -> Set(b)
Set.filter : Set(a), (a) -> Bool -> Set(a)
Set.fold : Set(a), b, (b, a) -> b -> b

-- Conversion
Set.to_iter : Set(a) -> Iter(a)                -- via IntoIter
```

### Q7: Iter API — **RESOLVED → D22**

`Iter(a, e)` with effect row. No standalone collect (use FromIter). No Iter.sorted.

```
@Iter : (a, e) @{
  next: || -[e]-> [Yield(a) | Done]
}

-- Construction
empty       : Iter(a, e)
singleton   : a -> Iter(a, e)
from_list   : List(a) -> Iter(a, e)       -- via IntoIter trait, but explicit

-- Core transformations
map         : Iter(a, e), (a) -> b -> Iter(b, e)
filter      : Iter(a, e), (a) -> Bool -> Iter(a, e)
flat_map    : Iter(a, e), (a) -> Iter(b, e) -> Iter(b, e)
filter_map  : Iter(a, e), (a) -> Result(b, err) -> Iter(b, e)  -- drop Errs

-- Consumption
fold        : Iter(a, e), b, (b, a) -> b -> b
for_each    : Iter(a, e), (a) -> () -> ()
count       : Iter(a, e) -> I64

-- Search
find        : Iter(a, e), (a) -> Bool -> Result(a, [NotFound])
any         : Iter(a, e), (a) -> Bool -> Bool
all         : Iter(a, e), (a) -> Bool -> Bool
contains    : Iter(a, e), a -> Bool   -- requires Eq

-- Slicing
take        : Iter(a, e), I64 -> Iter(a, e)
skip        : Iter(a, e), I64 -> Iter(a, e)
take_while  : Iter(a, e), (a) -> Bool -> Iter(a, e)
skip_while  : Iter(a, e), (a) -> Bool -> Iter(a, e)

-- Composition
chain       : Iter(a, e), Iter(a, e) -> Iter(a, e)
zip         : Iter(a, e), Iter(b, e) -> Iter((a, b), e)
enumerate   : Iter(a, e) -> Iter((I64, a), e)

-- Collection
collect     : Iter(a, e) -> c          -- via FromIter trait

-- Sorting (collects into memory)
sorted_via_list : Iter(a, e) -> Iter(a, e)   -- requires Ord
```

**Effect tracking:** `Iter` is parameterized over both `a` (element type) and `e` (effect row). Effect rows merge via
row unification when closures have different effects than the iterator's `next`.

### Q8: Effect module APIs — **RESOLVED → D23**

Only `foo!` variants (use `Result.catch` for Result). `FileErr` keeps `IoErr` catch-all. `Env.try_get` returns Result.
API details preserved below for reference.

#### Console!

```
Console.println! : Str -> -[Console!]-> ()
Console.print!   : Str -> -[Console!]-> ()
Console.readline! : -[Console!]-> Str
```

#### File!

```
File.read_all!  : Path -> -[File!, Throw!([FileErr])]-> Str
File.write_all! : Path, Str -> -[File!, Throw!([FileErr])]-> ()
File.append_all! : Path, Str -> -[File!, Throw!([FileErr])]-> ()
File.read_bytes! : Path -> -[File!, Throw!([FileErr])]-> Bytes
File.write_bytes! : Path, Bytes -> -[File!, Throw!([FileErr])]-> ()
File.list_dir!  : Path -> -[File!, Throw!([FileErr])]-> List(Path)
File.create_dir! : Path -> -[File!, Throw!([FileErr])]-> ()
File.remove!    : Path -> -[File!, Throw!([FileErr])]-> ()
File.copy!      : Path, Path -> -[File!, Throw!([FileErr])]-> ()
File.exists!    : Path -> -[File!]-> Bool
File.is_dir!    : Path -> -[File!]-> Bool
File.is_file!   : Path -> -[File!]-> Bool

@FileErr : [NotFound | PermissionDenied | AlreadyExists | InvalidUtf8 | IoErr]
```

#### Env!

```
Env.get!       : Str -> -[Env!, Throw!([VarNotFound])]-> Str
Env.try_get    : Str -> -[Env!]-> Result(Str, [VarNotFound])
Env.vars!      : -[Env!]-> List((Str, Str))
Env.args!      : -[Env!]-> List(Str)
```

#### Time!

```
Time.now!        : -[Time!]-> Duration    -- Duration only; DateTime is a package
Time.monotonic!  : -[Time!]-> Duration
```

#### Random!

```
Random.int!   : I64, I64 -> -[Random!]-> I64
Random.float! : F64, F64 -> -[Random!]-> F64
Random.bytes! : I64 -> -[Random!]-> Bytes
Random.bool!  : -[Random!]-> Bool
```

#### Crypto.Random!

```
Crypto.Random.int!   : I64, I64 -> -[Crypto.Random!]-> I64
Crypto.Random.bytes! : I64 -> -[Crypto.Random!]-> Bytes
Crypto.Random.uuid!  : -[Crypto.Random!]-> Uuid
```

#### Log!

```
Log.debug! : Str -> -[Log!]-> ()
Log.info!  : Str -> -[Log!]-> ()
Log.warn!  : Str -> -[Log!]-> ()
Log.error! : Str -> -[Log!]-> ()
```

### Q9: Duration and DateTime — **RESOLVED → D24**

Duration is Rust-style two-field struct `{ secs: I64, nanos: I64 }` (signed). DateTime is a **separate package** (not
stdlib), designed following jiff crate philosophy. Duration API preserved below for reference.

```
@Duration : -- opaque, internally { secs: I64, nanos: I64 }

-- Constructors
Duration.from_seconds : F64 -> Duration
Duration.from_millis  : I64 -> Duration
Duration.from_micros  : I64 -> Duration
Duration.from_nanos   : I64 -> Duration

-- Accessors
Duration.as_seconds   : Duration -> F64
Duration.as_millis    : Duration -> I64
Duration.as_micros    : Duration -> I64
Duration.as_nanos     : Duration -> I64

-- Arithmetic
Duration.add  : Duration, Duration -> Duration
Duration.sub  : Duration, Duration -> Duration
Duration.mul  : Duration, I64 -> Duration
Duration.neg  : Duration -> Duration
Duration.abs  : Duration -> Duration

-- Comparison (via Ord)
Duration.is_zero : Duration -> Bool

-- Constants
Duration.zero, Duration.second, Duration.millisecond, Duration.microsecond, Duration.nanosecond
```

### Q10: Path module — **RESOLVED → D25**

Opaque `Path` type, normalized on construction. API preserved below for reference.

```
@Path : -- opaque type, normalized

-- Construction
Path.new    : Str -> Path
Path.join   : Path, Path -> Path
Path.from_list : List(Str) -> Path

-- Decomposition
Path.parent    : Path -> Result(Path, [HasNoParent])
Path.filename  : Path -> Str
Path.stem      : Path -> Str
Path.extension : Path -> Str

-- Manipulation
Path.with_extension : Path, Str -> Path
Path.with_filename  : Path, Str -> Path
Path.with_parent    : Path, Path -> Path

-- Queries
Path.is_absolute : Path -> Bool
Path.is_relative : Path -> Bool

-- Conversion
Path.to_str   : Path -> Str
Path.to_iter  : Path -> Iter(Str)   -- iterate over components
```

**RESOLVED:** Opaque Path type. Auto-normalized on construction. No I/O on Path — that's in File!.

### Q11: Encode/Decode codec — **RESOLVED → D26**

Encode is format-agnostic (produces intermediate `Encoding` tree). Decode is format-specific. `derives Encode, Decode`
generates impls. Rich `DecodeError` with path tracking. **Tentative** — revisit when trait system matures.

```
-- Format-agnostic encoding trait
Encode(a, f) : {
  encode : (a, Encoder(f)) -> Encoder(f)
}

-- Format-agnostic decoding trait
Decode(a, f) : {
  decode : (Decoder(f)) -> Result(a, [DecodeError])
}

-- Format backend traits
EncoderFormatting(f) : {
  u8    : U8 -> Encoder(f)
  i64   : I64 -> Encoder(f)
  f64   : F64 -> Encoder(f)
  bool  : Bool -> Encoder(f)
  string : Str -> Encoder(f)
  list  : List(elem), (elem -> Encoder(f)) -> Encoder(f)
  record : List({ key: Str, value: Encoder(f) }) -> Encoder(f)
  tag   : Str, List(Encoder(f)) -> Encoder(f)
}

DecoderFormatting(f) : {
  u8    : Decoder(f) -> Result(U8, [DecodeError])
  i64   : Decoder(f) -> Result(I64, [DecodeError])
  f64   : Decoder(f) -> Result(F64, [DecodeError])
  bool  : Decoder(f) -> Result(Bool, [DecodeError])
  string : Decoder(f) -> Result(Str, [DecodeError])
  list  : Decoder(f), Decoder(elem) -> Result(List(elem), [DecodeError])
  record : Decoder(f), List({ key: Str, decoder: Decoder(field) }) -> Result(record, [DecodeError])
}

-- Decode error type
@DecodeError : [TooShort | Leftover(Bytes) | InvalidFormat(Str) | MissingField(Str) | TypeMismatch(Str, Str)]
```

**Decoder combinators:**

```
Decode.map      : Decoder(a, f), (a -> b) -> Decoder(b, f)
Decode.then     : Decoder(a, f), (a -> Decoder(b, f)) -> Decoder(b, f)
Decode.one_of   : List(Decoder(a, f)) -> Decoder(a, f)
Decode.field    : Str, Decoder(a, f) -> Decoder(a, f)
Decode.optional : Decoder(a, f) -> Decoder(Result(a, [FieldAbsent]), f)
Decode.list     : Decoder(a, f) -> Decoder(List(a), f)
Decode.custom   : (Decoder(f)) -> Result(a, [DecodeError]) -> Decoder(a, f)
```

**RESOLVED:** Encode format-agnostic (intermediate tree), Decode format-specific. Tentative — no method generics means
Roc-style fully format-agnostic isn't possible.

### Q12: Num module — **RESOLVED → D27**

`Num` namespace with per-type submodules: `Num.I64.abs`, `Num.F64.sqrt`, etc.

### Q13: Fmt module — **RESOLVED → D28**

`Fmt` houses `Display`/`Debug` traits. Format specifiers (padding, alignment) go in interpolation syntax as a language
feature.

### Q14: Hasher type — **RESOLVED → D29**

Opaque `Hasher` (SipHash-1-3). `Hash(a)` stays single-parameter.

### Q15: Module organization — **RESOLVED → D30**

Flat modules except `Num` and `Crypto`. Future decision point: consider Zig-style nested type/module naming.

______________________________________________________________________

## 3. Complete Module Listing (Proposed)

### Priority 1 — Required for any non-trivial program

| Module     | Type                   | Description                                 |
| ---------- | ---------------------- | ------------------------------------------- |
| `Result`   | Type + functions       | Error/absence handling (replaces Option)    |
| `Bool`     | Type + functions       | Boolean operations                          |
| `Num`      | Namespace + submodules | Numeric operations (Num.I64, Num.F64, etc.) |
| `Str`      | Type + functions       | UTF-8 string operations                     |
| `List`     | Type + functions       | Immutable linked list                       |
| `Iter`     | Type + functions       | Lazy iterator                               |
| `Map`      | Type + functions       | Ordered tree map                            |
| `Set`      | Type + functions       | Ordered tree set                            |
| `Bytes`    | Type + functions       | Raw byte buffer                             |
| `Eq`       | Trait                  | Equality                                    |
| `Ord`      | Trait                  | Ordering (with `Order` type)                |
| `Hash`     | Trait                  | Hashing (with `Hasher` type)                |
| `Debug`    | Trait                  | Debug formatting                            |
| `Display`  | Trait                  | Display formatting                          |
| `Default`  | Trait                  | Default values                              |
| `IntoIter` | Trait                  | Convert to iterator                         |
| `FromIter` | Trait                  | Convert from iterator                       |
| `From`     | Trait                  | Infallible conversion                       |
| `TryFrom`  | Trait                  | Fallible conversion                         |
| `Encode`   | Trait                  | Format-agnostic encoding                    |
| `Decode`   | Trait                  | Format-agnostic decoding                    |
| `Fmt`      | Functions              | Formatting utilities                        |
| `Path`     | Type + functions       | Filesystem path                             |
| `Duration` | Type + functions       | Time duration (Rust-style signed struct)    |
| `Console!` | Effect                 | Standard I/O                                |
| `Throw!`   | Effect                 | Error propagation                           |
| `File!`    | Effect                 | Filesystem access                           |
| `Env!`     | Effect                 | Environment variables                       |
| `Time!`    | Effect                 | Time access                                 |
| `Random!`  | Effect                 | Fast PRNG                                   |
| `Log!`     | Effect                 | Logging                                     |

### Priority 2 — Required for most REST APIs

| Module           | Type             | Description                  |
| ---------------- | ---------------- | ---------------------------- |
| `Json`           | Type + functions | JSON parsing/stringify/Value |
| `Regex`          | Type + functions | Regular expressions          |
| `Uri`            | Type + functions | URI/URL parsing              |
| `Crypto.Random!` | Effect           | Cryptographic random         |
| `Uuid`           | Type + functions | UUID v4/v7                   |
| `Base64`         | Functions        | Base64 encode/decode         |
| `Base64URL`      | Functions        | URL-safe Base64              |
| `Base32`         | Functions        | Base32 encode/decode         |
| `Hex`            | Functions        | Hex encode/decode            |

### Priority 3 — Important for completeness

| Module              | Type      | Description                 |
| ------------------- | --------- | --------------------------- |
| `Gzip`              | Functions | Compression/decompression   |
| `EncoderFormatting` | Trait     | Format backend for encoding |
| `DecoderFormatting` | Trait     | Format backend for decoding |

### Numeric type modules (Priority 1)

| Module                    | Description                           |
| ------------------------- | ------------------------------------- |
| `I8`, `I16`, `I32`, `I64` | Signed integer types and operations   |
| `U8`, `U16`, `U32`, `U64` | Unsigned integer types and operations |
| `F32`, `F64`              | Floating-point types and operations   |

### Official Packages (NOT stdlib)

| Package             | Description                                             |
| ------------------- | ------------------------------------------------------- |
| `Http`              | Server!/Client! effects                                 |
| `Database`          | query!/execute!/transaction!                            |
| `Database.Postgres` | PostgreSQL driver                                       |
| `Database.Sqlite`   | SQLite driver                                           |
| `Database.MySql`    | MySQL driver                                            |
| `Database.Redis`    | Redis driver                                            |
| `Crypto.Hash`       | sha256, sha512, blake2b, etc.                           |
| `DateTime`          | Civil types, Zoned, Span, IANA tzdb (jiff-style design) |

### Deferred (future design tasks)

| Module          | Description                    | Why deferred                 |
| --------------- | ------------------------------ | ---------------------------- |
| `Array`         | Fixed-length, O(1) index       | Needs const generics design  |
| `StringBuilder` | Efficient string concatenation | Needs rope/buffer design     |
| `Queue`         | FIFO data structure            | Can use List with discipline |
| `Stack`         | LIFO data structure            | Can use List with discipline |

______________________________________________________________________

## 4. Key Research Findings (Condensed)

### Error handling across languages

| Language | Option/Maybe           | Result/Either  | Effects/Exceptions | Bridge functions                |
| -------- | ---------------------- | -------------- | ------------------ | ------------------------------- |
| Roc      | ❌ None                | ✅ Result only | ❌ (Task = type)   | `?` operator                    |
| Gleam    | ✅ (but idiom: Result) | ✅             | ❌                 | `try` syntax                    |
| Rust     | ✅                     | ✅             | ❌                 | `?` operator + From trait       |
| Koka     | ✅ maybe               | ✅ either      | ✅ exn effect      | error/try, untry, maybe, either |
| Haskell  | ✅ Maybe               | ✅ Either      | ✅ IO exceptions   | try, catch, evaluate            |
| Swift    | ✅ Optional            | ✅ Result      | ✅ throwing        | try/catch                       |

### Collection API patterns

- **Roc/Gleam:** Rich List API (60+ functions), no lazy iterators, use `walk`/`fold`
- **Rust:** Minimal Vec, rich Iterator trait, zero-cost lazy iteration
- **Haskell:** Rich list + Foldable/Traversable typeclasses
- **Camp choice:** Lean List + rich Iter (Rust-style, adapted for immutable FP)

### String design patterns

- **Roc:** Single `Str` type, ASCII-only case ops, Unicode in package, `walk_utf8` for byte iteration
- **Gleam:** Grapheme-based operations, `Result(v, Nil)` for fallible ops
- **Rust:** `str`/`String` split, lazy char/byte iterators, `Option` for fallible ops
- **Koka:** `string` + `sslice` (zero-copy substring), `maybe` for fallible ops

### Prelude design patterns

- **Rust:** Tiny prelude (traits + 5 types), edition-gated evolution
- **Gleam:** Minimal (types + constructors only), all functions require import
- **Elm:** Medium (Basics exposed fully, List/Dict qualified)
- **Haskell:** Large (~100 functions), controversial, alternative preludes exist
- **OCaml:** Medium (built-in types + operators, submodules qualified)

### Codec framework patterns

- **Roc:** Format-agnostic `Encode`/`Decode` abilities, auto-derived, `EncoderFormatting`/`DecoderFormatting` backends
- **Rust serde:** Format-agnostic `Serialize`/`Deserialize`, `#[derive]`, `Serializer`/`Deserializer` traits, visitor
  pattern
- **Gleam:** Format-specific `Decoder(a)` tied to `Dynamic`, `map`/`then`/`one_of` combinators
- **Haskell Aeson:** JSON-specific `FromJSON`/`ToJSON`, Generic-based derivation

### Duration/DateTime patterns

- **Go:** `Duration = int64` nanoseconds (simplest, signed, ~290yr range)
- **Rust:** `Duration { secs: u64, nanos: u32 }` (unsigned, ~584B yr range)
- **Haskell:** `NominalDiffTime = Pico` (picosecond, signed, via Num typeclass)
- **Koka:** 128-bit double-double (attosecond, signed, ~300B yr range)
- **DateTime TZ:** Parametric (Rust `DateTime<Tz>`) vs runtime field (Haskell/Go/Python/Koka)

### Path design patterns

- **Rust:** `PathBuf`/`Path` (owned/borrowed), `Component` enum, rich methods
- **Koka:** Opaque `path` type, auto-normalized, `/` operator for joining
- **Haskell:** `FilePath = String` (legacy), pure functions
- **Go:** Plain `string`, pure functions, `Clean` for normalization
- **Python:** `PurePath`/`Path` split (I/O vs no-I/O), object-oriented

______________________________________________________________________

## 5. Changes from Current Spec

The current spec (openspec/specs/stdlib/spec.md) lists these modules:
`Result, Option, Bool, Int, Str, List, Iter, Map, Set, Eq, Ord, Hash, Fmt, Path, Console!, Throw!, File!, Env!, Time!, Random!, Log!, Crypto.Random!, Bytes, Encode, Decode`

**Changes needed:**

1. **Remove `Option`** from module listing (D1)
1. **Add** `Display`, `Default`, `IntoIter`, `FromIter`, `From`, `TryFrom` (D9)
1. **Add** `Order` type (part of Ord trait module, structural tag union D16)
1. **Add** `Hasher` type (opaque, part of Hash trait module, D29)
1. **Add** `EncoderFormatting`, `DecoderFormatting` traits (D26, tentative)
1. **Replace** `Int` with `Num` namespace containing per-type submodules (D27)
1. **Add** `Duration` to Priority 1 (D24, Rust-style signed struct)
1. **Move** `DateTime`, `Date`, `Time` to official packages (D24, jiff-style design)
1. **Add** `Uuid` module
1. **Add** `Base64`, `Base64URL`, `Base32`, `Hex` modules
1. **Add** `Gzip` module
1. **Add** `Regex`, `Uri`, `Json` modules (already in spec requirements but not in module listing)
1. **Update** `Log!` to message-only (D15)
1. **Update** `Map` to specify ordered (tree-based) for referential transparency (D7)
1. **Update** `Iter.next` return type from `[Some(a) | None]` to `[Yield(a) | Done]` (D2)
1. **Update** `Result` API to include `unwrap!`, `catch`, `unwrap_or_default`, `or`, `filter`, `flatten`, `to_list`,
   `from_list` (D6)
1. **Update** prelude to include `Ok`, `Err` constructors (D17)
1. **Remove** `Clone`/`Copy` if they were ever in the spec (D9)
1. **Update** `File!` to only `foo!` variants, no `try_foo` (D23)
1. **Update** `Encode`/`Decode` to format-agnostic Encode + format-specific Decode (D26, tentative)
1. **Update** `Fmt` to house Display/Debug traits, format specifiers in interpolation (D28)
1. **Update** module organization to flat except `Num` and `Crypto` (D30)
1. **Update** `Result` API to include `unwrap!`, `catch`, `unwrap_or_default`, `or`, `filter`, `flatten`, `to_list`,
   `from_list`
1. **Update** prelude to include `Ok`, `Err` constructors
1. **Remove** `Clone`/`Copy` if they were ever in the spec (they're not currently listed)

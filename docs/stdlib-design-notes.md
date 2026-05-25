# Camp Standard Library — Design Notes

> Working document capturing all design decisions, open questions, and proposed APIs from the stdlib design grilling session. This is NOT a spec — it's the research and reasoning that will inform spec updates.

---

## 1. Decisions Made

### D1: Drop `Option`, keep `Result` + `Throw!`

Three error/absence mechanisms (Option + Result + Throw!) is too many. Two is right.

- **Can't drop Throw!** — effects are core to Camp's identity
- **Can't drop Result** — data vs control flow distinction: Result is storable, pure, local; Throw! is propagating, effectful
- **So Option goes** — eliminates Option↔Result impedance mismatch, one set of combinators, specific error tags replace None's ambiguity

Non-failure optionality uses domain-specific tag unions: `[Loading, Loaded(Artist)]` instead of `Option(Artist)`.

Camp differs from Roc (no error type inference, no optional record fields), but tag unions make `Result(a, [SpecificTag])` ergonomic.

### D2: `Iter.next` uses `[Yield(a) | Done]` (tentative)

Iteration being "done" isn't an error — Result framing is semantically wrong. Domain-specific tag unions beat generic wrappers for non-failure optionality. May revisit if pattern matching ergonomics are bad.

### D3: Error tags — specific per operation (Pattern A)

`Dict.get` returns `Result(v, [KeyNotFound])`, `List.first` returns `Result(a, [ListWasEmpty])`. Tags are naturally module-qualified via Camp's module system. No collision risk, composes with effect rows.

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
- **Map** — ordered tree map (Priority 1) — MUST be ordered for referential transparency (hash maps have non-deterministic iteration order)
- **Set** — ordered tree set (Priority 1)
- **Iter** — lazy iterator (Priority 1)
- **Bytes** — contiguous byte buffer (Priority 1)
- **Str** — UTF-8 string (Priority 1)
- **Array** — deferred to future design task (needs const generics, mutability semantics)
- **StringBuilder** — deferred to future consideration

### D8: List API — lean, Iter does the rest

"One way to do things" principle. List is for construction, structural access, and conversion. Iter is for all transformation.

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

**Derivable:** `Eq`, `Ord`, `Hash`, `Debug`, `Default`
**Not derivable:** `Display`
**Collection:** `IntoIter(a)`, `FromIter(c, a)`
**Codec:** `Encode(a, f)`, `Decode(a, f)`
**Conversion:** `From(source, target)`, `TryFrom(source, target, e)`

**Eliminated:** `Clone`, `Copy` — Camp is auto-memory-managed (Perceus RC) and immutable. Values are always shared by reference; "cloning" is meaningless.

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

Default I64/F64 for unannotated literals, context unification resolves when type is known. Evolve toward Roc-style polymorphic literals later.

### D12: String types — Str + Bytes

- `Str` = validated UTF-8, flat buffer, immutable
- `Bytes` = raw bytes, no encoding guarantee
- `StringBuilder` deferred

### D13: Map/Set API decisions

- `Map.update` — yes, included in v1
- `Map.keys` / `Map.values` — return `Iter`, not `List`
- Set operations (`union`, `intersection`, `difference`, `symmetric_difference`, `is_subset`, `is_disjoint`) — on Set directly, not through Iter

### D14: Effect module naming convention

- `foo!` for Throw! version, `try_foo` for Result version
- `File.exists!` — effectful but can't fail, no `try_` variant needed

---

## 2. Open Questions

### Q1: Log! structured data design (PINNED)

Camp doesn't have variadic functions. The spec says `Log.info!("Request processed", { duration_ms: 42, path: "/api/users", status: 200 })` but how does this work without dynamic record inspection?

**Options:**
- **A) Just the message, no structured data** — `Log.info! : Str -> -[Log!]-> ()`. Simplest. Structured logging can be a package.
- **B) Explicit list of kv pairs** — `Log.info! : Str, List((Str, Str)) -> -[Log!]-> ()`. Verbose at call sites.
- **C) Record-based with Inspect/Debug trait** — `Log.info! : Str, r -> -[Log!]-> ()` where r is any record rendered via Debug. Depends on Camp's record/inspection story.

**My recommendation:** A for v1. Structured logging is important but the design depends on Camp's record/inspection capabilities, which aren't settled. Start simple, add structure later.

**Cross-language research:**
- Koka: Logging is a user-defined effect with a handler. No built-in structured logging.
- Roc: No logging module. Uses `Stderr.line!` directly.
- Rust: `log` crate facade + `tracing` for structured data. Structured via key-value pairs.
- Haskell: `co-log` uses contravariant functors for composable structured logging. `polysemy-log` uses effects.
- **Key pattern:** Define a `Log!` effect with severity levels, render at the boundary. Effect handlers allow per-call-stack log level configuration.

### Q2: Prelude design

What's auto-imported? This is a major design decision.

**Cross-language spectrum:**
- **Minimal (Rust, Gleam):** Types + constructors only. All functions require explicit import.
- **Medium (OCaml, Roc, Elm):** Types + constructors + core operators. Module functions are qualified.
- **Large (Haskell, F#):** Types + constructors + operators + many functions.

**My recommendation for Camp:** Medium — closer to Elm/Roc.

**Proposed prelude:**
```
-- Types always in scope
Bool (True, False)
Result (Ok, Err)     -- via import Result { [Ok, Err] }
Order (Less, Equal, Greater)
I64, F64             -- default numeric types
Str                  -- string type

-- Traits always in scope (so methods are available)
Eq, Ord, Hash, Debug, Display, Default
IntoIter, FromIter
From, TryFrom

-- Operators (built into language, not from module)
+, -, *, /, ==, !=, <, >, <=, >=
and, or, not
|>                   -- pipe
->, -[e]->           -- function arrows

-- Nothing else auto-imported
-- All module functions require explicit import or qualified access
-- List.map, Str.length, Dict.get, etc. all require import
```

**Key decisions:**
- Should `List`, `Str`, `Dict` constructors be in scope? (Elm exposes `List` type but not functions)
- Should `Iter` be in scope?
- Should `Order` be in scope?
- Should numeric type names (I8, U8, etc.) all be in scope, or just I64/F64?

### Q3: Str API design

**Cross-language patterns:**

| Category | Functions | Notes |
|---|---|---|
| **Queries** | `length`, `is_empty`, `byte_size` | Unicode length vs byte length |
| **Comparison** | `starts_with`, `ends_with`, `contains` | |
| **Slicing** | `take`, `drop`, `slice` | Grapheme-based or byte-based? |
| **Splitting** | `split`, `split_first`, `split_last` | split_first/last return Result |
| **Trimming** | `trim`, `trim_start`, `trim_end` | |
| **Case** | `to_lower`, `to_upper` | Unicode or ASCII only? |
| **Concat** | `concat`, `join_with`, `repeat` | |
| **Replace** | `replace`, `replace_first`, `replace_last` | |
| **Prefix/Suffix** | `with_prefix`, `drop_prefix`, `drop_suffix` | |
| **Conversion** | `to_bytes`, `from_bytes` | from_bytes returns Result |
| **Parsing** | `to_i64`, `to_f64`, etc. | All return Result |
| **Iteration** | `to_iter` (chars), `to_graphemes` | Via IntoIter |

**Key design questions:**
- Should `Str.length` count bytes, codepoints, or graphemes? (Roc deliberately obscures this; Gleam counts graphemes; Rust counts bytes)
- Should `Str.slice` be grapheme-safe or byte-based? (Gleam: grapheme; Rust: byte; Haskell: char)
- Should `Str.to_lower`/`to_upper` be Unicode or ASCII-only? (Roc: ASCII-only, Unicode in package; Gleam: Unicode; Rust: Unicode)
- Should `Str.split_first` return `Result({ before: Str, after: Str }, [NotFound])` or `Result((Str, Str), [NotFound])`?

**My recommendation:**
- `Str.length` — grapheme count (most intuitive for users). `Str.byte_size` for byte count.
- `Str.slice` — grapheme-safe (can't split a grapheme cluster)
- `Str.to_lower`/`to_upper` — Unicode in stdlib (Camp targets WASI, not embedded; Unicode is expected)
- `Str.split_first` — return `Result({ before: Str, after: Str }, [NotFound])` (named fields are clearer than tuples)

### Q4: Bytes API design

**Cross-language patterns:**

| Category | Functions | Notes |
|---|---|---|
| **Construction** | `new`, `singleton`, `from_list`, `from_str` | |
| **Queries** | `length`, `is_empty` | |
| **Access** | `get`, `first`, `last` | get returns Result for OOB |
| **Slicing** | `slice`, `take`, `drop` | |
| **Concat** | `append`, `concat` | |
| **Conversion** | `to_str`, `to_list`, `to_iter` | to_str returns Result |
| **Encoding** | `to_base64`, `from_base64`, `to_hex`, `from_hex` | Or separate modules? |

**Key question:** Should Base64/Hex encoding live on `Bytes` or in separate modules?

The current spec has separate `Base64`, `Base64URL`, `Base32`, `Hex` modules. This is cleaner — encoding is a separate concern from byte manipulation.

### Q5: Map API design

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

**Open questions:**
- Should `Map.update` use `Result(v, [KeyNotFound]) -> Result(v, [UpdateRemoved])` (Roc style) or `Maybe(v) -> Maybe(v)` (Haskell alter style)? Since we dropped Option, Result is the way.
- Should `Map.union` take a conflict-resolution function? (Gleam has `combine` for this)
- Should `Map.min`/`Map.max` exist? (Haskell has `minView`/`maxView` returning `Maybe`; ordered maps can do this efficiently)

### Q6: Set API design

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

### Q7: Iter API design

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

**Effect tracking:** `Iter` is parameterized over both `a` (element type) and `e` (effect row). Effect rows merge via row unification when closures have different effects than the iterator's `next`.

### Q8: Effect module APIs

#### Console!
```
Console.println! : Str -> -[Console!]-> ()
Console.print!   : Str -> -[Console!]-> ()
Console.readline! : -[Console!]-> Str
```

#### File!
```
-- Throw! versions (propagate errors)
File.read_all!  : Path -> -[File!, Throw!([FileErr])]-> Str
File.write_all! : Path, Str -> -[File!, Throw!([FileErr])]-> ()
File.append_all! : Path, Str -> -[File!, Throw!([FileErr])]-> ()
File.read_bytes! : Path -> -[File!, Throw!([FileErr])]-> Bytes
File.write_bytes! : Path, Bytes -> -[File!, Throw!([FileErr])]-> ()
File.list_dir!  : Path -> -[File!, Throw!([FileErr])]-> List(Path)
File.create_dir! : Path -> -[File!, Throw!([FileErr])]-> ()
File.remove!    : Path -> -[File!, Throw!([FileErr])]-> ()
File.copy!      : Path, Path -> -[File!, Throw!([FileErr])]-> ()

-- Result versions (return errors as values)
File.try_read_all  : Path -> -[File!]-> Result(Str, [FileErr])
File.try_write_all : Path, Str -> -[File!]-> Result((), [FileErr])
-- ... etc for each

-- Non-failing queries
File.exists!    : Path -> -[File!]-> Bool
File.is_dir!    : Path -> -[File!]-> Bool
File.is_file!   : Path -> -[File!]-> Bool
```

**Open question:** What tags does `FileErr` contain? Cross-language research shows:
- Roc: `[FileReadErr Path IOErr, FileReadUtf8Err Path]` — very specific
- Gleam: 50+ POSIX errno variants
- Rust: `io::ErrorKind` enum with ~20 variants
- Haskell: `IOException` with `ioe_type`

**My recommendation:** Start with a small set of specific tags:
```
@FileErr : [NotFound | PermissionDenied | AlreadyExists | InvalidUtf8 | IoErr]
```
Grow as needed. API permanence means we can add but not remove.

#### Env!
```
Env.get!       : Str -> -[Env!, Throw!([VarNotFound])]-> Str
Env.try_get    : Str -> -[Env!]-> Result(Str, [VarNotFound])
Env.vars!      : -[Env!]-> List((Str, Str))
Env.args!      : -[Env!]-> List(Str)
```

**Note:** `Env.set!` is questionable on WASI (environment is typically read-only). May omit.

#### Time!
```
Time.now!        : -[Time!]-> DateTime
Time.monotonic!  : -[Time!]-> Duration
```

#### Random!
```
Random.int!   : I64, I64 -> -[Random!]-> I64    -- range [min, max)
Random.float! : F64, F64 -> -[Random!]-> F64    -- range [min, max)
Random.bytes! : I64 -> -[Random!]-> Bytes         -- length
Random.bool!  : -[Random!]-> Bool
```

#### Crypto.Random!
```
Crypto.Random.int!   : I64, I64 -> -[Crypto.Random!]-> I64
Crypto.Random.bytes! : I64 -> -[Crypto.Random!]-> Bytes
Crypto.Random.uuid!  : -[Crypto.Random!]-> Uuid
```

#### Log! (design TBD)
```
-- Option A: message only
Log.debug! : Str -> -[Log!]-> ()
Log.info!  : Str -> -[Log!]-> ()
Log.warn!  : Str -> -[Log!]-> ()
Log.error! : Str -> -[Log!]-> ()

-- Option B: message + kv list
Log.info! : Str, List((Str, Str)) -> -[Log!]-> ()

-- Option C: message + record (needs Debug/Inspect trait)
Log.info! : Str, r -> -[Log!]-> ()
```

### Q9: Duration and DateTime design

**Duration:**
```
@Duration : -- opaque type, internally I64 nanoseconds (signed, ~290 year range)

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

**Design choice:** Go's `type Duration int64` (nanoseconds) is the simplest and most practical. Signed to allow "time since" calculations. I64 gives ~290 year range at nanosecond resolution.

**DateTime:**
```
-- Naive types (no timezone)
@Date : { year: I64, month: I64, day: I64 }
@Time : { hour: I64, minute: I64, second: I64, nanosecond: I64 }
@DateTime : { date: Date, time: Time }

-- Timezone-aware
@Offset : I64  -- seconds from UTC
@ZonedDateTime : { datetime: DateTime, offset: Offset, name: Str }

-- Construction
DateTime.from_iso8601 : Str -> Result(DateTime, [ParseError])
Date.from_ymd : I64, I64, I64 -> Result(Date, [InvalidDate])
Time.from_hms : I64, I64, I64 -> Result(Time, [InvalidTime])

-- Formatting
DateTime.to_iso8601 : DateTime -> Str
DateTime.format : DateTime, Str -> Str   -- strftime-style format codes

-- Arithmetic
DateTime.add  : DateTime, Duration -> DateTime
DateTime.sub  : DateTime, DateTime -> Duration
DateTime.diff : DateTime, DateTime -> Duration

-- Accessors
DateTime.date    : DateTime -> Date
DateTime.time    : DateTime -> Time
DateTime.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday

-- Timezone conversion
ZonedDateTime.to_utc : ZonedDateTime -> DateTime
ZonedDateTime.with_offset : ZonedDateTime, Offset -> ZonedDateTime
```

**Design choice:** Start with naive DateTime + ZonedDateTime (runtime timezone field, not parametric). This matches Haskell/Go/Python/Koka. Rust's parametric `DateTime<Tz>` is elegant but complex for Camp's trait system.

### Q10: Path module design

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

**Design choice:** Opaque `Path` type (like Koka, Rust). Not just a string. Auto-normalized on construction. No I/O operations on Path itself — those live in `File!`.

### Q11: Encode/Decode codec framework

Following Roc's design (format-agnostic traits):

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

**Key difference from Roc:** Camp requires explicit `derives Encode, Decode`. Roc auto-derives. Camp's trait system (structural verification with nominal opt-in via `is`) makes auto-derivation harder.

### Q12: Bool and Int module APIs

```
-- Bool
Bool.not  : Bool -> Bool
Bool.xor  : Bool, Bool -> Bool
Bool.and  : Bool, Bool -> Bool
Bool.or   : Bool, Bool -> Bool

-- Int (operations for all integer types, parameterized)
Int.abs   : I64 -> I64
Int.clamp : I64, I64, I64 -> I64
Int.max   : I64, I64 -> I64
Int.min   : I64, I64 -> I64
Int.range : I64, I64 -> Iter(I64)    -- [start, end)
Int.to_str : I64 -> Str
Int.from_str : Str -> Result(I64, [InvalidFormat])
```

**Open question:** Should `Int` be a single module for I64, or should each numeric type have its own module? Roc has `Num` with subtypes. Rust has per-type modules. OCaml has separate `Int`, `Int32`, `Int64`.

**My recommendation:** Single `Int` module for I64 (the default). Other types use qualified access: `I32.abs`, `U8.max`, etc. Or: a generic `Num` module with type-specific submodules. This needs more thought.

### Q13: Fmt module

The current spec lists `Fmt` but doesn't define it. Cross-language research:

- **Rust:** `std::fmt` module with `Display`, `Debug`, `Formatter` types. `format!` macro.
- **Haskell:** `Text.Printf` (C-style), `Text.Show` (typeclass-derived)
- **Gleam:** No Fmt module; uses `string.inspect` and string concatenation
- **Roc:** `Inspect` ability for debug formatting

**My recommendation:** `Fmt` should provide:
```
Fmt.debug  : a -> Str    -- via Debug trait, machine-oriented
Fmt.display : a -> Str   -- via Display trait, human-oriented
Fmt.format  : Str, a -> Str   -- printf-style? Or just use string interpolation?
```

Camp already has string interpolation (`"Hello, {name}!"`). So `Fmt.format` may not be needed. The module might just be `Debug` and `Display` traits with their methods.

### Q14: Hasher type

The `Hash` trait takes a `Hasher` parameter. What is `Hasher`?

```
@Hasher : @{ state: I64 }   -- or opaque

Hasher.new    : Hasher
Hasher.update : Hasher, I64 -> Hasher
Hasher.update_str : Hasher, Str -> Hasher
Hasher.update_bytes : Hasher, Bytes -> Hasher
Hasher.finish : Hasher -> I64
```

This allows hash composition — you can hash struct fields into a running hasher and produce one final hash. The `Hash` trait implementation calls `hasher->update_str(field1)->update_i64(field2)->finish()`.

### Q15: Module organization — flat or nested?

Current spec has flat module names: `Result`, `List`, `Str`, etc. But some modules logically nest:
- `Crypto.Random!` (already nested)
- `Json.Encode`, `Json.Decode`, `Json.Value`?
- `Base64`, `Base64URL`, `Base32`, `Hex` — or `Encoding.Base64`, `Encoding.Hex`?

**My recommendation:** Keep flat for core types (Result, List, Str, Map, Set, Iter, Bytes). Nest for domain groups:
- `Crypto.Random!` (already decided)
- `Json` as flat module with `Json.encode`, `Json.decode`, `Json.Value`, `Json.parse`
- `Base64`, `Base64URL`, `Base32`, `Hex` as separate flat modules (they're small and distinct)
- `DateTime`, `Date`, `Time`, `Duration` as separate flat modules (they're distinct types)

---

## 3. Complete Module Listing (Proposed)

### Priority 1 — Required for any non-trivial program

| Module | Type | Description |
|---|---|---|
| `Result` | Type + functions | Error/absence handling (replaces Option) |
| `Bool` | Type + functions | Boolean operations |
| `Int` | Functions | Integer operations (I64 default) |
| `Str` | Type + functions | UTF-8 string operations |
| `List` | Type + functions | Immutable linked list |
| `Iter` | Type + functions | Lazy iterator |
| `Map` | Type + functions | Ordered tree map |
| `Set` | Type + functions | Ordered tree set |
| `Bytes` | Type + functions | Raw byte buffer |
| `Eq` | Trait | Equality |
| `Ord` | Trait | Ordering (with `Order` type) |
| `Hash` | Trait | Hashing (with `Hasher` type) |
| `Debug` | Trait | Debug formatting |
| `Display` | Trait | Display formatting |
| `Default` | Trait | Default values |
| `IntoIter` | Trait | Convert to iterator |
| `FromIter` | Trait | Convert from iterator |
| `From` | Trait | Infallible conversion |
| `TryFrom` | Trait | Fallible conversion |
| `Encode` | Trait | Format-agnostic encoding |
| `Decode` | Trait | Format-agnostic decoding |
| `Fmt` | Functions | Formatting utilities |
| `Path` | Type + functions | Filesystem path |
| `Console!` | Effect | Standard I/O |
| `Throw!` | Effect | Error propagation |
| `File!` | Effect | Filesystem access |
| `Env!` | Effect | Environment variables |
| `Time!` | Effect | Time access |
| `Random!` | Effect | Fast PRNG |
| `Log!` | Effect | Logging |

### Priority 2 — Required for most REST APIs

| Module | Type | Description |
|---|---|---|
| `Json` | Type + functions | JSON parsing/stringify/Value |
| `Regex` | Type + functions | Regular expressions |
| `Uri` | Type + functions | URI/URL parsing |
| `Duration` | Type + functions | Time duration |
| `DateTime` | Type + functions | Date and time |
| `Date` | Type + functions | Date without time |
| `Time` | Type + functions | Time without date |
| `Crypto.Random!` | Effect | Cryptographic random |
| `Uuid` | Type + functions | UUID v4/v7 |
| `Base64` | Functions | Base64 encode/decode |
| `Base64URL` | Functions | URL-safe Base64 |
| `Base32` | Functions | Base32 encode/decode |
| `Hex` | Functions | Hex encode/decode |

### Priority 3 — Important for completeness

| Module | Type | Description |
|---|---|---|
| `Gzip` | Functions | Compression/decompression |
| `EncoderFormatting` | Trait | Format backend for encoding |
| `DecoderFormatting` | Trait | Format backend for decoding |

### Numeric type modules (Priority 1)

| Module | Description |
|---|---|
| `I8`, `I16`, `I32`, `I64` | Signed integer types and operations |
| `U8`, `U16`, `U32`, `U64` | Unsigned integer types and operations |
| `F32`, `F64` | Floating-point types and operations |

### Official Packages (NOT stdlib)

| Package | Description |
|---|---|
| `Http` | Server!/Client! effects |
| `Database` | query!/execute!/transaction! |
| `Database.Postgres` | PostgreSQL driver |
| `Database.Sqlite` | SQLite driver |
| `Database.MySql` | MySQL driver |
| `Database.Redis` | Redis driver |
| `Crypto.Hash` | sha256, sha512, blake2b, etc. |

### Deferred (future design tasks)

| Module | Description | Why deferred |
|---|---|---|
| `Array` | Fixed-length, O(1) index | Needs const generics design |
| `StringBuilder` | Efficient string concatenation | Needs rope/buffer design |
| `Queue` | FIFO data structure | Can use List with discipline |
| `Stack` | LIFO data structure | Can use List with discipline |

---

## 4. Key Research Findings (Condensed)

### Error handling across languages

| Language | Option/Maybe | Result/Either | Effects/Exceptions | Bridge functions |
|---|---|---|---|---|
| Roc | ❌ None | ✅ Result only | ❌ (Task = type) | `?` operator |
| Gleam | ✅ (but idiom: Result) | ✅ | ❌ | `try` syntax |
| Rust | ✅ | ✅ | ❌ | `?` operator + From trait |
| Koka | ✅ maybe | ✅ either | ✅ exn effect | error/try, untry, maybe, either |
| Haskell | ✅ Maybe | ✅ Either | ✅ IO exceptions | try, catch, evaluate |
| Swift | ✅ Optional | ✅ Result | ✅ throwing | try/catch |

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
- **Rust serde:** Format-agnostic `Serialize`/`Deserialize`, `#[derive]`, `Serializer`/`Deserializer` traits, visitor pattern
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

---

## 5. Changes from Current Spec

The current spec (openspec/specs/stdlib/spec.md) lists these modules:
`Result, Option, Bool, Int, Str, List, Iter, Map, Set, Eq, Ord, Hash, Fmt, Path, Console!, Throw!, File!, Env!, Time!, Random!, Log!, Crypto.Random!, Bytes, Encode, Decode`

**Changes needed:**
1. **Remove `Option`** from module listing (D1)
2. **Add** `Display`, `Default`, `IntoIter`, `FromIter`, `From`, `TryFrom` (D9)
3. **Add** `Order` type (part of Ord trait module)
4. **Add** `Hasher` type (part of Hash trait module)
5. **Add** `EncoderFormatting`, `DecoderFormatting` traits
6. **Add** numeric type modules: `I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`
7. **Add** `Duration`, `DateTime`, `Date`, `Time` types
8. **Add** `Uuid` module
9. **Add** `Base64`, `Base64URL`, `Base32`, `Hex` modules
10. **Add** `Gzip` module
11. **Add** `Regex`, `Uri`, `Json` modules (already in spec requirements but not in module listing)
12. **Update** `Log!` requirement to remove structured kv syntax (pending design)
13. **Update** `Map` to specify ordered (tree-based) for referential transparency
14. **Update** `Iter.next` return type from `[Some(a) | None]` to `[Yield(a) | Done]`
15. **Update** `Result` API to include `unwrap!`, `catch`, `unwrap_or_default`, `or`, `filter`, `flatten`, `to_list`, `from_list`
16. **Update** prelude to include `Ok`, `Err` constructors
17. **Remove** `Clone`/`Copy` if they were ever in the spec (they're not currently listed)

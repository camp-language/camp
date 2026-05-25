# Design: Priority 2 Standard Library Modules

## Architecture Decisions

### AD1: One Random! Effect + Two Handlers (D31)

**Decision**: Fold `Crypto.Random!` into `Random!` as a second handler. `Random!` defines the interface; `random_prng` and `random_crypto` provide implementations.

**Rationale**: Algebraic effects separate interface from implementation. `Random!` declares *what* you need (randomness); handlers decide *how* to provide it (fast PRNG vs WASI `random_get`). Two separate effects with identical operation signatures is near-duplication. The handler choice — not the effect — determines security guarantees.

**Tradeoff**: A function like `v4! : -[Random!]-> Uuid` cannot guarantee crypto-grade randomness from its type alone; it depends on which handler the caller provides. This is acceptable: UUIDs are about uniqueness, not cryptographic security. Users who need crypto-grade randomness for keys/tokens handle `Random!` with `random_crypto` explicitly.

**Impact**:
- `Crypto.Random!` module eliminated from spec and impl-spec
- `Random!` gains `bytes!` operation (D32)
- `random_crypto` handler added (WASI `random_get` syscall)
- Existing `random_prng` handler unchanged

```camp
effect Random! : {
  bytes! : U64 -> -[Random!]-> Bytes          // NEW
  int!   : I64, I64 -> -[Random!]-> I64        // existing
  float! : -[Random!]-> F64                     // existing
}

random_prng   : U64 -> Handler(Random!)         // existing: seeded fast PRNG
random_crypto : Handler(Random!)                // NEW: WASI random_get, cryptographically secure
```

### AD2: JSON Number — Three-Variant Tag Union (D35)

**Decision**: `JsonNumber` uses `[PosInt(U64) | NegInt(I64) | Float(F64)]`, following Rust's `serde_json::Number` design.

**Rationale**: A single `Num(F64)` variant loses the integer/float distinction — `42` round-trips as `42.0`, and integers beyond 2^53 lose precision. Rust's three-variant approach preserves this distinction: the parser records whether the input was an integer or float, and serializers emit the correct representation. This is the standard approach across mature JSON libraries.

**Impact**:
- `JsonValue` uses `Num(JsonNumber)` instead of `Num(F64)`
- `as_i64`, `as_u64`, `as_f64` accessors on `JsonNumber` (mirror Rust's `is_i64`/`as_i64` pattern)
- `Float(F64)` only stores finite values (NaN/Infinity are not valid JSON numbers)

### AD3: JSON Object — Map Representation (D34)

**Decision**: `Obj(Map(Str, JsonValue))` for O(log n) field lookup.

**Rationale**: Field access is the dominant operation on JSON objects. `Map` provides O(log n) lookup vs O(n) for `List((Str, JsonValue))`. The tradeoff is loss of insertion order and key deduplication — if duplicate keys exist, later values overwrite earlier ones (matching JSON spec's recommendation).

**Impact**: Programs that need insertion order (rare) can use the streaming parser (`JsonEvent`) to capture key order.

### AD4: RE2-Style Regex Engine (D37)

**Decision**: Use RE2-style regex engine — no backtracking, guaranteed O(n) time, no backreferences, no lookahead/lookbehind.

**Rationale**: A stdlib regex module must be safe against malicious input. PCRE-style backtracking can exhibit exponential time on crafted patterns (ReDoS). RE2 guarantees linear time at the cost of some features (no backreferences, no lookahead). For a stdlib, safety is more important than feature completeness. Users who need PCRE features can use an external package.

**Impact**:
- `replace`/`replace_all` take literal replacement strings (no backreference substitution)
- No lookahead (`(?=...)`, `(?!...)`) or lookbehind (`(?<=...)`, `(?<!...)`)
- No backreferences (`\1`, `\2`)
- `groups` in `Match` captures parenthesized groups but cannot refer to them in replacements

### AD5: URI Query — Raw String + Parsed Accessor (D36)

**Decision**: Store `query` as `Option(Str)` (raw percent-encoded string), with `parse_query`/`format_query` helper functions for `application/x-www-form-urlencoded` parsing.

**Rationale**: Following Rust's `url` crate: query strings have diverse formats (form-encoded, matrix parameters, custom). Storing raw preserves all information; parsing is opt-in. Eager parsing would lose the original encoding, force a single query format, and add allocation for programs that never inspect query parameters.

**Impact**: `parse_query : Str -> List((Str, Str))` handles form-encoded parsing. `format_query : List((Str, Str)) -> Str` reverses it.

### AD6: Uuid — Random! Only, No Separate Crypto Variant (D38)

**Decision**: `v4!` and `v7!` use `Random!` only. No `v4_secure!`/`v7_secure!` variants.

**Rationale**: UUIDs are about uniqueness, not cryptographic security. The standard UUID v4/v7 algorithms specify random bytes — they don't require cryptographic randomness. Users who need crypto-grade randomness for UUIDs handle `Random!` with `random_crypto` at the call site. Adding `v4_secure!`/`v7_secure!` doubles the API surface for a marginal security benefit that most users don't need.

**Impact**: Simpler Uuid API. `v7!` takes explicit `I64` timestamp (no coupling to `Time!` effect).

### AD7: Base64 — Parameterized + Shorthands (D39)

**Decision**: Core API uses `Base64Format` parameter (`encode : Base64Format, Bytes -> Str`), plus shorthand functions for the three most common formats.

**Rationale**: Parameterization is extensible (new formats add a tag variant, not new functions). Shorthands (`encode64`, `encode64url`, `encode16`) reduce boilerplate for the 90% case. Both styles serve different ergonomics without conflicting.

**Impact**: 4 shorthand pairs (encode/decode) + 2 parameterized functions (encode/decode) + 2 string-convenience pairs (encode_str/decode_str) = 14 functions total.

### AD8: Pure Camp vs Intrinsic Split

**Decision**: Pure Camp implementations where algorithms are bounded-complexity string/byte operations (Uri, Base64). Intrinsics where complex parsing/engines need performant C runtimes (Json, Regex).

| Module | Implementation | Rationale |
|--------|---------------|-----------|
| Random! modification | Intrinsic | WASI syscall, handler dispatch |
| Uuid (generation) | Intrinsic | Random! effect interaction |
| Uuid (parse/format) | Pure Camp | String parsing/formatting, no C runtime needed |
| Json | Intrinsic | Complex recursive-descent parser, needs performant runtime |
| Regex | Intrinsic | NFA engine compilation and execution |
| Uri | Pure Camp | RFC 3986 is bounded string scanning |
| Base64 | Pure Camp | Lookup table + bit shifting, trivial algorithms |

## Module Specifications

### 1. Random! (Modified — P1 Module Change)

Add `bytes!` operation and `random_crypto` handler.

```camp
// Random.camp — MODIFIED
effect Random! : {
  bytes! : U64 -> -[Random!]-> Bytes
  int!   : I64, I64 -> -[Random!]-> I64
  float! : -[Random!]-> F64
}

// Handlers
random_prng   : U64 -> Handler(Random!)      // existing: seeded fast PRNG
random_crypto : Handler(Random!)             // NEW: WASI random_get

// Intrinsic implementations
// bytes!(n) — crash "intrinsic: Random.bytes"
// int!(lo, hi) — crash "intrinsic: Random.int"
// float!() — crash "intrinsic: Random.float"
// random_prng(seed) — crash "intrinsic: Random.random_prng"
// random_crypto() — crash "intrinsic: Random.random_crypto"
```

**`random_crypto` handler**: Every operation calls WASI `random_get` directly. No PRNG state, no seed, no deterministic replay. Suitable for cryptographic keys, tokens, nonces.

### 2. Uuid

```camp
// Uuid.camp — NEW
@Uuid : pub Bytes                              // 16 bytes, opaque

@UuidErr : pub [
    InvalidFormat(Str)
  | InvalidLength(U64)
  | InvalidVersion(U8)
]

@UuidVariant : pub [V4 | V7 | Unknown(U8)]
@UuidFormat  : pub [Standard | Compact | Urn | Braced]

// Generation — effectful (intrinsic)
v4! : -[Random!]-> Uuid
v7! : I64 -> -[Random!]-> Uuid                // timestamp in milliseconds

// Parsing — pure Camp
parse      : Str -> Result(Uuid, UuidErr)
from_bytes : Bytes -> Result(Uuid, UuidErr)

// Formatting — pure Camp
to_str    : Uuid -> Str                        // 8-4-4-4-12 lowercase hyphenated
format    : UuidFormat, Uuid -> Str
to_bytes  : Uuid -> Bytes

// Inspection — pure Camp
version   : Uuid -> U8
variant   : Uuid -> UuidVariant
timestamp : Uuid -> Result(I64, [])            // V7 only; Err if not V7

// Intrinsic implementations
// v4!() — crash "intrinsic: Uuid.v4"
// v7!(ts) — crash "intrinsic: Uuid.v7"
```

**Design notes**:
- `@Uuid` wraps 16 `Bytes` — lightweight, no allocation beyond the byte storage
- `v7!` takes explicit `I64` timestamp — no coupling to `Time!` effect. Callers pass `Time!.now!()` if desired.
- `format(Standard, u)` → `"550e8400-e29b-41d4-a716-446655440000"`
- `format(Compact, u)` → `"550e8400e29b41d4a716446655440000"`
- `format(Urn, u)` → `"urn:uuid:550e8400-e29b-41d4-a716-446655440000"`
- `format(Braced, u)` → `"{550e8400-e29b-41d4-a716-446655440000}"`

**Pure Camp implementations**:
```camp
parse = fn s -> Result(Uuid, UuidErr) {
  // Validate length (36 for standard, 32 for compact)
  // Validate hyphens at positions 8, 13, 18, 23
  // Validate hex characters
  // Validate version nibble (4 or 7)
  // Convert hex pairs to bytes
}

to_str = fn u -> Str {
  // Format 16 bytes as 8-4-4-4-12 lowercase hex with hyphens
}

format = fn fmt, u -> Str {
  // Switch on fmt: Standard adds hyphens, Compact removes them,
  // Urn prepends "urn:uuid:", Braced adds curly braces
}

version = fn u -> U8 {
  // Extract version nibble from byte 6 (0-indexed), high bits
}

variant = fn u -> UuidVariant {
  // Extract variant bits from byte 8
  // 10xx -> V4/V7, 110x -> Microsoft, 111x -> reserved
}

timestamp = fn u -> Result(I64, []) {
  // V7: extract 48-bit millisecond timestamp from bytes 0-5
  // Err([]) if not V7
}
```

### 3. Json

```camp
// Json.camp — NEW
@JsonNumber : pub [
    PosInt(U64)                                // non-negative integer
  | NegInt(I64)                                // negative integer
  | Float(F64)                                 // finite float (never NaN/Inf)
]

@JsonValue : pub [
    Null
  | Bool(Bool)
  | Num(JsonNumber)                            // D35: preserves int/float distinction
  | Str(Str)
  | Arr(List(JsonValue))
  | Obj(Map(Str, JsonValue))                   // D34: Map for O(log n) lookup
]

@JsonErr : pub [
    UnexpectedChar(U64, Str)                  // position + description
  | InvalidNumber(U64, Str)
  | UnexpectedEnd
  | TrailingContent(U64)
]

// Core DOM API — intrinsic
decode        : Str -> Result(JsonValue, JsonErr)
encode        : JsonValue -> Str
encode_pretty : JsonValue -> Str                // 2-space indent

// JsonNumber accessors — pure Camp
is_int   : JsonNumber -> Bool
is_float : JsonNumber -> Bool
as_i64   : JsonNumber -> Option(I64)           // None if PosInt > I64_MAX or Float
as_u64   : JsonNumber -> Option(U64)           // None if NegInt or Float
as_f64   : JsonNumber -> Option(F64)           // Always Some (every JsonNumber can be F64)

// JsonValue convenience accessors — pure Camp
get     : JsonValue, Str -> Result(JsonValue, JsonErr)
get_at  : JsonValue, U64 -> Result(JsonValue, JsonErr)
keys    : JsonValue -> Result(List(Str), [])              // Err if not Obj
values  : JsonValue -> Result(List(JsonValue), [])        // Err if not Obj
length  : JsonValue -> Result(U64, [])                    // Arr length or Obj key count

// Streaming parser — intrinsic
@JsonEvent : pub [
    StartObj
  | EndObj
  | StartArr
  | EndArr
  | Key(Str)
  | Null
  | Bool(Bool)
  | Num(JsonNumber)
  | Str(Str)
]

@JsonParser : pub { source : Str, pos : U64, depth : U64 }

parse_init : Str -> JsonParser
parse_next : JsonParser -> Result((JsonParser, JsonEvent), JsonErr)
parse_all  : Str -> Result(List(JsonEvent), JsonErr)

// Intrinsic implementations
// decode(s) — crash "intrinsic: Json.decode"
// encode(v) — crash "intrinsic: Json.encode"
// encode_pretty(v) — crash "intrinsic: Json.encode_pretty"
// parse_init(s) — crash "intrinsic: Json.parse_init"
// parse_next(p) — crash "intrinsic: Json.parse_next"
// parse_all(s) — crash "intrinsic: Json.parse_all"
```

**Design notes**:
- `as_f64` always returns `Some` — every `JsonNumber` can be lossily represented as F64 (large integers lose precision, but the conversion is always valid). Mirrors Rust's `serde_json::Number::as_f64`.
- `as_i64` returns `None` for `PosInt` values exceeding `I64_MAX` and for `Float` variants. Mirrors Rust's `is_i64`/`as_i64`.
- Streaming parser is a state machine: `parse_next` returns `(new_state, event)` for lazy consumption. `parse_all` materializes all events eagerly.
- `depth` field in `JsonParser` tracks nesting depth — reject input exceeding a configurable limit (e.g., 128) to prevent stack overflow on maliciously deep input.
- `Obj` deduplicates keys: later values overwrite earlier ones (per JSON spec).

**Pure Camp implementations**:
```camp
is_int = fn n -> match n {
  PosInt(_) -> True
  NegInt(_) -> True
  Float(_)  -> False
}

is_float = fn n -> match n {
  Float(_)  -> True
  PosInt(_) -> False
  NegInt(_) -> False
}

as_i64 = fn n -> match n {
  NegInt(i)  -> Some(i)
  PosInt(u)  -> if u <= 9223372036854775807 { Some(I64.from(u)) } else { None }
  Float(_)   -> None
}

as_u64 = fn n -> match n {
  PosInt(u)  -> Some(u)
  NegInt(_)  -> None
  Float(_)   -> None
}

as_f64 = fn n -> match n {
  Float(f)   -> Some(f)
  PosInt(u)  -> Some(F64.from(u))
  NegInt(i)  -> Some(F64.from(i))
}

get = fn v, key -> match v {
  Obj(m) -> match Map.get(m, key) {
    Some(child) -> Ok(child)
    None        -> Err(UnexpectedChar(0, "key not found: " ++ key))
  }
  _ -> Err(UnexpectedChar(0, "not an object"))
}

get_at = fn v, idx -> match v {
  Arr(items) -> match List.get_at(items, idx) {
    Some(child) -> Ok(child)
    None        -> Err(UnexpectedChar(0, "index out of bounds"))
  }
  _ -> Err(UnexpectedChar(0, "not an array"))
}
```

### 4. Regex

```camp
// Regex.camp — NEW
@Regex : pub { pattern : Str }                  // opaque compiled regex

@RegexErr : pub [
    CompileError(Str)
  | InvalidEscape(Str)
  | InvalidRepeat(Str)
]

@MatchGroup : pub { value : Str, start : U64, end : U64 }
@Match : pub { full : Str, start : U64, end : U64, groups : List(MatchGroup) }

// Compilation — intrinsic
compile  : Str -> Result(Regex, RegexErr)
is_match : Regex, Str -> Bool

// Search — intrinsic
find      : Regex, Str -> Option(Match)         // first match only
find_all  : Regex, Str -> List(Match)           // all non-overlapping matches

// Transformation — intrinsic
replace      : Regex, Str, Str -> Str           // first match, literal replacement
replace_all  : Regex, Str, Str -> Str           // all matches, literal replacement
split        : Regex, Str -> List(Str)          // split on matches
splitn       : Regex, Str, U64 -> List(Str)     // at most n-1 splits

// Utility — pure Camp
escape : Str -> Str                              // escape regex metacharacters

// Intrinsic implementations
// compile(pat) — crash "intrinsic: Regex.compile"
// is_match(r, s) — crash "intrinsic: Regex.is_match"
// find(r, s) — crash "intrinsic: Regex.find"
// find_all(r, s) — crash "intrinsic: Regex.find_all"
// replace(r, s, rep) — crash "intrinsic: Regex.replace"
// replace_all(r, s, rep) — crash "intrinsic: Regex.replace_all"
// split(r, s) — crash "intrinsic: Regex.split"
// splitn(r, s, n) — crash "intrinsic: Regex.splitn"
```

**Design notes**:
- RE2-style engine per D37: guaranteed O(n), no backtracking, no backreferences, no lookahead/lookbehind
- `@Regex` is opaque — compiled NFA can't be inspected
- `replace`/`replace_all` take *literal* replacement strings (no `$1`/`\1` backreference substitution — RE2 doesn't support backreferences)
- `find_all` returns all non-overlapping matches, leftmost-first
- `splitn(r, s, n)` produces at most n elements (n-1 splits)
- `escape` escapes `.` `*` `+` `?` `(` `)` `[` `]` `{` `}` `|` `\` `^` `$`

**Pure Camp implementation for `escape`**:
```camp
escape = fn s -> {
  // Walk each character; if metacharacter, prepend '\'
  // Metacharacters: . * + ? ( ) [ ] { } | \ ^ $
  s->to_iter()
   ->map(fn c -> if is_metachar(c) { "\\" ++ Str.from_char(c) } else { Str.from_char(c) })
   ->Str.join()
}
```

### 5. Uri

```camp
// Uri.camp — NEW — all pure Camp
@UriAuthority : pub {
    userinfo : Option(Str)
    host     : Str
    port     : Option(U16)
}

@Uri : pub {
    scheme    : Str
    authority : Option(UriAuthority)
    path      : Str
    query     : Option(Str)                     // D36: raw percent-encoded string
    fragment  : Option(Str)
}

@UriErr : pub [
    InvalidScheme(Str)
  | InvalidHost(Str)
  | InvalidPort(Str)
  | InvalidEscape(Str)
  | MissingScheme
]

// Parsing and formatting
parse   : Str -> Result(Uri, UriErr)
to_str  : Uri -> Str

// Component-level percent encoding
encode_component : Str -> Str                   // percent-encode for URI component
decode_component : Str -> Result(Str, UriErr)   // percent-decode

// Query string parsing (convenience)
parse_query  : Str -> List((Str, Str))          // form-encoded: "a=1&b=2" -> [("a","1"), ("b","2")]
format_query : List((Str, Str)) -> Str         // reverse

// Functional construction helpers
with_scheme    : Str, Uri -> Uri
with_authority : Option(UriAuthority), Uri -> Uri
with_path      : Str, Uri -> Uri
with_query     : Option(Str), Uri -> Uri
with_fragment  : Option(Str), Uri -> Uri
```

**Design notes**:
- Pure Camp — RFC 3986 parsing is bounded-complexity string scanning, no C runtime needed
- `query` stores raw string per D36; `parse_query`/`format_query` handle form-encoded conversion separately
- `userinfo` includes password for backward compatibility but is documented as deprecated per RFC 3986 §3.2.1
- `encode_component` encodes everything except unreserved characters `[A-Za-z0-9_.~-]` per RFC 3986 §2.3
- `with_*` helpers return new `Uri` with one field changed (records are immutable)
- `parse` handles: `scheme://[userinfo@]host[:port]/path[?query][#fragment]`
- `parse_query` handles: key-value pairs separated by `&`/`;`, with percent-decoding of both keys and values

**Pure Camp implementation sketch for `encode_component`**:
```camp
encode_component = fn s -> {
  s->to_iter()
   ->map(fn c -> {
     if is_unreserved(c) { Str.from_char(c) }
     else { "%" ++ hex_encode(c) }
   })
   ->Str.join()
}
// where is_unreserved matches [A-Za-z0-9_.~-]
// and hex_encode converts byte to two-digit uppercase hex
```

### 6. Base64

```camp
// Base64.camp — NEW — all pure Camp
@Base64Format : pub [Standard | UrlSafe | Base32 | Hex]

@Base64Err : pub [
    InvalidChar(U64, Str)                       // position + bad character
  | InvalidLength
  | InvalidPadding
]

// Core encode/decode (parameterized)
encode     : Base64Format, Bytes -> Str
decode     : Base64Format, Str -> Result(Bytes, Base64Err)

// String convenience (UTF-8 encode/decode internally)
encode_str : Base64Format, Str -> Str
decode_str : Base64Format, Str -> Result(Str, Base64Err)

// Format-specific shorthands
encode64     : Bytes -> Str                     // Standard Base64
decode64     : Str -> Result(Bytes, Base64Err)
encode64url  : Bytes -> Str                     // URL-safe Base64
decode64url  : Str -> Result(Bytes, Base64Err)
encode16     : Bytes -> Str                     // Hex, lowercase
decode16     : Str -> Result(Bytes, Base64Err)
```

**Design notes**:
- Pure Camp — lookup table + bit shifting, no C runtime needed
- `Standard`: RFC 4648 Base64 with `A-Za-z0-9+/` and `=` padding
- `UrlSafe`: RFC 4648 Base64url with `A-Za-z0-9-_` and no padding
- `Base32`: RFC 4648 Base32 with `A-Z2-7` and `=` padding
- `Hex`: lowercase hex `0-9a-f` (Base16)
- `decode_str` returns `Result(Str, Base64Err)` — invalid UTF-8 after decoding is an error, not silent replacement

**Pure Camp implementation structure**:
```camp
// Each format has an alphabet and padding rule
@Base64Alphabet : pub { chars : Str, pad : Bool }

standard_alphabet : Base64Alphabet = { chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", pad: True }
urlsafe_alphabet  : Base64Alphabet = { chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", pad: False }
base32_alphabet   : Base64Alphabet = { chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", pad: True }
hex_alphabet      : Base64Alphabet = { chars: "0123456789abcdef", pad: False }

encode = fn fmt, bytes -> {
  alphabet = alphabet_for(fmt)
  // Group bytes: 3 bytes -> 4 Base64 chars (6 bits each)
  // Or 5 bytes -> 8 Base32 chars (5 bits each)
  // Or 1 byte -> 2 hex chars (4 bits each)
  // Apply alphabet lookup, add padding if configured
}
```

## Module Registry Updates

| Module | File | Category | Pure/Intrinsic |
|--------|------|----------|---------------|
| Random! | Random.camp | Effect | Modified (add bytes!, random_crypto) |
| Uuid | Uuid.camp | Type + Functions | Mixed (generation intrinsic, parse/format pure) |
| Json | Json.camp | Type + Functions | Intrinsic (parsing/encoding) + Pure (accessors) |
| Regex | Regex.camp | Type + Functions | Intrinsic (engine) + Pure (escape) |
| Uri | Uri.camp | Type + Functions | Pure Camp |
| Base64 | Base64.camp | Functions | Pure Camp |

## Dependency Graph

```
Random! (existing, modified)
    ↑
    |
   Uuid (v4!/v7! need Random!)

Json    (standalone — Str, List, Map, Result)
Regex   (standalone — Str, List, Result)
Uri     (standalone — Str, Result)
Base64  (standalone — Bytes, Str, Result)
```

## Design Decision Register

| ID | Decision | Choice | Tradeoff |
|----|----------|--------|----------|
| D31 | Random! vs Crypto.Random! | One effect + two handlers | No type-level crypto guarantee; handler determines security |
| D32 | Random! bytes! operation | Add to existing Random! | Slight API expansion of P1 module |
| D33 | Crypto.Random! as separate module | Eliminated | Folded into Random! handler |
| D34 | Json Obj representation | Map(Str, JsonValue) | O(log n) lookup; loses insertion order, deduplicates keys |
| D35 | Json number type | JsonNumber [PosInt\|NegInt\|Float] | Preserves int/float distinction; adds type complexity |
| D36 | Uri query storage | Raw Option(Str) + parse_query helper | Preserves original encoding; parsed access is opt-in |
| D37 | Regex engine class | RE2-style (no backtracking) | Safe against ReDoS; no backreferences/lookahead |
| D38 | Uuid generation effect | Random! only | Simpler API; crypto choice at handler level |
| D39 | Base64 API shape | Parameterized + shorthands | More API surface; convenience for common cases |

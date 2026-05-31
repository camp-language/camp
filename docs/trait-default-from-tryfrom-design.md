# Default, From, TryFrom Trait Design

## 1. Default Trait

### Definition

```camp
Default : {
  default : || -> Self,
}
```

Zero-arg function returning a canonical "default" value for the type. No value-typed fields in traits — all trait fields are pure functions per generics-traits-spec.

### Implementations

| Type | Default | Note |
|------|---------|------|
| `I8`, `I16`, `I32`, `I64` | `0` | Intrinsic |
| `U8`, `U16`, `U32`, `U64` | `0` | Intrinsic |
| `F32`, `F64` | `0.0` | Intrinsic |
| `Bool` | `False` | Pure Camp |
| `Char` | `'\0'` | Null character |
| `Str` | `""` | Empty string, intrinsic |
| `Bytes` | empty byte array | Intrinsic |
| `List(a)` | `[]` | Pure Camp |
| `Map(k, v)` | empty map | Intrinsic |
| `Set(a)` | empty set | Intrinsic |
| `Path` | `Path.new(".")` | Intrinsic |
| `Duration` | `Duration.zero` | Intrinsic |
| `Uri` | empty URI | Intrinsic |
| `Uuid` | nil UUID (all zeros) | Intrinsic |
| `Json` | `Json.Null` | Pure Camp — record with Null |
| `Result(a, e)` | **No impl** | `unwrap_or_default` exists as method |

### Call Pattern

```camp
I64.default()      // -> I64 = 0
Bool.default()     // -> Bool = False
Default.default    // Error — default is a fn, call it
```

Default is NOT derivable via `derives`. It is manually implemented per type.

### No Blanket Impls

No `where a is Default` conditionals for now. `List`, `Map`, `Set` have fixed empty defaults regardless of element type. `Result` has no Default impl (use `unwrap_or_default`).

---

## 2. From Trait

### Definition

```camp
From : {
  from : |source| -> Self,
}
```

The `source` type variable is unbound in the trait — it resolves at impl site via structural signature check. The trait defines that the implementing type (`Self`) can be created from `source` without error.

### Semantics

- **Lossless only**: `From` impls must be infallible and lossless (no truncation, no rounding, no information loss)
- **No runtime cost**: monomorphized to direct WASM operations
- **Idempotent**: `From.from` on a value that's already the target type is identity

### Numeric From Implementations

**Rule**: Only lossless conversions. Source range must fit entirely within target range.

#### Unsigned → Unsigned
| Source | Targets |
|--------|---------|
| `U8` | U16, U32, U64, F32, F64 |
| `U16` | U32, U64, F64 |
| `U32` | U64, F64 |
| `U64` | *(none — no larger fixed-width type)* |

#### Signed → Signed
| Source | Targets |
|--------|---------|
| `I8` | I16, I32, I64, F32, F64 |
| `I16` | I32, I64, F64 |
| `I32` | I64, F64 |
| `I64` | *(none)* |

#### Unsigned → Signed
| Source | Targets | Note |
|--------|---------|------|
| `U8` | I16, I32, I64 | Both ranges fit. U8 max 255 < I16 max 32767 |
| `U16` | I32, I64 | U16 max 65535 fits in I32/I64 |
| `U32` | I64 | U32 max 4B fits in I64 |

**Banned**: `U32 → I32` (lossy for values > 2B). `U64 → I64` (lossy).

#### Integer → Float
| Source | Float targets | Note |
|--------|--------------|------|
| `U8` | F32, F64 | 8 bits ≤ 24/53 mantissa |
| `U16` | F64 | 16 bits ≤ 53 mantissa, but **not** F32 (24-bit mantissa insufficient for 65535 with exact precision — actually 65535 < 2^24 = 16777216, so it DOES fit losslessly) |
| `U32` | F64 | 32 bits ≤ 53 mantissa |
| `I8` | F32, F64 | 8 bits |
| `I16` | F64 | 16 bits fits 53, and also fits 24 → F32 is fine (32768 < 16777216) |
| `I32` | F64 | 32 bits ≤ 53 |

**Precise**: I16→F32 IS lossless (max abs 32768 < 2^24 = 16777216). U16→F32 IS lossless (65535 < 16777216). Both good.

**Not lossless**: U32→F32 (4B > 24-bit mantissa). I32→F32 (2B > 24-bit mantissa). U64→F64 (64 > 53-bit mantissa). I64→F64 (64 > 53-bit mantissa). These go through TryFrom.

#### Float → Float
| Source | Target | Note |
|--------|--------|------|
| `F32` | F64 | Always exact |

**Not lossless**: F64→F32 (overflow, precision loss). Goes through TryFrom.

#### Bool → All Numerics
| Source | Targets |
|--------|---------|
| `Bool` | All 10 numeric types + both floats |

`false` → `0`, `true` → `1`. Always lossless.

### Non-Numeric From Implementations

| Source | Target | Mechanism |
|--------|--------|-----------|
| `Str` | `Bytes` | UTF-8 bytes — infallible |
| `Str` | `Path` | Path from string |
| `Str` | `Uri` | URI from string string — actually questionable for infallible. Skip — use TryFrom |
| `Uuid` | `Str` | Uuid.to_str() |
| `Uuid` | `Bytes` | Uuid.to_bytes() |
| `Str` | `Json` | Use TryFrom (parse can fail) |

Actually re-examining: `Str → Uri` can fail on invalid URIs. So TryFrom only. Similarly `Str → Path` — actually paths are opaque byte sequences in WASM, construction from arbitrary string doesn't fail (invalid UTF-8 handled by runtime). So Str→Path is From.

### Call Pattern

```camp
// Qualified trait dispatch:
From.from(val: U8): I64

// Through inference:
let x: I64 = From.from(u8_val)

// No UFCS method from trait (no self access for From)
```

---

## 3. TryFrom Trait

### Definition

```camp
TryFrom : {
  try_from : |source| -> Result(Self, e),
}
```

`source` is unbound in trait, resolved at impl site. `e` is the error type, chosen by the implementor. Caller pattern-matches on the `Result`.

### Error Types

Each impl picks its own error. No shared enum.

| Conversion | Error Type |
|-----------|-----------|
| Numeric narrowing (e.g. I64→I32) | `TryFromIntError` (zero-payload opaque) |
| Str→I64, Str→I32, Str→F64, etc. | `ParseError(Str)` |
| Str→Uuid | `UuidErr` |
| Str→Regex | `RegexErr` |
| Str → Json | `JsonErr` |
| Bytes→Str | `[InvalidUtf8]` |

**`TryFromIntError` definition** (lives in prelude or a dedicated file):
```camp
// Intrinsic — compiler knows about it for numeric narrowing
@TryFromIntError : { value_out_of_range: {} }
```

Actually simpler: `TryFromIntError` is a zero-payload nominal type with `Debug`:

```camp
@TryFromIntError : {}   // opaque zero-size marker
```

### Numeric TryFrom Implementations

**All narrowing conversions that can overflow.** Follows Rust patterns:

#### Unsigned → Unsigned (narrowing)
| Source | Target | Bound check |
|--------|--------|------------|
| `U16` | `U8` | upper |
| `U32` | `U8, U16` | upper |
| `U64` | `U8, U16, U32` | upper |

#### Signed → Signed (narrowing)
| Source | Target | Bound check |
|--------|--------|------------|
| `I16` | `I8` | both |
| `I32` | `I8, I16` | both |
| `I64` | `I8, I16, I32` | both |

#### Unsigned → Signed (narrowing)
| Source | Target | Bound check |
|--------|--------|------------|
| `U8` | `I8` | upper |
| `U16` | `I8, I16` | upper |
| `U32` | `I8, I16, I32` | upper |
| `U64` | `I8, I16, I32, I64` | upper |

#### Signed → Unsigned (narrowing)
| Source | Target | Bound check |
|--------|--------|------------|
| `I8` | `U8, U16, U32, U64` | lower |
| `I16` | `U8` | both |
| `I16` | `U16, U32, U64` | lower |
| `I32` | `U8, U16` | both |
| `I32` | `U32, U64` | lower |
| `I64` | `U8, U16, U32` | both |
| `I64` | `U64` | lower |

#### Float Narrowing
| Source | Target | Check |
|--------|--------|-------|
| `F64` | `F32` | overflow + infinity |
| `F64` | `I64, I32` | overflow + fraction |
| `F32` | `I32, I16, I8` | overflow + fraction |

### String Parsing TryFrom

| Target | Error | Note |
|--------|-------|------|
| `I64` | `ParseError(Str)` | `Str.to_i64` |
| `I32` | `ParseError(Str)` | via I64 then TryFrom |
| `I16` | `ParseError(Str)` | via I64 then TryFrom |
| `I8` | `ParseError(Str)` | via I64 then TryFrom |
| `U64` | `ParseError(Str)` | intrinsic |
| `U32` | `ParseError(Str)` | via U64 then TryFrom |
| `U16` | `ParseError(Str)` | via U64 then TryFrom |
| `U8` | `ParseError(Str)` | via U64 then TryFrom |
| `F64` | `ParseError(Str)` | `Str.to_f64` |
| `F32` | `ParseError(Str)` | via F64 then TryFrom |

**Question**: Should TryFrom for Str→I64 use `Str.to_i64` (which returns `Result(I64, [InvalidFormat])`) or does the TryFrom impl use the intrinsic directly? The TryFrom impl wraps the existing function:

```camp
I64 is TryFrom {
  try_from = |s: Str| -> Result(I64, ParseError) {
    match Str.to_i64(s) {
      Ok(v) => Ok(v)
      Err(_) => Err(ParseError("Invalid integer format"))
    }
  }
}
```

### Non-Numeric TryFrom

| Source | Target | Error |
|--------|--------|-------|
| `Str` | `Regex` | `RegexErr` |
| `Str` | `Uuid` | `UuidErr` |
| `Str` | `Uri` | `UriErr` |
| `Str` | `Json` | `JsonErr` |
| `Bytes` | `Str` | `InvalidUtf8` |

### Call Pattern

```camp
// Qualified:
TryFrom.try_from(big_val: I64): Result(I32, TryFromIntError)

// With pattern matching:
match TryFrom.try_from(val) {
  Ok(narrowed) => use_narrowed(narrowed)
  Err(_) => handle_overflow()
}
```

---

## 4. Interaction with Prelude / Modular Structure

All three traits are defined in their own module files:

- `stdlib/Default.camp` — trait definition
- `stdlib/From.camp` — trait definition
- `stdlib/TryFrom.camp` — trait definition

Implementations go in the implementing type's module (orphan rule):

- Numeric impls → `stdlib/Num/I8.camp`, `stdlib/Num/U32.camp`, etc.
- Bool impls → `stdlib/Bool.camp`
- Str impls → `stdlib/Str.camp`
- Bytes impls → `stdlib/Bytes.camp`
- Collection impls → `stdlib/List.camp`, `stdlib/Map.camp`, `stdlib/Set.camp`
- Etc.

---

## 5. Error Type Definitions

```camp
// In stdlib/TryFromIntError.camp (new file):
@TryFromIntError : {}

// In stdlib/ParseError.camp (new file):
@ParseError : pub Str
```

---

## 6. Compiler Changes Required

### Intrinsic Default Support
Add compiler awareness of `Default.default` for known numeric types. When `I64 is Default { default = || -> I64 { 0 } }` is encountered, compiler recognizes the constant `0` and can optimize.

### Intrinsic From/TryFrom Support
Numeric From/TryFrom impls use `crash "intrinsic: ..."` markers. The compiler recognizes these during codegen and emits direct WASM instructions (`i64.extend_i32_u` for widening, range-check-then-truncate for narrowing).

### TryFromIntError Awareness
Compiler recognizes `@TryFromIntError` and knows how to construct it during narrowing overflow checks.

---

## 7. Not Included (Future Work)

- `TryInto` — symmetric version of TryFrom (add when needed)
- `Into` — symmetric version of From (add when needed)
- Blanket impl: `From` implies infallible `TryFrom` with `e = Infallible`
- `TryFrom<Str>` for more types (Date, Time, etc.)
- Platform-specific numeric conversions (usize/isize)

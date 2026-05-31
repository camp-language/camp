# Implementation Plan: Default, From, TryFrom

## Overview

Implement three stdlib traits (`Default`, `From`, `TryFrom`) across all stdlib types. All impls use `crash "intrinsic: ..."` markers where runtime support is needed — the compiler recognizes these strings during codegen.

**Key constraint**: No dynamic dispatch. All trait dispatch resolves at monomorphization time.

---

## File Inventory

### New files to create
1. `stdlib/TryFromIntError.camp` — zero-payload error marker type
2. `stdlib/ParseError.camp` — parse error type

### Files to modify
1. `stdlib/Default.camp` — update trait sig: `default : Self` → `default : || -> Self`
2. `stdlib/From.camp` — update trait sig: `from : |Self| -> target` → `from : |source| -> Self`
3. `stdlib/TryFrom.camp` — update trait sig: `try_from : |Self| -> Result(target, e)` → `try_from : |source| -> Result(Self, e)`
4. `stdlib/Bool.camp` — add Default, From (to all numerics)
5. `stdlib/Str.camp` — add Default, From (to Bytes, Path), TryFrom (to I64, F64, Uuid, Regex)
6. `stdlib/Bytes.camp` — add Default, TryFrom (to Str)
7. `stdlib/Uuid.camp` — add Default, TryFrom (from Str)
8. `stdlib/Uri.camp` — add Default
9. `stdlib/Path.camp` — add Default
10. `stdlib/Duration.camp` — add Default
11. `stdlib/Json.camp` — add Default, TryFrom (from Str)
12. `stdlib/Regex.camp` — add TryFrom (from Str)
13. `stdlib/Num/I8.camp` — add Default, From (I8→I16/I32/I64/F32/F64), TryFrom (I64→I8, etc.)
14. `stdlib/Num/I16.camp` — add Default, From (I16→I32/I64/F64), TryFrom
15. `stdlib/Num/I32.camp` — add Default, From (I32→I64/F64), TryFrom
16. `stdlib/Num/I64.camp` — add Default, TryFrom
17. `stdlib/Num/U8.camp` — add Default, From (U8→all larger), TryFrom
18. `stdlib/Num/U16.camp` — add Default, From (U16→U32/U64/F64), TryFrom
19. `stdlib/Num/U32.camp` — add Default, From (U32→U64/F64), TryFrom
20. `stdlib/Num/U64.camp` — add Default, TryFrom
21. `stdlib/Num/F32.camp` — add Default, From (F32→F64), TryFrom
22. `stdlib/Num/F64.camp` — add Default, TryFrom

---

## Step 1: Error types

### `stdlib/TryFromIntError.camp`
```camp
// TryFromIntError.camp — zero-payload error for numeric narrowing failures
@TryFromIntError : {}
TryFromIntError is Debug {
  debug = |self| -> Str { crash "intrinsic: TryFromIntError_debug" }
}
```

### `stdlib/ParseError.camp`
```camp
// ParseError.camp — string parse failure
@ParseError : pub Str
ParseError is Debug {
  debug = |self: Self| -> Str { crash "intrinsic: ParseError_debug" }
}
```

---

## Step 2: Update trait definitions

### `stdlib/Default.camp`
```camp
Default : {
  default : || -> Self,
}
```

### `stdlib/From.camp`
```camp
From : {
  from : |source| -> Self,
}
```

### `stdlib/TryFrom.camp`
```camp
TryFrom : {
  try_from : |source| -> Result(Self, e),
}
```

---

## Step 3: Default implementations

### Pattern for numeric types
Each numeric type gets:
```camp
I8 is Default {
  default = || -> I8 { crash "intrinsic: I8_default" }
}
```

### Pattern for Bool (pure Camp impl)
```camp
Bool is Default {
  default = || -> Bool { False }
}
```

### Pattern for collections (empty)
```camp
List(a) is Default {
  default = || -> List(a) { [] }
}
Map(k, v) is Default {
  default = || -> Map(k, v) { crash "intrinsic: Map_new" }
}
Set(a) is Default {
  default = || -> Set(a) { crash "intrinsic: Set_new" }
}
```

### Str
```camp
Str is Default {
  default = || -> Str { crash "intrinsic: Str_default" }  // returns ""
}
```

### Bytes
```camp
Bytes is Default {
  default = || -> Bytes { crash "intrinsic: Bytes_new" }  // returns empty
}
```

### Path, Duration, Uri, Uuid, Json
```camp
Path is Default {
  default = || -> Path { Path.new(".") }
}
Duration is Default {
  default = || -> Duration { crash "intrinsic: Duration_zero" }
}
Uri is Default {
  default = || -> Uri { crash "intrinsic: Uri_default" }
}
Uuid is Default {
  default = || -> Uuid { crash "intrinsic: Uuid_nil" }
}
Json is Default {
  default = || -> Json { Json.Null }
}
```

---

## Step 4: From implementations

### Numeric From — unsigned widening
```camp
U8 is From {
  from = |val: U8| -> U16 { crash "intrinsic: U8_to_U16" }
}
U8 is From {
  from = |val: U8| -> U32 { crash "intrinsic: U8_to_U32" }
}
U8 is From {
  from = |val: U8| -> U64 { crash "intrinsic: U8_to_U64" }
}
U8 is From {
  from = |val: U8| -> F32 { crash "intrinsic: U8_to_F32" }
}
U8 is From {
  from = |val: U8| -> F64 { crash "intrinsic: U8_to_F64" }
}
U16 is From {
  from = |val: U16| -> U32 { crash "intrinsic: U16_to_U32" }
}
U16 is From {
  from = |val: U16| -> U64 { crash "intrinsic: U16_to_U64" }
}
U16 is From {
  from = |val: U16| -> F64 { crash "intrinsic: U16_to_F64" }
}
U32 is From {
  from = |val: U32| -> U64 { crash "intrinsic: U32_to_U64" }
}
U32 is From {
  from = |val: U32| -> F64 { crash "intrinsic: U32_to_F64" }
}
```

### Numeric From — signed widening
```camp
I8 is From {
  from = |val: I8| -> I16 { crash "intrinsic: I8_to_I16" }
}
I8 is From {
  from = |val: I8| -> I32 { crash "intrinsic: I8_to_I32" }
}
I8 is From {
  from = |val: I8| -> I64 { crash "intrinsic: I8_to_I64" }
}
I8 is From {
  from = |val: I8| -> F32 { crash "intrinsic: I8_to_F32" }
}
I8 is From {
  from = |val: I8| -> F64 { crash "intrinsic: I8_to_F64" }
}
I16 is From {
  from = |val: I16| -> I32 { crash "intrinsic: I16_to_I32" }
}
I16 is From {
  from = |val: I16| -> I64 { crash "intrinsic: I16_to_I64" }
}
I16 is From {
  from = |val: I16| -> F64 { crash "intrinsic: I16_to_F64" }
}
I32 is From {
  from = |val: I32| -> I64 { crash "intrinsic: I32_to_I64" }
}
I32 is From {
  from = |val: I32| -> F64 { crash "intrinsic: I32_to_F64" }
}
```

### Numeric From — unsigned → signed widening
```camp
U8 is From {
  from = |val: U8| -> I16 { crash "intrinsic: U8_to_I16" }
}
U8 is From {
  from = |val: U8| -> I32 { crash "intrinsic: U8_to_I32" }
}
U8 is From {
  from = |val: U8| -> I64 { crash "intrinsic: U8_to_I64" }
}
U16 is From {
  from = |val: U16| -> I32 { crash "intrinsic: U16_to_I32" }
}
U16 is From {
  from = |val: U16| -> I64 { crash "intrinsic: U16_to_I64" }
}
U32 is From {
  from = |val: U32| -> I64 { crash "intrinsic: U32_to_I64" }
}
```

### Bool → all numeric
```camp
Bool is From {
  from = |val: Bool| -> I8 { crash "intrinsic: Bool_to_I8" }
}
Bool is From {
  from = |val: Bool| -> I16 { crash "intrinsic: Bool_to_I16" }
}
Bool is From {
  from = |val: Bool| -> I32 { crash "intrinsic: Bool_to_I32" }
}
Bool is From {
  from = |val: Bool| -> I64 { crash "intrinsic: Bool_to_I64" }
}
Bool is From {
  from = |val: Bool| -> U8 { crash "intrinsic: Bool_to_U8" }
}
Bool is From {
  from = |val: Bool| -> U16 { crash "intrinsic: Bool_to_U16" }
}
Bool is From {
  from = |val: Bool| -> U32 { crash "intrinsic: Bool_to_U32" }
}
Bool is From {
  from = |val: Bool| -> U64 { crash "intrinsic: Bool_to_U64" }
}
Bool is From {
  from = |val: Bool| -> F32 { crash "intrinsic: Bool_to_F32" }
}
Bool is From {
  from = |val: Bool| -> F64 { crash "intrinsic: Bool_to_F64" }
}
```

### Float → Float
```camp
F32 is From {
  from = |val: F32| -> F64 { crash "intrinsic: F32_to_F64" }
}
```

### Non-numeric From
```camp
Str is From {
  from = |val: Str| -> Bytes { Str.to_bytes(val) }
}
Str is From {
  from = |val: Str| -> Path { Path.new(val) }
}
Uuid is From {
  from = |val: Uuid| -> Str { Uuid.to_str(val) }
}
Uuid is From {
  from = |val: Uuid| -> Bytes { Uuid.to_bytes(val) }
}
```

---

## Step 5: TryFrom implementations

### Numeric narrowing — pattern
For each narrowing pair, use the intrinsic version:
```camp
I64 is TryFrom {
  try_from = |val: I64| -> Result(I32, TryFromIntError) {
    crash "intrinsic: I64_try_into_I32"
  }
}
```

The intrinsic checks range: `val >= I32.MIN and val <= I32.MAX`, returns `Err(TryFromIntError)` on failure.

### Full matrix of narrowing TryFrom impls

| Source | Target(s) | Type |
|--------|----------|------|
| U16 | U8 | upper-only |
| U32 | U8, U16 | upper-only |
| U64 | U8, U16, U32 | upper-only |
| I16 | I8 | both |
| I32 | I8, I16 | both |
| I64 | I8, I16, I32 | both |
| U8 | I8 | upper-only |
| U16 | I8, I16 | upper-only |
| U32 | I8, I16, I32 | upper-only |
| U64 | I8, I16, I32, I64 | upper-only |
| I8 | U8, U16, U32, U64 | lower-only |
| I16 | U8 | both |
| I16 | U16, U32, U64 | lower-only |
| I32 | U8, U16 | both |
| I32 | U32, U64 | lower-only |
| I64 | U8, U16, U32 | both |
| I64 | U64 | lower-only |
| F64 | F32 | overflow check |
| F64 | I64, I32 | overflow + truncation |
| F32 | I32, I16, I8 | overflow + truncation |

### String → numeric (via existing to_* functions)
```camp
I64 is TryFrom {
  try_from = |s: Str| -> Result(I64, ParseError) {
    match Str.to_i64(s) {
      Ok(v) => Ok(v)
      Err(_) => Err(ParseError("Invalid integer format"))
    }
  }
}
F64 is TryFrom {
  try_from = |s: Str| -> Result(F64, ParseError) {
    match Str.to_f64(s) {
      Ok(v) => Ok(v)
      Err(_) => Err(ParseError("Invalid float format"))
    }
  }
}
```

### Str → Regex
```camp
Regex is TryFrom {
  try_from = |s: Str| -> Result(Regex, RegexErr) {
    Regex.compile(s)
  }
}
```

### Str → Json
```camp
Json is TryFrom {
  try_from = |s: Str| -> Result(Json, JsonErr) {
    Json.decode(s)
  }
}
```

### Str → Uuid
```camp
Uuid is TryFrom {
  try_from = |s: Str| -> Result(Uuid, UuidErr) {
    Uuid.parse(s)
  }
}
```

### Bytes → Str
```camp
Str is TryFrom {
  try_from = |b: Bytes| -> Result(Str, InvalidUtf8) {
    Bytes.to_str(b)
  }
}
```

---

## Step 6: Compiler intrinsic naming convention

All `crash "intrinsic: ..."` strings follow this format:

- **Default**: `{Type}_default` (e.g. `I64_default`, `Str_default`)
- **From**: `{Source}_to_{Target}` (e.g. `U8_to_I16`, `Bool_to_I64`)
- **TryFrom**: `{Source}_try_into_{Target}` (e.g. `I64_try_into_I32`)

### Compiler codegen notes

For intrinsic `Default` of numeric types: just emit the constant 0/0.0.
For intrinsic `From` of numeric widening: emit the appropriate WASM extend/convert instruction.
For intrinsic `TryFrom` of numeric narrowing: emit a range check branch followed by convert.

---

## Step 7: Testing

After all impls, update kitchen-sink test to exercise:
1. `Default.default()` on each type
2. `From.from()` for each widening pair
3. `TryFrom.try_from()` for narrowing (success + failure cases)
4. Error type construction and pattern matching

---

## Step 8: Spec updates

Update `docs/generics-traits-spec.md` if needed (no — trait definitions unchanged, only impls added).

No spec changes needed if the trait signatures are already compatible. The design doc in `docs/trait-default-from-tryfrom-design.md` is the reference.

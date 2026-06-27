---
# camp-lh35
title: Encode/Decode trait design and implementation
status: blocked
type: task
priority: normal
tags:
    - traits
    - stdlib
    - codec
blocked_by:
    - method generics (language feature)
created_at: 2026-06-22T02:24:34Z
updated_at: 2026-06-22T02:24:34Z
---

## Problem

Camp needs encode/decode traits for serialization. The design is sketched in `docs/stdlib-design-notes.md` (D26, Q11) but marked "tentative" because it requires method generics that don't exist yet.

## Design (from D26 + Q11)

**Traits:**
```
Encode(a, f) : {
  encode : (a, Encoder(f)) -> Encoder(f)
}

Decode(a, f) : {
  decode : (Decoder(f)) -> Result(a, [DecodeError])
}
```

Both are multi-param traits with format parameter `f`. The multi-param trait infrastructure is now in place (camp-3ojo).

**Format backend traits:**
```
EncoderFormatting(f) : {
  u8, i64, f64, bool, string, list, record, tag : ...
}

DecoderFormatting(f) : {
  u8, i64, f64, bool, string, list, record : ...
}
```

**Error type:**
```
@DecodeError : [TooShort | Leftover(Bytes) | InvalidFormat(Str) | MissingField(Str) | TypeMismatch(Str, Str)]
```

**Decoder combinators:** map, then, one_of, field, optional, list, custom.

## Why blocked

The design requires method generics to write format-agnostic code. Without them, you can't write a single `encode` function that works across all format backends. Roc-style fully format-agnostic encoding requires the format parameter to be generic at the method level, which Camp's trait system doesn't support yet.

## What CAN be done now

1. The multi-param trait infrastructure (camp-3ojo) supports Encode/Decode's trait shape
2. Format-specific impls (e.g., `Json is Encode(MyType, JsonFormat)`) can be written
3. The `Encoder(f)` / `Decoder(f)` / `EncoderFormatting(f)` / `DecoderFormatting(f)` types can be designed and implemented
4. `DecodeError` newtype can be defined

## What CANNOT be done now

- Generic `encode : (a, Encoder(f)) -> Encoder(f)` where `f` is a type parameter resolved at call site
- Format-agnostic combinators that work across all backends
- `derives Encode, Decode` auto-impl generation (needs method generics for the recursive encode/decode calls)

## Next steps

1. Wait for method generics to be added to the language
2. Then implement: prelude injection for Encode/Decode, EncoderFormatting/DecoderFormatting traits, DecodeError newtype, Json module with concrete impls

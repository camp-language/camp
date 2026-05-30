---
id: camp-9m0n
title: Implement Hash trait for stdlib types
status: todo
type: task
priority: low
created_at: 2026-05-30T16:29:00Z
updated_at: 2026-05-30T16:29:00Z
---

Stdlib defines `Hash : { hash : |Self, Hasher| -> Hasher }` in `stdlib/Hash.camp`.
No types implement it. `Hash` is needed for HashMap/HashSet keys and consistent hashing.

Depends on `Hasher` type being defined (likely a stateful hash accumulator type).

Types needing impls:
- Bool: hash 0 or 1
- All Num types: hash the in-memory representation
- Str: hash string bytes (stable hash, e.g. FNV-1a or SipHash)
- Bytes: hash byte sequence
- List(T): hash each element in order, combine with Hasher — requires T: Hash
- Result(T, E): hash variant tag then payload
- Map(K, V): hash sorted keys then values (order-independent hash)
- Set(T): hash elements (order-independent, e.g. XOR)
- Path: hash string representation
- Uri: hash string representation
- Uuid: hash 16 bytes
- Duration: hash nanosecond count
- Regex: hash pattern string

Requires `Hasher` type definition and its interface before impls can be written.

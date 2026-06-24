---
# camp-3q0j
title: Add stdlib test coverage for untested modules (Base64, Bytes, Char, Console, Duration, Env, File, Fmt, Iter, Json, List, Log, Map, Ord, Path, Random, Regex, Result, Set, Str, Throw, Time, Uri, Uuid, ParseError)
status: todo
type: task
priority: low
tags:
    - stdlib
    - testing
created_at: 2026-06-24T04:27:11Z
updated_at: 2026-06-24T04:27:11Z
---

Source: stdlib coverage sweep. Only stdlib/Bool.camp has test blocks (1 block). All other 35 modules have ZERO test blocks. This violates AGENTS.md Stdlib Testing coverage requirement ("Zero tests = untested module").

Modules needing tests (excluding those already covered by existing beans): camp-r33l covers U16/U32/U64/F32/F64/Str/Bytes/Map/Set (partial). camp-d3k3 covers Display impls. Remaining untested:
Base64, Char, Console, Duration, Env, File, Fmt, Iter, Json, List, Log, Ord, Path, Random, Regex, Result, Set, Throw, Time, Uri, Uuid, ParseError, Hash, From, FromIter, IntoIter, TryFrom, TryFromIntError, Default, Debug.

Add test blocks per AGENTS.md principles: one concern per test, boundary-first, order happy→empty→singleton→multi→error→identity. Prefer pure Camp tests. One bean covers the whole sweep but may be split into child beans per cluster (collections I/O, parsing, effects, traits).

Done: every stdlib/*.camp has >=3 test blocks (or is explicitly documentation-only per its parent implementation bean). just check passes.

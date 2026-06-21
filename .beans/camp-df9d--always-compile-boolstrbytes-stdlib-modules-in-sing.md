---
# camp-df9d
title: Always-compile Bool/Str/Bytes stdlib modules in single-file builds
status: todo
type: task
priority: normal
tags:
    - codegen
    - traits
    - stdlib
created_at: 2026-06-21T05:09:00Z
updated_at: 2026-06-21T05:09:00Z
---

Decision A (camp-24mj) currently only always-compiles Char.camp. Bool, Str, and Bytes modules cause wasm validation errors (type mismatch: values remaining on stack at end of block) when always-compiled. The issue is likely in how their trait impl bodies (Ord.compare returning Order, Hash.hash returning Hasher, etc.) are lowered to IR and then to wasm. Need to debug the wasm validation errors and expand ALWAYS_COMPILE in build.odin to include Bool, Str, and Bytes (and eventually Num/* modules). Once all primitive modules are always-compiled, the hand-written Bool_Compare/I64_compare intrinsics in codegen/runtime.odin can be removed.

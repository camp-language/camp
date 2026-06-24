---
# camp-j3u9
title: Trait-impl lowering silently skips unregistered impls (lower.odin returns nil, produces no diagnostic)
status: todo
type: bug
priority: high
tags:
    - codegen
    - typecheck
created_at: 2026-06-24T04:27:22Z
updated_at: 2026-06-24T04:27:22Z
---

Source: error-path sweep. src/ir/lower.odin:736-737 — trait-impl lowering returns nil silently when an impl was not registered (comment: "the conformance check already silently skipped the impl"). From/TryFrom impls not in prelude vanish without telling the user. This is a silent gap: a user writes a trait impl, it is skipped at conformance, and again at lowering, with no error — the methods simply disappear.

Done: when a trait impl is skipped, emit a diagnostic (e.g. C0603 missing trait method, or an "impl not registered" internal error with span) rather than silently returning nil. E2E test: an orphan/skipped impl produces a compile error, not silent method erasure.

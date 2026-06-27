---
# camp-335w
title: Implement real stdlib trait bodies for Debug, Display, Eq, Hash (currently type-only stubs)
status: todo
type: task
priority: low
tags:
    - stdlib
    - traits
created_at: 2026-06-24T04:27:11Z
updated_at: 2026-06-24T04:27:11Z
---

Source: stdlib coverage sweep. These modules are 4-7 line type declarations with no impl bodies:
- stdlib/Debug.camp (5L): only declares Debug trait { debug: |Self| -> Str }
- stdlib/Display.camp (4L): only declares Display { to_str }
- stdlib/Eq.camp (5L): only declares Eq { eq }
- stdlib/Hash.camp (8L): only declares Hasher [@Hasher:{} empty] + Hash { hash }

These are trait *declarations* (interfaces), not impl modules — clarify whether this is intended (impls live elsewhere, e.g. camp-d3k3 for Display primitives) or whether canonical impls should live here. If intended, add a comment marking doc-only. If impls belong here, add them per stdlib-design-notes.

Done: each module either marked explicitly documentation-only with rationale, or contains real impls + test blocks. No ambiguous stubs.

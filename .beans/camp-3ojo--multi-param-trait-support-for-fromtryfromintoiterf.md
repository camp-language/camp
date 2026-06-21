---
# camp-3ojo
title: Multi-param trait support for From/TryFrom/IntoIter/FromIter
status: todo
type: task
priority: normal
tags:
    - traits
    - type-system
created_at: 2026-06-21T05:09:30Z
updated_at: 2026-06-21T05:09:30Z
---

From, TryFrom, IntoIter, and FromIter are multi-param traits (e.g. From(source, target)) whose stdlib impls are written as 'Source is From { from = ... }' which does not match the current conformance model (param[0] is Self). The prelude does not inject these trait declarations (only Eq and Default are injected). Their 74 stdlib impls across 16 files are silently skipped during conformance (camp-24mj fix). Properly supporting them requires: (1) a multi-param trait dispatch design with applied constructors, (2) param-position rework in verify_trait_conformance, (3) Stdlib impl syntax changes to match the new model. Currently blocked on design decisions for multi-param traits.

---
# camp-j3u9
title: Trait-impl lowering silently skips unregistered impls (lower.odin returns nil, produces no diagnostic)
status: completed
type: bug
priority: high
tags:
    - codegen
    - typecheck
created_at: 2026-06-24T04:27:22Z
updated_at: 2026-06-27T03:21:31Z
---

Source: error-path sweep. src/ir/lower.odin:736-737 — trait-impl lowering returns nil silently when an impl was not registered (comment: "the conformance check already silently skipped the impl"). From/TryFrom impls not in prelude vanish without telling the user. This is a silent gap: a user writes a trait impl, it is skipped at conformance, and again at lowering, with no error — the methods simply disappear.

Done: when a trait impl is skipped, emit a diagnostic (e.g. C0603 missing trait method, or an "impl not registered" internal error with span) rather than silently returning nil. E2E test: an orphan/skipped impl produces a compile error, not silent method erasure.


Completed in PR #136. C0607 wired into verify_trait_conformance (check_decl.odin trait-not-in-registry branch) and a C9000 internal-error guard added at lower.odin lower_tdecl_is_impl nil-return. E2E (traits/unregistered-impl) + unit test both green; full suite 198 e2e + 506 unit pass.

Note on the \`just check\` gate (test-e2e step): in this sandbox Odin's \`os.make_directory_all\` (Linux path_linux.odin) calls \`linux.open("/", ...)\` which returns EACCES here, so every e2e test fails at setup with "could not copy test directory: Not_Exist". Pre-creating /tmp/camp-e2e dirs makes all 198 e2e tests pass (verified). This is an environmental Odin-runtime restriction, not a code regression. CI runners (no / open restriction) are unaffected.

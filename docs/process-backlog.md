# Processing the Backlog

How to work a bean from `.beans/` to a PR. Applies whenever you pick up a bean — whether explicitly assigned or
self-directed.

## Workflow

1. Create bean with `beans create "<title>" [--priority <level>]`
1. Before implementing a bean, **re-anchor on the design**:
   - Read `docs/language-spec.md` — find the relevant rule the bean maps to. Quote the
     relevant rule in your plan.
   - Read `AGENTS.md` constraints + the relevant `src/` and `tests/` code. **Code is truth over docs** — if a doc
     contradicts the code, flag the discrepancy, don't silently follow either.
1. Implement on an isolated worktree (never main). Conventional Commits with the bean id in the scope, e.g.
   `feat(codegen): fix i32/i64 list recursion (camp-jqvd)`.
1. **`just check` is the gate.** It MUST be green before commit. If it's red, try up to **3 genuinely different
   approaches** (different code path, not the same edit re-applied). Re-read the relevant recipe section on each attempt
   — drift usually starts when you stop checking the constitution.
1. On green: delete the bean, commit, push, `gh pr create --fill`, then delete the bean.
1. **If stuck after 3 distinct attempts, stop — do not loop.** Append findings to the bean so the next run inherits the
   context instead of re-discovering it: `beans update <id> -s blocked --body-append - <<'NOTES'` with what you tried,
   the blocked location (`file:line` + shortest decisive error), and the spec reference. Set back to `todo` if still
   tractable later, or leave `blocked` if it needs a design decision.
1. Every feature or bugfix must include tests:
   - **E2E tests** in `tests/e2e/` for compiler diagnostics and runtime behavior
   - **Unit tests** in `src/test_*.odin` for programmatic verification
   - **Camp-native tests** in `stdlib/` for stdlib features
1. No need to keep docs in sync for deleted beans

## Self-Directed Work

When asked to work on the backlog (e.g. "work the next bean", "work a bean") with no specific task:

1. Pick the next ready bean: `beans list --ready -q | head -1`. The `--ready` filter excludes
   in-progress/blocked/completed, and the default sort is priority-first among ready tasks.
1. Follow the Workflow above starting at step 2.
1. If no ready beans, say so — do not invent work.

## Guardrails

- **Never** commit to main, never force-push.
- **Never** delete a test to make the suite pass.
- **Never** silently change behavior not covered by a test without adding one.
- **Never** trust a doc over the code; flag the discrepancy.
- **Always** re-read the relevant recipe section before editing parser/syntax code.
- **Always** stop and record findings on the bean rather than spin on a failing test.

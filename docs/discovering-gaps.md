# Discovering Gaps

How to find implementation gaps and make new beans. Triggered by prompts like
"find gaps", "sweep for missing work". **Dedup against existing beans first** —
`beans list -q` — before creating anything. A duplicate bean wastes a future run.

## Gap sources (in priority order)

### 1. Diagnostic catalog (`docs/diagnostics-catalog.md`)

Specified-but-unwired diagnostics are the densest gap source. For each code
marked "🆕 New":

- grep `src/` to see whether the diagnostic is emitted anywhere (search the
  code, the message text, and the `C0xxx` identifier).
- If no emit site exists, that code is a gap. Create one bean per *coherent
  group* of related codes (e.g. all C01xx lexical diagnostics as one bean if
  they share a phase), not one per code — a single parser/diagnostic phase
  lands as one PR.
- Title it like: `Wire C0003-C0005 lexical diagnostics (invalid escape,
  unterminated string, bad numeric literal)`.

### 2. Recipe §15 (`docs/syntax-recipe.md` §15 "Remaining Compiler Gaps")

Each `###` sub-section under §15 is a named, fix-located gap already.
Cross-reference against `.beans/` by searching slug keywords; only create a
bean if no existing bean covers it. Title from the §15 heading; reference the
heading + the file:line it points at in the body.

### 3. Stdlib coverage (`stdlib/*.camp`)

Two failure modes here:

- **Stub modules** (4-7 line files with type declarations but no or minimal
  impl bodies) — e.g. `Debug`, `Display`, `Eq`. These need real impls; one
  bean per module.
- **Untested modules** (`test "..."` blocks absent or <3). One bean per
  untested module, scoped to adding tests following the Stdlib Testing section
  of `AGENTS.md`.
- Check whether the stub/untested module already appears in an existing bean's
  body before creating a new one.

### 4. Error paths in `src/`

Search for `unreachable`, `not.*(implemented|handled|supported)`, runtime
intrinsics that `panic`, and `#partial switch` fallthroughs (§15 calls these
out explicitly). Each silent error path that should emit a diagnostic is a
candidate bean. Only file one if the diagnostic exists in the catalog but isn't
wired, or if no diagnostic covers it (then also flag for the catalog).

### 5. Recipe drift (§13 "Key Syntax Changes")

§13 is the historical record of decided changes (all marked "Done").
Spot-check 3-5 rows at random: does the parser/code actually reflect the
"Decision" column? A row marked "Done" that the code contradicts is a bug —
create a bean referencing the §13 row and the offending `file:line`. Do not
assume "Done" means done; verify against code.

## Bean creation guidelines

- One bean per *landable unit of work* (one PR's worth). If a gap needs
  multiple phases, create a parent bean + child beans with `--parent <id>`.
- Default priority: `normal` for wired diagnostic gaps and §15 items; `low` for
  stdlib test-coverage; `high` only if the gap causes silent wrong-codegen or
  crashes.
- Body must include: the source reference (catalog code / §15 heading /
  `file:line`), what "done" looks like (the test that proves it), and any §14
  design dependency that blocks it.
- Type: `task` for impl work, `bug` if the gap is wrong behavior rather than
  missing work, `feature` only for genuinely new surface area.
- Tag by area: `codegen`, `parser`, `typecheck`, `stdlib`, `traits`,
  `diagnostics`, as appropriate.

## When NOT to create a bean from gap discovery

- The gap is already covered by an existing bean (search slugs + titles).
- The fix is a trivial one-liner → just fix it per the "When NOT to create a
  bean" rule in `AGENTS.md`.
- The "gap" is actually a §14 deferred design decision — those need the project
  owner's input, not an impl bean. Flag it in chat instead.

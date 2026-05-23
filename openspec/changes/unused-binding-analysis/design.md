## Context

The Camp compiler currently typechecks and lowers code without checking whether bindings are actually consumed. A binding like `x = expensive()` where `x` is never read silently wastes computation. In a strict language with effect tracking, this matters: pure unused bindings are wasted work, and effectful bindings with discarded results may indicate bugs.

The canonical AST (`canonical.odin`) already has the structure needed: `CExpr_Block` contains ordered statements, `CExpr_Assign` captures assignments, `CExpr_For` captures loop variables, and `CExpr_Record` captures field literals. The `Type_Env` tracks bindings with their types and effect rows. The `Diagnostic_Collector` and typed error variants in `diagnostic.odin` provide the diagnostic infrastructure.

The analysis must run **after typechecking** (needs type/effect info to distinguish pure from effectful expressions) but **before code generation** (dead code should not be emitted, and errors should halt compilation).

## Goals / Non-Goals

**Goals:**
- Detect and error on all unused bindings (immutable, reassignable, pattern, destructuring)
- Detect and error on unused record literal fields that don't escape their scope
- Detect and error on unused imports
- Provide `_` prefix escape hatch for intentionally unused bindings
- Provide dedicated error for contradictory `_$`/`$_` prefixes
- Handle `$`-var per-assignment tracking with loop structural-dead-value exemption
- Warn on pointless evaluation (`_ = pureExpr`)
- Skip analysis in unreachable code

**Non-Goals:**
- Whole-program dead code elimination (this is an analysis pass, not an optimization)
- Interprocedural record field analysis (only local scope checked)
- Configurable severity (always hard error for now; future: flag to downgrade)
- Effect purity analysis beyond what the type system already provides

## Decisions

### Decision 1: Pass placement — post-typecheck, pre-lower

The unused analysis pass runs on the **canonical AST** after typechecking completes. This gives us:
- Type information to distinguish effectful from pure expressions (via the effect row on each binding's type)
- The full binding environment from `Type_Env`
- Source spans for precise error messages

We do NOT run this on the IR — the IR is too low-level (already flattened, dup/drop inserted by Perceus). The canonical AST preserves the programmer's binding structure.

**Alternative considered**: Running on the typed AST (`TExpr`). Rejected — the typed AST is an internal typecheck artifact; the canonical AST is the stable representation. Also, the canonical AST already has all the structure we need.

### Decision 2: Two-phase analysis — collect uses, then check

Phase 1: **Use collection** — walk the canonical AST, building a map from each binding name to its set of use sites (read positions, field accesses, function arguments, etc.). For `$`-vars, track each assignment as a distinct "value" with its own use set.

Phase 2: **Check** — for each binding, determine if it has sufficient uses. Apply the `_` prefix exemption. Apply the loop structural-dead-value exemption. Emit diagnostics.

**Alternative considered**: Single-pass with state tracking. Rejected — two passes is simpler to reason about and easier to test. The canonical AST is already in memory; walking it twice is negligible cost.

### Decision 3: Use-site categorization

Each use of a binding falls into a category that determines whether it "counts" for unused checking:

| Category | Example | Counts as use? |
|----------|---------|----------------|
| **Read** | `print(x)` | Yes |
| **Field access** | `r.x` | Yes (for binding `r`, and for field `x` of the record) |
| **Escape** | `process(r)`, `return r`, `perform Op(r)` | Yes (for binding + all record fields) |
| **Effectful escape** | `perform Op` where `Op` uses `x` | Yes |
| **Self-assignment RHS** | `$x = $x + 1` | No (stepping stone, not essential) |
| **Discard** | `_ = x` | No for record fields; yes for bindings (exempts them) |

For record fields: a field is "used" if it is accessed via `.field` or if the record escapes. `_ = r.field` does NOT count as using `r.field` (pure field access in discard position is still wasted work).

### Decision 4: `$`-var assignment tracking model

Each `$`-var gets a stack of assignments, ordered by source position:

```
$x = 1          → assignment 0 (value "1")
$x = $x + 1     → assignment 1 (value "$x + 1")
$x = compute()   → assignment 2 (value "compute()")
```

For each assignment, we track:
- The source span (for error messages)
- Whether any read before the next assignment consumes this value
- Whether the read is "essential" (transitively reaches an observable effect)
- Whether this assignment is inside a loop body

**Overwrite-before-read**: If assignment N is never read before assignment N+1, it's an error.

**Loop exit exemption**: The last assignment in a loop body (the "exit assignment") is exempt from the "must be consumed after the loop" rule IF the `$`-var has essential reads within the loop body.

**Final assignment**: The last assignment before scope exit must be consumed (unless it's a loop exit assignment that qualifies for exemption).

### Decision 5: Essential read detection

A read of a `$`-var is "essential" if it transitively reaches an **observable effect**: an effectful function call (`!`-suffixed), a `perform`, a `return`, or an escape (fn argument that escapes the function). This requires tracking data flow:

```camp
$count = $count + 1                       -- read of $count, but NOT essential (stepping stone)
Console.println!($count)                   -- essential (effectful call)
result = format($count)                    -- only essential if result is also used
```

Implementation: after collecting use sites, do a small reachability analysis from effectful operations backward through data flow. A read is essential if it's in the transitive closure of values that reach an effectful operation.

**Simplification for v1**: Rather than full dataflow, use a conservative heuristic: a read is essential if it appears as an argument to an effectful call, a perform, or a return. Reads consumed only by self-assignment are non-essential. Reads passed to pure functions are only essential if the pure function's result is also used (checked recursively, one level deep).

### Decision 6: Record field escape analysis

A record "escapes" when it is:
1. Passed as a function argument
2. Returned from the current function
3. Used in a `perform`
4. Aliased and the alias escapes (transitive)

When a record escapes, **all its fields are considered used**.

When a record stays local, each field is checked independently. A field is "used" if:
- It is accessed via `.field` anywhere in the local scope
- It is destructured in a pattern that binds the field name

A field is NOT used if:
- It is accessed only in a discard position (`_ = r.field`)
- It is not accessed at all

**Nested records**: Check recursively. If `{ meta: { a: 1, b: 2 }, data: 3 }` and only `meta.a` is accessed, then `meta.b` is unused. BUT if the outer record escapes, all inner fields are used (escape propagates inward).

**Spread**: `{ ...r, z: 3 }` — `r`'s fields are exempt (spread transfers them). The result record's fields are checked.

### Decision 7: Diagnostic error variants

New diagnostic variants in `diagnostic.odin`:

```odin
Unused_Binding :: struct {
    name: string,
    hint:  string,  -- "prefix with _ to mark as intentionally unused"
}

Unused_Record_Field :: struct {
    field_name:   string,
    record_span:  Source_Span,
}

Unused_Import :: struct {
    name:        string,
    module_name: string,
}

Pointless_Evaluation :: struct {
    kind: string,  -- "pure expression discarded with _"
}

Contradictory_Prefix :: struct {
    name: string,  -- "_$x" or "$_x"
}

Noop_Assignment :: struct {
    name: string,  -- "$x = $x"
}

Unused_Assignment :: struct {
    name:      string,
    assign_no: int,     -- which assignment number
    hint:      string,  -- "value is overwritten before read" or "final value is never consumed"
}
```

**Shadowing priority**: When `check_shadow` fires, suppress the `Unused_Binding` error for the same name. The shadowing error is more fundamental.

### Decision 8: `_` prefix parsing and validation

The canonical AST already uses `Intern_ID` for names. To check the `_` prefix:
- Get the interned string for a binding name
- Check if it starts with `_` followed by an alphanumeric character (not another `_`)
- `__foo` → not a valid `_`-prefixed name (reserved)
- Bare `_` → wildcard, always exempt

For `$`-vars: check if the name (after stripping `$`) starts with `_`. Both `_$x` and `$_x` patterns detected.

## Risks / Trade-offs

**[Breaking change]** → Every existing Camp program with unused bindings will fail to compile. Mitigation: This is intentional — dead code is a bug. The `_` prefix provides a clear migration path. Fix is mechanical: add `_` prefix or remove dead code.

**[False positives in complex control flow]** → Path-insensitive analysis may flag bindings that ARE used on some paths but not all. Mitigation: We chose path-insensitive (reports only if NO path uses the binding). This is conservative toward the programmer — fewer false positives, some false negatives.

**[Record field checking is strict]** → No escape hatch for unused fields (`_ = r.y` doesn't help). Mitigation: This forces structural discipline. If you don't need a field, don't include it in the literal. If you need the field for a function, pass the whole record (escape).

**[Essential read detection is approximate]** → v1 heuristic may miss some essential reads or flag some as non-essential. Mitigation: Conservative (errs on the side of "essential" = fewer false errors). Can refine with better dataflow in future versions.

**[Performance]** → Two full AST walks per function. Mitigation: The canonical AST is small relative to other compiler phases. Negligible impact on compile time.

## 1. Diagnostic Error Variants

- [ ] 1.1 Add `Unused_Binding` struct to `diagnostic.odin` with `name` and `hint` fields, and a `diag_unused_binding` constructor
- [ ] 1.2 Add `Unused_Record_Field` struct with `field_name` and `record_span`, and constructor
- [ ] 1.3 Add `Unused_Import` struct with `name` and `module_name`, and constructor
- [ ] 1.4 Add `Pointless_Evaluation` struct with `kind` field, and constructor (category: Warning)
- [ ] 1.5 Add `Contradictory_Prefix` struct with `name` field, and constructor
- [ ] 1.6 Add `Noop_Assignment` struct with `name` field, and constructor
- [ ] 1.7 Add `Unused_Assignment` struct with `name`, `assign_no`, and `hint` fields, and constructor
- [ ] 1.8 Add all new variant names to `diag_token_names.odin` for CLI rendering
- [ ] 1.9 Verify: `odin test src` passes with new diagnostic types

## 2. Underscore Prefix Validation

- [ ] 2.1 Add helper function `is_underscore_prefixed(name: Intern_ID, interner) -> bool` that returns true for `_name` (single underscore + alphanumeric, not double underscore) and bare `_`
- [ ] 2.2 Add helper function `is_bare_wildcard(name: Intern_ID, interner) -> bool` that returns true only for bare `_`
- [ ] 2.3 Add helper function `is_contradictory_prefix(name: Intern_ID, interner) -> bool` that returns true for `_$name` or `$_name` patterns
- [ ] 2.4 Add validation pass in canonicalize or typecheck to emit `Contradictory_Prefix` error for `_$x`/`$_x` bindings
- [ ] 2.5 Verify: `odin test src` passes; write unit tests for all prefix detection functions

## 3. Use Collection Pass (Phase 1 of analysis)

- [ ] 3.1 Create `unused_analysis.odin` with the analysis pass entry point
- [ ] 3.2 Define `Use_Kind` enum: `Read`, `Field_Access`, `Escape_Fn_Arg`, `Escape_Return`, `Escape_Perform`, `Self_Assign_Rhs`, `Discard`
- [ ] 3.3 Define `Binding_Info` struct: name, span, is_reassignable, is_underscore_prefixed, is_top_level, is_pub, assignments list, use_sites list
- [ ] 3.4 Implement `collect_uses_expr` walker for all `CExpr` variants — record each name reference with its `Use_Kind`
- [ ] 3.5 Implement `$`-var assignment tracking: build a per-var assignment stack with source spans and use-site tracking
- [ ] 3.6 Implement record escape detection: track when a record-typed binding is passed to a function, returned, or used in perform
- [ ] 3.7 Implement record field access tracking: for each record binding, track which fields are accessed via `CExpr_Field_Access`
- [ ] 3.8 Implement transitive escape tracking: if a binding is aliased (assigned to another name) and the alias escapes, mark the original as escaped
- [ ] 3.9 Implement pattern binder collection: walk `CPattern` variants to record introduced bindings
- [ ] 3.10 Implement import use collection: track which imported names are referenced in the module

## 4. Unused Checking Pass (Phase 2 of analysis)

- [ ] 4.1 Implement check for unused immutable bindings: if a binding has no `Read`/`Field_Access`/`Escape_*` uses and is not `_`-prefixed, emit `Unused_Binding`
- [ ] 4.2 Implement check for `_`-prefixed bindings with pure RHS: if `_`-prefixed binding has a pure expression and no effect row, emit `Pointless_Evaluation` warning
- [ ] 4.3 Implement check for unused top-level bindings: if private top-level has no uses, emit `Unused_Binding` (ignore `_` prefix for top-levels)
- [ ] 4.4 Implement check for unused imports: if an imported name has no references, emit `Unused_Import`
- [ ] 4.5 Implement check for unused pattern match binders: each binder independently checked, `_`-prefixed exempt
- [ ] 4.6 Implement check for unused destructuring sub-bindings: each field in record/tuple destructuring independently checked
- [ ] 4.7 Implement check for unused iteration variables: `CExpr_For` variable checked like a local binding
- [ ] 4.8 Implement shadowing priority: when `check_shadow` fires for the same name, suppress `Unused_Binding` for that binding

## 5. Reassignable Variable Analysis

- [ ] 5.1 Implement overwrite-before-read detection: for each assignment, check if any use (path-insensitive) exists before the next assignment
- [ ] 5.2 Implement final-assignment-must-be-consumed check: if the last assignment to a `$`-var in a scope has no subsequent reads, emit `Unused_Assignment`
- [ ] 5.3 Implement self-assignment detection: if `$x = $x` is encountered, emit `Noop_Assignment`
- [ ] 5.4 Implement essential read detection: a read is essential if it appears as an argument to an effectful call, perform, return, or escape. Reads only consumed by self-assignment are non-essential
- [ ] 5.5 Implement loop context detection: identify when a `$`-var assignment is inside a `CExpr_For` or `CExpr_While` body
- [ ] 5.6 Implement loop exit assignment exemption: if the exit assignment of a `$`-var in a loop body has essential reads in the loop, suppress the "final value never consumed" error
- [ ] 5.7 Implement non-exit overwrite-before-read in loops: assignments overwritten before read inside a loop body are still errors, except the exit assignment

## 6. Record Field Unused Analysis

- [ ] 6.1 Implement local-only field checking: for records that don't escape, check each field for access via `.field` in the same scope
- [ ] 6.2 Implement `_ = r.field` non-use rule: discard positions do NOT count as using a field
- [ ] 6.3 Implement nested record recursive checking: for nested record literals, check fields at every level
- [ ] 6.4 Implement escape propagation inward: if outer record escapes, all nested record literals' fields are considered used
- [ ] 6.5 Implement spread source exemption: in `{ ...r, z: 3 }`, the source `r` is exempt from field checking
- [ ] 6.6 Implement match-is-local rule: matching on a record counts as local access, not escape — only fields mentioned in patterns count as used

## 7. Integration into Compiler Pipeline

- [ ] 7.1 Add `unused_analysis` pass to the compilation pipeline after typechecking, before lowering
- [ ] 7.2 Pass the `Type_Env` and `Type_Store` to the analysis so it can distinguish effectful from pure expressions
- [ ] 7.3 Skip unused analysis in unreachable code blocks (after `CExpr_Return`, `CExpr_Crash`, provably-false branches)
- [ ] 7.4 Verify: `odin build src -out:camp` succeeds with the new pass integrated
- [ ] 7.5 Verify: `odin test src` passes with the analysis pass in the pipeline

## 8. E2E Tests

- [ ] 8.1 Create `tests/e2e/unused-analysis/immutable-unused/Main.camp` + `expected.toml` — unused immutable binding error
- [ ] 8.2 Create `tests/e2e/unused-analysis/underscore-exempt/Main.camp` + `expected.toml` — `_`-prefixed binding is exempt
- [ ] 8.3 Create `tests/e2e/unused-analysis/pointless-eval/Main.camp` + `expected.toml` — `_ = pureExpr` warning
- [ ] 8.4 Create `tests/e2e/unused-analysis/contradictory-prefix/Main.camp` + `expected.toml` — `_$x` and `$_x` errors
- [ ] 8.5 Create `tests/e2e/unused-analysis/var-overwrite-before-read/Main.camp` + `expected.toml` — `$x = 1; $x = 2; print($x)` error
- [ ] 8.6 Create `tests/e2e/unused-analysis/var-loop-exempt/Main.camp` + `expected.toml` — loop counter with essential reads, no error
- [ ] 8.7 Create `tests/e2e/unused-analysis/var-loop-pure-unused/Main.camp` + `expected.toml` — loop counter with only non-essential reads, error
- [ ] 8.8 Create `tests/e2e/unused-analysis/self-assignment/Main.camp` + `expected.toml` — `$x = $x` error
- [ ] 8.9 Create `tests/e2e/unused-analysis/record-unused-field/Main.camp` + `expected.toml` — unused record field error
- [ ] 8.10 Create `tests/e2e/unused-analysis/record-escape/Main.camp` + `expected.toml` — record passed to fn, no error
- [ ] 8.11 Create `tests/e2e/unused-analysis/record-discard-not-use/Main.camp` + `expected.toml` — `_ = r.y` still errors for `y`
- [ ] 8.12 Create `tests/e2e/unused-analysis/unused-import/Main.camp` + `expected.toml` — unused import error
- [ ] 8.13 Create `tests/e2e/unused-analysis/unused-pattern-binder/Main.camp` + `expected.toml` — unused match variable error
- [ ] 8.14 Create `tests/e2e/unused-analysis/shadowing-priority/Main.camp` + `expected.toml` — shadowing error wins over unused error
- [ ] 8.15 Update `tests/e2e/language/kitchen-sink/Main.camp` if it contains any unused bindings (fix or prefix with `_`)
- [ ] 8.16 Run `just test-e2e` and verify all new and existing tests pass

## 9. Spec Updates

- [ ] 9.1 Update `openspec/specs/unused-analysis/spec.md` — create the new spec domain from the delta spec
- [ ] 9.2 Update `openspec/specs/diagnostics/spec.md` — merge the new diagnostic variants into the existing spec
- [ ] 9.3 Update `openspec/specs/language/spec.md` — merge the modified naming conventions and new requirements
- [ ] 9.4 Update `openspec/specs/compiler/spec.md` — add requirement for the unused analysis pass in the pipeline

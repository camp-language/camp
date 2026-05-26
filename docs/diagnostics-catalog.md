# Camp Diagnostics Catalog

A comprehensive catalog of all diagnostics the Camp compiler should report, organized by compiler phase and category. Each diagnostic includes its severity, title, message template, hints, and rationale.

## Diagnostic Severity Levels

Camp uses three severity levels:

| Level | Meaning | CLI Color |
|-------|---------|-----------|
| **Error** | Compilation cannot succeed. Code must be fixed. | Bold red |
| **Warning** | Code compiles but likely contains a mistake or dead code. | Bold yellow |
| **Internal** | Compiler bug. User should report it. | Bold magenta |

Future: Consider adding **Note** (informational, attached to errors) and **Help** (actionable fix suggestion) as distinct sub-diagnostic types within the existing structure, following Rust's pattern of `note:` and `help:` lines.

## Error Code System (Proposed)

Each diagnostic should have a unique `C####` code for searchability and `camp --explain C0123` support.

| Range | Category |
|-------|----------|
| C0001–C0099 | Lexer errors |
| C0100–C0199 | Parser errors |
| C0200–C0299 | Name resolution errors |
| C0300–C0399 | Type system errors |
| C0400–C0499 | Effect system errors |
| C0500–C0599 | Pattern matching errors |
| C0600–C0699 | Trait/generics errors |
| C0700–C0799 | Newtype/nominal type errors |
| C0800–C0899 | Module/import errors |
| C0900–C0999 | Unused analysis warnings |
| C1000–C1099 | Unused analysis errors |
| C1100–C1199 | Perceus/RC errors |
| C1200–C1299 | CLI/build errors |
| C9000–C9099 | Internal errors |

---

## 1. Lexer Errors

### 1.1 UNEXPECTED CHARACTER (C0001) — Error ✅ Implemented

> I don't recognize the character `{char}`.

**Hint:** (context-dependent — backtick and `!` in certain positions get specialized hints)

**Rationale:** The lexer encountered a character outside Camp's accepted character set.

### 1.2 UNTERMINATED STRING (C0002) — Error ✅ Implemented

> This string never ends. Try adding a closing `"`.

**Rationale:** A string literal was opened but never closed before EOF or a newline (for non-per-line strings).

### 1.3 INVALID ESCAPE SEQUENCE (C0003) — Error 🆕 New

> `\{escape}` is not a valid escape sequence.

**Hint:** Valid escape sequences are: `\n`, `\t`, `\r`, `\\`, `\"`, `\0`.

**Rationale:** Other languages (Rust, Go, Swift) report invalid escape sequences explicitly. Without this, an invalid escape like `\x` silently becomes `x` or causes confusing downstream errors.

### 1.4 UNTERMINATED PER-LINE STRING (C0004) — Error 🆕 New

> This per-line string (starting with `\`) is never closed. The closing `\` must appear alone on its own line.

**Rationale:** Per-line strings (Camp's `\` syntax) need a closing `\` on its own line. A distinct error from C0002 because the fix is different.

### 1.5 INVALID NUMERIC LITERAL (C0005) — Error 🆕 New

> Invalid numeric literal `{text}`.

**Hint:** (context-dependent — e.g., "Integer literals cannot contain decimal points. Write `3.14` as a Float literal.")

**Rationale:** Rust, Go, and Swift all report malformed numeric literals (e.g., `0b102`, `0xGH`). Camp should catch these at lexing rather than letting them become confusing parse errors.

### 1.6 UNTERMINATED BLOCK COMMENT (C0006) — Error 🆕 New

> This block comment was never closed. Add a closing `*/`.

**Rationale:** If Camp supports block comments (`/* ... */`), an unclosed one silently swallows code. Rust reports this explicitly.

---

## 2. Parser Errors

### 2.1 EXPECTED TOKEN (C0100) — Error ✅ Implemented

> I expected `{expected}` here, but I got `{actual}` instead.

**Rationale:** The parser expected a specific token (e.g., `}` after a block) but found something else.

### 2.2 UNEXPECTED TOKEN (C0101) — Error ✅ Implemented

> I was not expecting `{token}` here.

**Hint:** Context-dependent (e.g., "Are you trying to write a pattern match?" for `|`)

**Rationale:** The parser encountered a token that cannot appear in the current position.

### 2.3 EXPECTED TYPE (C0102) — Error ✅ Implemented

> I was expecting a type here, but I found `{actual}` instead.

**Rationale:** A type was expected (in annotations, signatures, etc.) but a non-type token was found.

### 2.4 MISSING BRACES (C0103) — Error ✅ Implemented

> `if`/`else` branches require braces. Use `if condition { ... } else { ... }`.

**Hint:** For chained conditions, use `else if`.

**Rationale:** Camp mandates braces for all branches. This is a design choice for readability and to avoid dangling-else ambiguity.

### 2.5 EMPTY TAG PARENS (C0105) — Error ✅ Implemented

> Tag `{name}` has no payload — write `{name}` without parentheses.

**Rationale:** Tags without payloads should not use parentheses, per the syntax recipe.

### 2.6 EMPTY EFFECT ROW (C0106) — Error ✅ Implemented

> An effect row cannot be empty. Use `->` for a pure function instead of `-[ ]->`.

**Rationale:** An empty effect row `-[ ]->` is syntactically meaningless. Pure functions use `->`.

### 2.7 UNTERMINATED INTERPOLATION (C0107) — Error ✅ Implemented

> This string interpolation expression is missing a closing `}`.

**Rationale:** String interpolation `${expr}` requires a closing `}`.

### 2.8 MULTILINE INTERPOLATION (C0108) — Error ✅ Implemented

> String interpolation expressions must be on a single line.

**Hint:** Try extracting the expression into a variable defined before the string.

**Rationale:** Interpolation expressions must be single-line for readability and parsing simplicity.

### 2.9 UNEXPECTED TOKENS IN INTERPOLATION (C0109) — Error ✅ Implemented

> I found extra tokens after the expression in this string interpolation.

**Rationale:** Only one expression is allowed per interpolation hole.

### 2.10 DUPLICATE FIELD IN RECORD LITERAL (C0110) — Error 🆕 New

> Field `{name}` appears more than once in this record literal.

**Rationale:** Rust (E0063), TypeScript (2353), and Swift all report duplicate struct/record fields. This is almost always a mistake.

### 2.11 DUPLICATE FIELD IN RECORD PATTERN (C0111) — Error 🆕 New

> Field `{name}` appears more than once in this record pattern.

**Rationale:** Destructuring the same field twice is either a typo or confusion about which value is bound.

### 2.12 DUPLICATE VARIANT IN TAG UNION (C0112) — Error 🆕 New

> Variant `{name}` appears more than once in this tag union type.

**Rationale:** Duplicate variants in a union type are meaningless and likely a copy-paste error.

### 2.13 DUPLICATE EFFECT IN ROW (C0113) — Error 🆕 New

> Effect `{name}` appears more than once in this effect row.

**Hint:** Each effect should appear at most once in an effect row.

**Rationale:** Duplicate effects in a row are semantically redundant and likely a mistake.

### 2.14 INVALID MATCH ARM (C0114) — Error 🆕 New

> This match arm is missing a `=>` and a body.

**Rationale:** Malformed match arms (e.g., just a pattern with no arrow) should be caught with a clear message rather than a generic "expected token" error.

### 2.15 MISSING ARROW IN FUNCTION TYPE (C0115) — Error 🆕 New

> This function type is missing an arrow. Use `->` for pure functions or `-[effects]->` for effectful ones.

**Rationale:** A common mistake when writing function types, especially for newcomers to the effect syntax.

### 2.16 INVALID VISIBILITY MODIFIER (C0116) — Error 🆕 New

> `pub` can only be applied to top-level declarations.

**Rationale:** Applying `pub` to local bindings is meaningless and likely a misunderstanding of visibility rules.

### 2.17 INVALID EFFECT ROW SYNTAX (C0117) — Error 🆕 New

> Effect rows use `|` as a separator, not `,`. Write `-[A! | B!]->` instead of `-[A!, B!]->`.

**Rationale:** Per the syntax recipe, effect rows use `|` as separator. A common mistake for users coming from languages with comma-separated lists.

---

## 3. Name Resolution Errors

### 3.1 UNDEFINED NAME (C0200) — Error ✅ Implemented

> I cannot find `{name}`.

**Hint:** "Did you mean `{similar}`?" (when similar names exist via Levenshtein distance)

**Rationale:** The referenced name does not exist in the current scope.

### 3.2 SHADOWING (C0201) — Error ✅ Implemented

> `{name}` shadows a binding from an enclosing scope. All shadowing is forbidden.

**Hint:** Use a different name for this binding.

**Rationale:** Camp forbids all shadowing to prevent subtle bugs. This is a deliberate design choice.

### 3.3 DUPLICATE NAME (C0202) — Error ✅ Implemented

> Name `{name}` is already defined in this module.

**Rationale:** Two bindings in the same scope share the same name.

### 3.4 UNDEFINED TYPE (C0203) — Error 🆕 New

> Type `{name}` is not defined.

**Hint:** "Did you mean `{similar}`?" (when similar type names exist)

**Rationale:** Distinguishing undefined types from undefined values gives clearer error messages. Rust (E0412), TypeScript (2304), and Kotlin all separate these.

### 3.5 UNDEFINED EFFECT (C0204) — Error 🆕 New

> Effect `{name}` is not defined.

**Hint:** "Did you mean `{similar}`?" (when similar effect names exist)

**Rationale:** Effects are a first-class concept in Camp. An undefined effect should have its own error distinct from undefined names/types.

### 3.6 PRIVATE MEMBER ACCESS (C0205) — Error 🆕 New

> `{name}` is private to module `{module}` and cannot be accessed here.

**Hint:** Use a public member, or access `{name}` from within module `{module}`.

**Rationale:** Kotlin (`INVISIBLE_REFERENCE`), Swift (`candidate_inaccessible`), and Rust (E0603) all report visibility violations explicitly. Currently Camp has `diag_import_not_exported` but no general private-access error for qualified access.

### 3.7 AMBIGUOUS REFERENCE (C0206) — Error 🆕 New

> `{name}` is ambiguous — it could refer to the binding from `{scope_a}` or the binding from `{scope_b}`.

**Hint:** Use qualified access to disambiguate.

**Rationale:** When the same name is available from multiple sources (imports, inheritance), the compiler should list the candidates. Currently only `diag_import_ambiguous` covers import-import conflicts; this covers the general case.

### 3.8 NOT A FUNCTION (C0207) — Error 🆕 New

> `{name}` has type `{type}`, which is not a function. It cannot be called.

**Rationale:** Attempting to call a non-function value. Currently this likely manifests as a type mismatch, but a dedicated error is clearer. Rust (E0618), TypeScript, and Swift all have this.

### 3.9 NOT A TYPE (C0208) — Error 🆕 New

> `{name}` has kind `{kind}`, which is not a type. It cannot be used in a type position.

**Rationale:** Using a value-level name in a type position (or vice versa). This is distinct from "undefined type" because the name exists but is the wrong kind.

### 3.10 RAW IDENTIFIER NOT NEEDED (C0209) — Warning 🆕 New

> `r#{name}` is not a keyword — you can write `{name}` without the `r#` prefix.

**Rationale:** Raw identifiers (`r#name`) are only needed for keywords. Using them for non-keywords is unnecessary noise. Rust warns about this.

---

## 4. Type System Errors

### 4.1 TYPE MISMATCH (C0300) — Error ✅ Implemented

> `{type_a}` does not match `{type_b}`.

**Secondary span:** "this has type `{type_b}`"

**Rationale:** The most common type error — two types that should unify don't.

### 4.2 PRIMITIVE MISMATCH (C0301) — Error ✅ Implemented

> `{name_a}` does not match `{name_b}`.

**Secondary span:** "this has type `{name_b}`"

**Rationale:** Specialized for primitive type conflicts (I64 vs F64, etc.) where the message can be more direct.

### 4.3 VALUE/ROW CONFLICT (C0302) — Error ✅ Implemented

> I expected a {kind_a} type here, but I found a {kind_b} type instead.

**Rationale:** Mismatch between a value type and a row type (or vice versa). This is specific to Camp's row-type system.

### 4.4 INFINITE TYPE (C0303) — Error ✅ Implemented

> This creates an infinite type. `{type_expr}` is defined in terms of itself, which would make the type infinitely large.

**Secondary span:** "also related to this"

**Rationale:** The occurs check failed — a type variable would need to contain itself.

### 4.5 ARITY MISMATCH (C0304) — Error ✅ Implemented

> This function expects {expected} argument(s), but it was called with {actual}.

**Secondary span:** "called here"

**Rationale:** Wrong number of arguments at a call site.

### 4.6 TAG ARITY MISMATCH (C0305) — Error ✅ Implemented

> Tag `{tag}` expects {expected} payload(s), but here it has {actual}.

**Secondary span:** "defined with {expected} payload(s) here"

**Rationale:** A tag constructor was given the wrong number of payload values.

### 4.7 AMBIGUOUS TYPE (C0306) — Error ⚠️ Defined but unused

> Cannot determine type for generic parameter `{name}`. Provide a type annotation.

**Rationale:** Type inference couldn't determine a type variable. This constructor exists but is not yet emitted.

### 4.8 CANNOT INFER RETURN TYPE (C0307) — Error 🆕 New

> Cannot infer the return type of this function. Add a type annotation to the function or its body.

**Rationale:** When a function's return type is ambiguous (e.g., an empty body, or conflicting return types in branches), a specific error is more helpful than a generic "ambiguous type". Kotlin (`CANNOT_INFER_VALUE_PARAMETER_TYPE`), Rust (E0282), and Swift all have this.

### 4.9 TYPE ANNOTATION MISMATCH (C0308) — Error 🆕 New

> This expression was annotated with type `{annotated}`, but it has type `{inferred}`.

**Secondary span:** "type annotation here"

**Rationale:** When the user provides a type annotation that conflicts with the inferred type, the error should specifically call out the annotation as the "expected" and the inference as the "actual". Elm and Rust both distinguish this from a generic type mismatch.

### 4.10 MISSING FIELDS IN RECORD (C0309) — Error 🆕 New

> Record type `{type}` requires field `{field}`, but it is missing from this literal.

**Hint:** Add `{field}: {value}` to the record literal.

**Rationale:** When constructing a record, all required fields must be present. Rust (E0563), TypeScript (2353), and Swift all report missing fields explicitly.

### 4.11 UNKNOWN FIELD IN RECORD (C0310) — Error 🆕 New

> Field `{field}` does not exist on record type `{type}`.

**Hint:** "Did you mean `{similar}`?" (when similar field names exist)

**Rationale:** Accessing or constructing a record with a field that doesn't exist in the type. Rust (E0560), TypeScript (2322), and Swift all report this.

### 4.12 FIELD TYPE MISMATCH (C0311) — Error 🆕 New

> Field `{field}` has type `{expected}`, but the provided value has type `{actual}`.

**Rationale:** When constructing a record with a field of the wrong type, the error should name the field rather than just showing a generic type mismatch.

### 4.13 DISPLAY NOT IMPLEMENTED (C0319) — Error ✅ Implemented

> Type `{type}` does not implement `Display`. Only types that implement `Display` can be used in string interpolation.

**Hint:** Implement `Display` for `{type}`, or convert the value to `Str` before interpolation.

**Rationale:** String interpolation requires `Display` implementation. This was previously unnumbered; assigned C0319 to avoid conflict with C0312.

### 4.14 CANNOT UNIFY EFFECT ROWS (C0312) — Error 🆕 New

> Effect row `{actual}` does not match expected row `{expected}`. The extra effect `{effect}` is not handled.

**Secondary span:** "this expression introduces effect `{effect}`"

**Hint:** Add `{effect}` to the function's effect row, or handle it with a `handle` block.

**Rationale:** Effect row unification failure is Camp-specific and deserves a dedicated error. Following Elm's pattern of tracing where the extraneous row label was introduced, this should show where the unexpected effect originates.

### 4.15 ROW LABEL MISMATCH (C0313) — Error 🆕 New

> Record row `{actual}` does not match expected row `{expected}`. Missing label `{label}`, extra label `{label}`.

**Rationale:** When record types fail to unify due to row differences, a specific error naming the mismatched labels is more helpful than a generic type mismatch.

### 4.16 TYPE PARAMETER KIND MISMATCH (C0314) — Error 🆕 New

> Type parameter `{param}` expects a {expected_kind} type, but `{actual}` is a {actual_kind} type.

**Rationale:** Applying a type parameter of the wrong kind (e.g., passing a value type where a row type is expected). Rust (E0210) has this.

### 4.17 RECURSIVE TYPE ALIAS (C0315) — Error 🆕 New

> Type alias `{name}` is directly recursive, which would expand infinitely. Use a tag union or newtype to introduce indirection.

**Rationale:** `type T = T` or `type T = List(T)` through an alias creates infinite expansion. TypeScript (E2456), Rust, and Haskell all report this.

### 4.18 INVALID MAIN SIGNATURE (C0316) — Error 🆕 New

> `main!` has type `{actual}`, but it must have type `() -[effects]-> I64`.

**Hint:** `main!` must return `I64`. Use `0` for a successful exit.

**Rationale:** The entry point has a fixed signature. A specific error is better than a generic type mismatch.

### 4.19 DUPLICATE TYPE PARAMETER (C0317) — Error 🆕 New

> Type parameter `{name}` appears more than once in this type's parameter list.

**Rationale:** `type Foo(a, a)` is meaningless. Rust (E0403) reports this.

### 4.20 CONSTRUCTOR NOT EXHAUSTIVE (C0318) — Error 🆕 New

> Tag union `{name}` has no variants. A tag union must have at least one variant.

**Rationale:** An empty tag union is uninhabitable and almost certainly a mistake.

---

## 5. Effect System Errors

Camp's algebraic effect system is its most distinctive feature. These diagnostics are critical for the developer experience.

### 5.1 EFFECTFUL FUNCTION NAMING (C0400) — Error ✅ Implemented

> This function performs effect {effects}, so its name needs to end with `!`.

**Hint:** Try: `{name}!`

**Rationale:** Camp requires effectful functions to end with `!` for explicitness at call sites.

### 5.2 UNHANDLED EFFECT (C0401) — Error ✅ Implemented

> This expression performs effect `{effect}`, but there is no `handle` block around it.

**Hint:** Try wrapping it with a `handle` block.

**Rationale:** An effect was performed but no handler is in scope.

### 5.3 EFFECT ROW MISMATCH (C0402) — Error 🆕 New

> This function's effect row `-[{actual}]->` does not match the expected `-[{expected}]->`.

**Secondary span:** "expected effect row from {context}" (e.g., "function signature", "type annotation")

**Hint:** Add `{missing_effect}` to the function's effect row, or handle it before this point.

**Rationale:** When a function's actual effects don't match its declared effect row, the error should show both rows and identify the discrepancy. This is distinct from C0312 (cannot unify rows) because this is about a function declaration vs its body.

### 5.4 UNNECESSARY EFFECT IN SIGNATURE (C0403) — Warning 🆕 New

> Effect `{effect}` is listed in this function's effect row, but the function never performs it.

**Hint:** Remove `{effect}` from the effect row, or the function may need to perform this effect.

**Rationale:** Over-declaring effects is not an error (it's a subtype relationship), but it's likely a mistake or leftover from refactoring. Similar to Rust's `unused_mut` — the code works but the annotation is misleading.

### 5.5 EFFECT NOT IN SCOPE (C0404) — Error 🆕 New

> Effect `{name}` is not defined. Did you mean to import it?

**Hint:** "Did you mean `{similar}`?" (when similar effect names exist)

**Rationale:** Referencing an undefined effect in a type annotation or `perform`. Currently this would fall under "undefined name" but deserves its own error because effects are a distinct namespace.

### 5.6 HANDLER SIGNATURE MISMATCH (C0405) — Error 🆕 New

> Handler arm for `{effect}` expects {expected} parameter(s), but the effect operation provides {actual}.

**Rationale:** A handler arm's parameter count must match the effect operation's signature. Currently this is an internal error; it should be a user-facing error.

### 5.7 MISSING RESUME IN HANDLER (C0406) — Error 🆕 New

> Handler arm for `{effect}` does not call `resume`. The computation is stuck.

**Hint:** Call `resume(value)` to continue the computation, or `resume` with a different value to alter the result.

**Rationale:** Forgetting to call `resume` in a handler arm is a common mistake that silently discards the continuation. This is analogous to Kotlin's `missing_return` diagnostic.

### 5.8 DOUBLE RESUME IN HANDLER (C0407) — Error 🆕 New

> `resume` was called more than once in this handler arm. Each handler arm may call `resume` at most once.

**Rationale:** Double-resuming is a well-known pitfall in algebraic effect handlers. Koka and Eff explicitly check for this.

### 5.9 INVALID RESUME OUTSIDE HANDLER (C0408) — Error 🆕 New

> `resume` can only be used inside a `handle` block.

**Rationale:** Using `resume` outside a handler is meaningless. Currently this would be an "undefined name" error, but a specific message is more helpful.

### 5.10 REDUNDANT HANDLER (C0409) — Warning 🆕 New

> This `handle` block handles `{effect}`, but that effect is never performed in the handled computation.

**Hint:** Remove the handler arm for `{effect}`, or the computation may need to perform this effect.

**Rationale:** A handler that never intercepts any operations is dead code. Similar to unused import detection.

### 5.11 EFFECT ROW SUBTYPE WARNING (C0410) — Warning 🆕 New

> This function's effect row `-[{actual}]->` is a subtype of the declared `-[{declared}]->`. The extra declared effects are unnecessary.

**Hint:** Consider tightening the effect row to `-[{actual}]->`.

**Rationale:** When a function declares more effects than it actually uses, the signature is imprecise. Not an error (subtyping allows it), but worth warning about for API clarity.

---

## 6. Pattern Matching Errors

### 6.1 NON-EXHAUSTIVE MATCH (BOOL) (C0500) — Error ✅ Implemented

> This match on Bool is non-exhaustive: missing branch for `{missing}`.

**Rationale:** Bool has exactly two constructors; missing one is always an error.

### 6.2 NON-EXHAUSTIVE MATCH (INT/STRING) (C0501) — Warning ✅ Implemented

> This match on {type} can never be exhaustive without a wildcard pattern.

**Hint:** Add a wildcard `_` or variable pattern to handle remaining values.

**Rationale:** Int and String have infinite constructors; a wildcard is required for exhaustiveness.

### 6.3 NON-EXHAUSTIVE MATCH (TAG UNION) (C0502) — Error 🆕 New

> This match on `{type}` is non-exhaustive: missing branch for `{missing_variant}`.

**Hint:** Add a branch for `{missing_variant}`, or add a wildcard pattern.

**Rationale:** Tag union exhaustiveness is a core feature of strict functional languages. Rust (E0004), Elm, and Kotlin all make this a hard error for sealed/sum types. Currently Camp has an internal error fallback; this should be a proper user-facing error.

### 6.4 REDUNDANT PATTERN (C0503) — Warning ✅ Implemented

> This pattern is redundant — it is already covered by an earlier arm.

**Hint:** Remove this arm or reorder patterns so this one comes first.

**Rationale:** Unreachable patterns are dead code. GHC (`-Woverlapping-patterns`), Rust, and OCaml (warning 11) all report this.

### 6.5 FRAGILE MATCH (C0504) — Warning 🆕 New

> This match on `{type}` is exhaustive now, but adding a new variant to `{type}` would make it non-exhaustive.

**Hint:** Add a wildcard pattern to make this match robust against future changes.

**Rationale:** OCaml's warning 4 (`fragile-match`) is brilliant — it warns when a match is technically exhaustive but would break if a new variant is added. This is especially valuable in Camp where newtypes can be extended with new variants.

### 6.6 INVALID IRREFUTABLE PATTERN (C0505) — Error 🆕 New

> Pattern `{pattern}` is refutable and cannot be used in a `let` binding. Only irrefutable patterns (wildcards, variables, records with all fields) are allowed here.

**Hint:** Use a `match` expression instead.

**Rationale:** `let` bindings require irrefutable patterns. Using a tag pattern like `let Some(x) = expr` should be an error. Rust (E0005), Haskell, and OCaml all enforce this.

### 6.7 MISSING FIELDS IN RECORD PATTERN (C0506) — Error 🆕 New

> Record pattern is missing field `{field}`. Use `_` to ignore a field, or `{..}` to ignore remaining fields.

**Rationale:** When destructuring a record, all fields must be accounted for (either bound or explicitly ignored). Rust (E0027) reports this.

### 6.8 UNKNOWN FIELD IN RECORD PATTERN (C0507) — Error 🆕 New

> Field `{field}` does not exist on record type `{type}`.

**Hint:** "Did you mean `{similar}`?"

**Rationale:** Destructuring a field that doesn't exist. Rust (E0026) reports this.

### 6.9 DUPLICATE BINDING IN PATTERN (C0508) — Error 🆕 New

> Variable `{name}` appears more than once in this pattern. In Camp, each variable in a pattern must be unique.

**Rationale:** `match x { { a, a } => ... }` is ambiguous. Rust (E0416) and Haskell report this.

### 6.10 WILDCARD AFTER CATCH-ALL (C0509) — Warning 🆕 New

> This wildcard pattern is unreachable — a previous wildcard or variable pattern already matches everything.

**Rationale:** A more specific version of "redundant pattern" for the case where multiple wildcards/variables exist.

---

## 7. Trait and Generics Errors

### 7.1 ORPHAN RULE VIOLATION (C0600) — Error ✅ Implemented

> Cannot implement `{trait}` for `{type}` here — implementations must be in the same module as the type or the trait.

**Rationale:** The orphan rule prevents incoherent trait instances. Rust (E0117) and Haskell enforce this.

### 7.2 OVERLAPPING INSTANCE (C0601) — Error ✅ Implemented

> `{type}` already implements `{trait}` — cannot implement the same trait for the same type twice.

**Rationale:** Duplicate trait implementations cause ambiguity. Rust (E0119) and Haskell report this.

### 7.3 CONSTRAINT VIOLATION (C0602) — Error ✅ Implemented

> `{type}` does not satisfy constraint `{constraint}`.

**Rationale:** A type doesn't implement a required trait. Rust (E0277) and Kotlin report this.

### 7.4 MISSING TRAIT METHOD (C0603) — Error ✅ Implemented

> `{type}` does not implement method `{method}` required by trait `{trait}`.

**Rationale:** A trait implementation is missing a required method. Rust (E0046) and Swift report this.

### 7.5 TRAIT METHOD SIGNATURE MISMATCH (C0604) — Error ✅ Implemented

> `{type}`'s `{method}` method has wrong signature for trait `{trait}`.

**Label:** "expected {expected_sig}, got {actual_sig}"

**Rationale:** A trait method implementation has the wrong type. Rust (E0053) and Swift report this.

### 7.6 MISSING TRAIT CONSTRAINT (C0605) — Error 🆕 New

> Type parameter `{param}` requires constraint `{constraint}`, but it is not in scope here.

**Hint:** Add `{constraint}` to the type parameter's constraint list.

**Rationale:** When a generic function uses a trait method on a type parameter, the constraint must be declared. Rust (E0599) reports this.

### 7.7 CONFLICTING IMPLEMENTATIONS (C0606) — Error 🆕 New

> Implementing `{trait}` for `{type}` would conflict with the existing implementation via `{other_trait}`.

**Rationale:** When two trait instances would overlap through coherence, the compiler should explain the conflict. Haskell and Rust both report this.

### 7.8 TRAIT NOT FOUND (C0607) — Error 🆕 New

> Trait `{name}` is not defined.

**Hint:** "Did you mean `{similar}`?"

**Rationale:** Referencing an undefined trait. Currently this would be an "undefined name" error, but traits are a distinct namespace.

### 7.9 SUPERTRAIT NOT SATISFIED (C0608) — Error 🆕 New

> Trait `{trait}` requires supertrait `{supertrait}`, but `{type}` does not implement it.

**Hint:** Implement `{supertrait}` for `{type}` first.

**Rationale:** When a trait has a supertrait requirement, the implementing type must satisfy all supertraits. Rust (E0277 with note) and Haskell report this.

### 7.10 CYCLIC TRAIT DEPENDENCY (C0609) — Error 🆕 New

> Trait `{trait}` has a cyclic dependency: `{cycle}`.

**Rationale:** `trait A requires B`, `trait B requires A` creates a cycle. Haskell and Rust report this.

### 7.11 AMBIGUOUS TRAIT RESOLUTION (C0610) — Error 🆕 New

> Multiple implementations of `{trait}` for `{type}` are available. Use a qualified call to disambiguate.

**Rationale:** When type inference can't determine which instance to use. Haskell and Rust report this.

---

## 8. Newtype and Nominal Type Errors

### 8.1 UNQUALIFIED TAG (C0700) — Error ✅ Implemented

> Tag `{tag}` belongs to newtype `{nt}` — use `{nt}.{tag}` to construct it.

**Rationale:** Tags belonging to newtypes must be qualified at construction sites outside the defining module.

### 8.2 TAG NOT OWNED (C0701) — Error ✅ Implemented

> Tag `{tag}` does not belong to newtype `{nt}`.

**Rationale:** Attempting to use a tag with a newtype it doesn't belong to.

### 8.3 NEWTYPE COERCION (C0702) — Error ⚠️ Defined but unused

> Cannot use `{nt}` where `{inner}` is expected — newtypes are distinct from their inner type. Use `.inner()` to unwrap.

**Rationale:** Newtypes are nominal — they don't implicitly convert to/from their inner type.

### 8.4 OPAQUE TYPE (C0703) — Error ✅ Implemented

> Nominal type `{type}` is opaque outside its defining module — cannot {action} here.

**Hint:** Perform this operation in the module that defines `{type}`, or use `pub` variants.

**Rationale:** Opaque types enforce abstraction boundaries.

### 8.5 NEWTYPE FIELD ACCESS (C0704) — Error 🆕 New

> Cannot access field `{field}` on newtype `{type}` — newtypes are opaque. Use a method or accessor defined in the defining module.

**Rationale:** Attempting to access a field on a newtype as if it were a record. Newtypes are nominal and opaque.

---

## 9. Module and Import Errors

### 9.1 MODULE NOT FOUND (C0800) — Error ✅ Implemented

> Module `{name}` not found.

**Rationale:** The imported module doesn't exist.

### 9.2 CYCLIC DEPENDENCY (C0801) — Error ✅ Implemented

> Cyclic dependency: {cycle_path}

**Rationale:** Circular imports create infinite compilation loops.

### 9.3 NOT EXPORTED (C0802) — Error ✅ Implemented

> `{name}` is not exported from module `{module}`.

**Hint:** Use qualified access `{module}.{name}` or make it `pub`.

**Rationale:** Attempting to import a private member.

### 9.4 IMPORT CONFLICT (C0803) — Error ✅ Implemented

> `{name}` imported from {module} conflicts with existing binding — use qualified access {module}.{name}

**Rationale:** An import name collides with an existing binding.

### 9.5 AMBIGUOUS IMPORT (C0804) — Error ✅ Implemented

> `{name}` is ambiguous — imported from both {mod_a} and {mod_b}; use qualified access.

**Rationale:** Two imports provide the same name.

### 9.6 ENTRY POINT NOT FOUND (C0805) — Error ✅ Implemented

> Entry point not found — expected src/Main.camp with `pub main!`

**Rationale:** The build system can't find the entry point.

### 9.7 NO MAIN FUNCTION (C0806) — Error ✅ Implemented

> Entry point module Main does not define `pub main!`

**Rationale:** The Main module exists but lacks the required entry point.

### 9.8 NO SOURCE FILES (C0807) — Error ✅ Implemented

> No Camp source files found — expected a `src/` directory

**Rationale:** The project has no source files to compile.

### 9.9 DUPLICATE IMPORT (C0808) — Warning 🆕 New

> `{name}` is imported more than once from module `{module}`.

**Rationale:** Importing the same name twice from the same module is redundant. TypeScript (6192) and GHC (`-Wdodgy-imports`) report this.

### 9.10 IMPORT SHADOWS BINDING (C0809) — Warning 🆕 New

> Imported name `{name}` shadows a local binding. Use qualified access to disambiguate.

**Rationale:** When an import name collides with a local binding, the import wins silently in many languages. Camp forbids shadowing, so this is already an error (C0201), but a more specific message helps.

### 9.11 SELF IMPORT (C0810) — Error 🆕 New

> Module `{name}` cannot import itself.

**Rationale:** Self-imports are meaningless and likely a mistake.

### 9.12 MISSING IMPORT FOR TYPE (C0811) — Note 🆕 New

> Type `{type}` is defined in module `{module}`. Consider adding `import {module} { {type} }`.

**Rationale:** When a type is referenced but not imported, suggesting the import (like Swift's `candidate_add_import`) is extremely helpful. This is a note attached to an UNDEFINED TYPE error.

---

## 10. Unused Analysis Warnings

### 10.1 UNUSED BINDING (C0900) — Warning ✅ Implemented

> Binding `{name}` is never used. {hint}

**Hint:** Prefix with `_` to mark as intentionally unused: `_{name}`

**Rationale:** Local bindings that are never read are dead code.

### 10.2 UNUSED RECORD FIELD (C0901) — Warning ✅ Implemented

> Record field `{field}` is never accessed locally.

**Secondary span:** "this record literal"

**Rationale:** A record field that is constructed but never accessed.

### 10.3 UNUSED IMPORT (C0902) — Warning ✅ Implemented

> `{name}` imported from `{module}` is never used.

**Rationale:** Unused imports add noise and slow compilation.

### 10.4 POINTLESS EVALUATION (C0903) — Warning ⚠️ Defined but unused

> Pure expression discarded with `_`. {kind}

**Hint:** Remove this binding, or use the result.

**Rationale:** Discarding a pure expression with `_ = expr` is pointless — the evaluation has no observable effect.

### 10.5 UNUSED ASSIGNMENT (C0904) — Warning ✅ Implemented

> Assignment #{n} to `${name}` is unused. {hint}

**Hints:** "Value is overwritten before read." / "Final value is never consumed."

**Rationale:** Reassignable variables (`$name`) must have every assignment consumed.

### 10.6 UNJOINED SPAWN (C0905) — Warning ⚠️ Defined but unused

> This spawned handle is not joined on all exit paths. Unjoined handles are cancelled when the handler exits, which may silently discard results.

**Hint:** Use `join!` to await the result, or explicitly `cancel!` to discard it.

**Rationale:** Forgetting to join a spawned task silently discards its result.

### 10.7 UNUSED FUNCTION (C0906) — Warning 🆕 New

> Private function `{name}` is never called.

**Hint:** If this is intentional, consider making it `pub` or prefixing with `_`.

**Rationale:** Unused private functions are dead code. Rust (`dead_code`), GHC (`-Wunused-binds`), and OCaml (warning 32) report this. Currently Camp's unused-binding covers top-level bindings, but a specific "unused function" message is clearer.

### 10.8 UNUSED TYPE DEFINITION (C0907) — Warning 🆕 New

> Type `{name}` is defined but never referenced.

**Rationale:** Unused type definitions are dead code. GHC (`-Wunused-type-signatures`) and OCaml (warning 34) report this.

### 10.9 UNUSED TYPE PARAMETER (C0908) — Warning 🆕 New

> Type parameter `{name}` is declared but never used in the type definition.

**Rationale:** `type Foo(a) = Bar` where `a` is unused. GHC (`-Wunused-type-patterns`) reports this.

### 10.10 UNUSED EFFECT HANDLER (C0909) — Warning 🆕 New

> Handler arm for `{effect}` never intercepts any operations. The effect is not performed in the handled computation.

**Rationale:** A handler arm that never fires is dead code. This is the handler analog of an unused import.

### 10.11 UNREACHABLE CODE (C0910) — Warning 🆕 New

> This code is unreachable — it follows a `return`, `match` with all branches returning, or similar construct.

**Rationale:** Code after a return or exhaustive match is dead. Go (`unreachable`), Rust, and GHC report this. The unused analysis spec notes that unreachable code should skip unused checking.

### 10.12 MUST_USE DISCARDED (C0911) — Warning 🆕 New

> Result of `{function}` is discarded. This type is marked as `@must_use` — its result should not be ignored.

**Hint:** Use the result, or explicitly discard with `_ =` if intentional.

**Rationale:** Rust's `#[must_use]` attribute catches bugs where important return values (like `Result`, `Option`) are silently discarded. Camp should support `@must_use` annotations on types and functions.

### 10.13 REDUNDANT ELSE (C0912) — Warning 🆕 New

> This `else` branch is redundant — the `if` condition is always true (or the preceding `match` is exhaustive).

**Rationale:** When an `if` condition is known to be always true (e.g., after a type-narrowing check), the `else` branch is unreachable. GHC and Rust report this.

### 10.14 UNNECESSARY MUTABILITY (C0913) — Warning 🆕 New

> Variable `{name}` is declared with `$` but is never reassigned. Use an immutable binding instead.

**Hint:** Replace `${name}` with `{name}`.

**Rationale:** If a `$`-variable is never reassigned, the `$` prefix is misleading. Rust's `unused_mut` lint serves the same purpose.

---

## 11. Unused Analysis Errors (Hard Errors)

These are hard errors per Camp's design philosophy that unused code should be caught early.

### 11.1 CONTRADICTORY PREFIX (C1000) — Error ✅ Implemented

> `{name}` combines `_` (ignore) and `$` (each value matters) — these are contradictory.

**Hint:** Reassignable variables cannot be marked as unused. Remove the `_` prefix.

**Rationale:** `_` and `$` have opposite semantics — one means "ignore", the other means "track carefully".

### 11.2 NO-OP ASSIGNMENT (C1001) — Error ✅ Implemented

> `{name}` is assigned to itself — this has no effect.

**Rationale:** Self-assignment (`$x = $x`) is always a mistake.

---

## 12. Perceus / Reference Counting Errors

Camp uses Perceus reference counting for deterministic memory management. These diagnostics are unique to Camp.

### 12.1 REFERENCE LEAK (C1100) — Warning 🆕 New

> Value of type `{type}` is created but never consumed. This may indicate a reference counting leak.

**Hint:** Ensure the value is used, returned, or explicitly dropped.

**Rationale:** In a Perceus RC system, values that are created but never consumed may leak. While the type system should prevent most leaks, this catches cases where a value is assigned but the assignment is never read (similar to unused assignment but from the RC perspective).

### 12.2 UNNECESSARY COPY (C1101) — Warning 🆕 New

> This value is copied when it could be moved. Use `move` or restructure to avoid the copy.

**Rationale:** Perceus optimizes by reusing (consuming) references. When a copy is made where a consume would suffice, this warning suggests an optimization opportunity. This is analogous to Rust's "consider using a reference" suggestions.

### 12.3 CONSUME AFTER USE (C1102) — Error 🆕 New

> Value `{name}` is consumed (used after it has been moved/consumed). Each value can only be used once under Perceus semantics.

**Secondary span:** "value consumed here"

**Rationale:** Under Perceus RC, consuming a value (using it as the last reference) means it can't be used again. This is Camp's analog of Rust's "use after move" (E0382).

---

## 13. CLI and Build Errors

### 13.1 INVALID FILE EXTENSION (C1200) — Error ✅ Implemented

> I expected a `.camp` file, but you gave me `{path}`.

**Rationale:** Camp source files must have the `.camp` extension.

### 13.2 FILE NOT FOUND (C1201) — Error ✅ Implemented

> I could not read `{path}` ({os_error}).

**Rationale:** The specified file doesn't exist or can't be read.

### 13.3 UNKNOWN COMMAND (C1202) — Error ✅ Implemented

> I don't know the command `{command}`.

**Hint:** Try `build`, `check`, `test`, or `fmt`.

**Rationale:** Invalid CLI subcommand.

### 13.4 FILE WRITE FAILED (C1203) — Error ✅ Implemented

> Failed to write output file `{path}`: {reason}

**Rationale:** The compiler couldn't write its output (permissions, disk full, etc.).

### 13.5 OUTPUT DIRECTORY NOT FOUND (C1204) — Error 🆕 New

> Output directory `{path}` does not exist and could not be created.

**Rationale:** When the `-o` or `--out` directory doesn't exist and can't be created.

### 13.6 INVALID OPTION (C1205) — Error 🆕 New

> Unknown option `{option}`.

**Hint:** Run `camp --help` for available options.

**Rationale:** Invalid CLI flag or option.

### 13.7 CONFLICTING OPTIONS (C1206) — Error 🆕 New

> Options `{a}` and `{b}` conflict — they cannot be used together.

**Rationale:** Mutually exclusive CLI options.

### 13.8 COMPILATION LIMIT EXCEEDED (C1207) — Error 🆕 New

> Compilation limit exceeded: {limit}. This may indicate an infinite loop in the compiler.

**Hint:** This is likely a compiler bug. Please report it at https://github.com/smores56/camp/issues

**Rationale:** Stack overflow, iteration limit, or memory limit during compilation. Prevents the compiler from hanging.

---

## 14. Internal Errors

### 14.1 INTERNAL ERROR (C9000) — Internal ✅ Implemented

> Something went wrong inside the compiler: {message}

**Hint:** This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues

**Rationale:** Compiler bugs. Currently used for several specific cases that should become proper user-facing errors:
- "perform without handler evidence" → should become C0408
- "handler arm has wrong parameter count" → should become C0405
- "operation not found in effects" → should become C0404
- "trait not found in registry" → should become C0607
- "non-exhaustive match" → should become C0502

---

## Summary: Implementation Status

### Currently Implemented (65 total)

| Category | Count | Codes |
|----------|-------|-------|
| Lexer | 2 | C0001, C0002 |
| Parser | 10 | C0100–C0109 |
| Name Resolution | 3 | C0200–C0202 |
| Type System | 7 | C0300–C0306 |
| Effect System | 2 | C0400, C0401 |
| Pattern Matching | 3 | C0500–C0503 |
| Traits/Generics | 5 | C0600–C0604 |
| Newtype/Nominal | 4 | C0700–C0703 |
| Module/Import | 8 | C0800–C0807 |
| Unused Warnings | 6 | C0900–C0905 |
| Unused Errors | 2 | C1000, C1001 |
| CLI/Build | 4 | C1200–C1203 |
| Internal | 1 | C9000 |

### Defined but Unused (4)

| Constructor | Proposed Code | Action |
|-------------|---------------|--------|
| `diag_newtype_coercion` | C0702 | Wire into type checker |
| `diag_ambiguous_type` | C0306 | Wire into type inference |
| `diag_unjoined_spawn` | C0905 | Wire into parallelism checker |
| `diag_pointless_evaluation` | C0903 | Wire into unused analysis (TODO in `analysis/unused.odin:667`) |

### Proposed New Diagnostics (58)

| Category | Count | Codes | Priority |
|----------|-------|-------|----------|
| Lexer | 4 | C0003–C0006 | Medium |
| Parser | 9 | C0110–C0118 | Medium |
| Name Resolution | 7 | C0203–C0209 | High |
| Type System | 12 | C0307–C0318 | High |
| Effect System | 10 | C0402–C0411 | **Critical** |
| Pattern Matching | 7 | C0502, C0504–C0509 | High |
| Traits/Generics | 6 | C0605–C0610 | Medium |
| Newtype/Nominal | 1 | C0704 | Low |
| Module/Import | 4 | C0808–C0811 | Medium |
| Unused Warnings | 8 | C0906–C0913 | High |
| Perceus/RC | 3 | C1100–C1102 | Medium |
| CLI/Build | 4 | C1204–C1207 | Low |

### Total Proposed Catalog: 123 diagnostics (65 existing + 58 new)

---

## Design Principles (Learned from Other Languages)

### 1. Chain the "Why" (TypeScript/Rust pattern)
When type A ≠ B, explain *why* at each structural level. Don't just say "mismatch" — drill down:
```
Error: `Record({x: I64, y: Str})` does not match `Record({x: I64, y: I64})`
  → field `y` has type `Str`, expected `I64`
```

### 2. Trace Effect Origins (Elm pattern)
For effect row mismatches, trace backwards to find where the unexpected effect was *introduced*, not just where the mismatch was detected. Show the introduction site as a secondary span.

### 3. Exhaustiveness is Always an Error (Rust/Elm pattern)
In a strict functional language, non-exhaustive matches on closed types (tag unions, Bool) should always be hard errors. For open types (Int, String), require a wildcard and warn if missing.

### 4. Fragile Match Warning (OCaml pattern)
Warn when a match is technically exhaustive but would break if a new variant is added. This is especially valuable during refactoring.

### 5. Must-Use Annotations (Rust pattern)
Support `@must_use` on types and functions. Discarding a must-use value should be a warning. This catches bugs like ignoring `Result` return values.

### 6. Suggest Imports (Swift pattern)
When a name is undefined but exists in another module, suggest the import. This dramatically improves the new-user experience.

### 7. Structured Diagnostic Type (GHC pattern)
Use a typed ADT for diagnostics rather than stringly-typed messages. This enables:
- JSON output for IDE integration
- `--explain C0300` for long-form descriptions
- Machine-readable suggestions with applicability levels
- Localization

### 8. Severity Fluidity (GHC pattern)
Decouple diagnostic *reason* from *severity*. Allow warnings to be promoted to errors via flags (`-Werror=unused-import`) and vice versa. This lets projects enforce strictness incrementally.

### 9. Actionable Hints (Elm pattern)
Every error should have an actionable hint. "Type mismatch" without a suggestion is frustrating. "Did you mean `Foo.bar`?" or "Add `!` to the function name" makes errors educational.

### 10. Internal Errors Should Become User Errors
Every current `diag_internal` call site that represents a user mistake (wrong handler arity, missing trait, etc.) should become a proper user-facing diagnostic with a helpful message. Internal errors should only be for genuine compiler bugs.

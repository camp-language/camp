# Generics and Traits — Technical Design

> Technical design for Camp's generic type parameters and trait system.
> See `spec.md` for behavioral requirements.

---

## 1. Overview

Camp implements parametric polymorphism via **monomorphization** and ad-hoc polymorphism via **structurally-verified, nominally-opted-in traits**. All dispatch is static — resolved at compile time during monomorphization. No vtables, no trait objects, no dynamic dispatch.

```
┌───────────────────────────────────────────────────────────────┐
│  Updated Pipeline                                             │
│                                                               │
│  parse → canonicalize → typecheck → ANNOTATE → MONO → lower  │
│                                           ↓         ↑        │
│                                     Typed IR    specialized   │
│                                      (TFile)     TFile       │
│                                                               │
│  New phases: ANNOTATE (CFile+Type_Store → TFile)              │
│              MONO     (TFile → specialized TFile)             │
└───────────────────────────────────────────────────────────────┘
```

---

## 2. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Generic strategy | Monomorphization | No hidden allocations; matches "no hidden control flow" principle; direct WASM calls |
| Specialization phase | After typecheck, before lower | Type info fresh; lower works on fully-specialized code |
| Dispatch method | Static-only (monomorphization) | No vtables, no runtime overhead; simpler implementation |
| Dynamic dispatch | Not in this phase | Add later when use cases demand it; requires vtable layout + fat pointers |
| `Self` | Implicit first param in trait methods | Reads naturally: `display : Self -> Str`; replaced during `is` verification |
| Trait inheritance | Transitive (`is Ord` implies `is Eq`) | Substitutability; matches Rust/Haskell/Swift; no runtime cost |
| Orphan rule | Enforced from the start | Prevents coherence issues early; simple module-name check |
| Constraint checking | Eager (at typecheck) | Errors reported early; follows ML-style type class resolution |
| Specialization naming | `$` separator | `add$I64`, `map$List_I64_Str`; guaranteed no collision with Camp identifiers |
| Mono input format | Typed IR (TFile) | Each node carries type; deep-clone + substitute is clean; lower benefits too |

---

## 3. Type System Extensions

### 3.1 New Types in `types.odin`

```odin
Type_Param :: struct {
    name:        Intern_ID,
    constraints: [dynamic]Intern_ID,  -- trait names (empty if unconstrained)
}

Trait_Info :: struct {
    name:    Intern_ID,
    module:  Intern_ID,               -- defining module
    parent:  Intern_ID,               -- NO_NAME if no parent
    methods: []Trait_Method_Info,
}

Trait_Method_Info :: struct {
    name:        Intern_ID,
    param_types: []Type_Var_ID,       -- includes Self as index 0
    return_type: Type_Var_ID,
}

Trait_Impl :: struct {
    trait_name:  Intern_ID,
    type_name:   Intern_ID,           -- the implementing type's interned name
    type_module: Intern_ID,           -- module that defines the type
    methods:     map[Intern_ID]Canonical_Name,  -- method name → implementing function
}
```

### 3.2 Extensions to `Type_Store`

```odin
Type_Store :: struct {
    -- ... existing fields ...

    trait_registry:   map[Intern_ID]Trait_Info,    -- trait name → info
    trait_impls:      [dynamic]Trait_Impl,         -- all `is` declarations
    type_constraints: map[Type_Var_ID][]Intern_ID,  -- var → required trait names
}
```

### 3.3 How Constraints Interact with Level Inference

When the typechecker processes `<a is Display>`:
1. Create a fresh `Type_Var_ID` for `a` (already done)
2. Record the constraint: `type_constraints[a_var] = [Display_name]`
3. When `a_var` is later unified with a concrete type (e.g., `UserId`), **immediately check**:
   - Look up `trait_impls` for `(Display, UserId)`
   - If no impl found, emit "type `UserId` does not satisfy constraint `Display`" error
4. The Level inference algorithm is unchanged — constraints are checked as a side effect of unification

### 3.4 Self Resolution

`Self` is a built-in type variable in trait method signatures. During `is` verification, Self is unified with the implementing type. It is not a free type variable — it is always resolved to the implementing type.

1. The trait method has `param_types[0]` pointing to a placeholder type var
2. When verifying `UserId is Display`, unify `param_types[0]` with `UserId`'s type var
3. This automatically checks that the implementing function's first parameter matches `UserId`

---

## 4. Typed IR (TFile)

### 4.1 Motivation

The mono pass needs to **clone and substitute** functions. The canonical AST (`CFile`) doesn't carry type information on each node — types live in `Type_Store` as a side table indexed by `Intern_ID`. Cloning a function would require cloning the relevant Type_Store entries, which is fragile.

A typed IR solves this: every node carries its `Type_Var_ID`, so deep-cloning + substitution is self-contained.

Lower also benefits: it currently struggles to determine WASM types from the untyped canonical AST.

### 4.2 TExpr Structure

Every `TExpr` node includes a `type_id: Type_Var_ID` and `eff_id: Type_Var_ID` (effect row). Mirror the `CExpr` union:

```odin
TExpr :: union {
    ^TExpr_Int,
    ^TExpr_Float,
    ^TExpr_String,
    ^TExpr_Bool,
    ^TExpr_Tag,
    ^TExpr_Record,
    ^TExpr_List,
    ^TExpr_Name,
    ^TExpr_Call,
    ^TExpr_Method_Call,
    ^TExpr_Lambda,
    ^TExpr_Block,
    ^TExpr_If,
    ^TExpr_Match,
    ^TExpr_BinOp,
    ^TExpr_PrefixOp,
    ^TExpr_Field_Access,
    ^TExpr_Record_Update,
    ^TExpr_Assign,
    ^TExpr_Return,
    ^TExpr_Crash,
    ^TExpr_Interpolate,
    ^TExpr_Handle,
}

TExpr_Int :: struct {
    value:   i64,
    type_id: Type_Var_ID,
    eff_id:  Type_Var_ID,
    span:    Source_Span,
}

TExpr_Call :: struct {
    callee:   TExpr,
    args:     [dynamic]TExpr,
    type_id:  Type_Var_ID,   -- return type
    eff_id:   Type_Var_ID,   -- effect row
    span:     Source_Span,
}

TExpr_Method_Call :: struct {
    receiver:  TExpr,
    method:    Canonical_Name,
    args:      [dynamic]TExpr,
    type_id:   Type_Var_ID,
    eff_id:    Type_Var_ID,
    -- resolved_impl: Canonical_Name,  -- filled in by mono for concrete types
    span:      Source_Span,
}

-- ... etc for all CExpr variants ...
```

### 4.3 TDecl Structure

```odin
TDecl :: union {
    ^TDecl_Const,
    ^TDecl_Effect,
    ^TDecl_Trait,
    ^TDecl_Alias,
    ^TDecl_Import,
    ^TDecl_Test,
    ^TDecl_Expect,
}

TDecl_Const :: struct {
    name:            Canonical_Name,
    is_pub:          bool,
    is_effectful:    bool,
    body:            TExpr,
    type_id:         Type_Var_ID,    -- the const's type
    eff_id:          Type_Var_ID,    -- effect row of body
    derive_targets:  [dynamic]Intern_ID,
    span:            Source_Span,
}
```

### 4.4 Annotate Pass

The annotate pass (`annotate.odin`, ~150 lines) converts `CFile` + `Type_Store` → `TFile`:

1. Walk the canonical AST
2. For each expression, look up its type from `Type_Store.bindings` or from the type var computed during typecheck
3. Attach `type_id` and `eff_id` to each `TExpr` node
4. Build `TFile` with all typed declarations

This is a straightforward structural traversal — no type inference, just annotation.

---

## 5. Monomorphization Pass

### 5.1 Data Structures

```odin
Mono_Env :: struct {
    store:           ^Type_Store,
    interner:        ^Intern_Table,
    specializations: map[string]Canonical_Name,  -- "fn_name$I64" → specialized name
    worklist:        [dynamic]Mono_Item,
    output_decls:    [dynamic]TDecl,
}

Mono_Item :: struct {
    original:  Canonical_Name,       -- the generic function
    type_args: map[Intern_ID]Type_Var_ID,  -- type param name → concrete type
    span:      Source_Span,
}
```

### 5.2 Algorithm

```
mono(tfile: TFile, store: Type_Store) -> TFile:

    env = Mono_Env{store, interner, ...}

    -- Phase 1: Seed the worklist
    for decl in tfile.decls:
        walk_decls_for_call_sites(decl, &env)

    -- Phase 2: BFS worklist
    while len(env.worklist) > 0:
        item = pop_front(&env.worklist)
        key = specialization_key(item)
        if key in env.specializations:
            continue  -- already specialized

        specialized_name = mangle(item.original, item.type_args)
        env.specializations[key] = specialized_name

        -- Deep-clone the generic function
        cloned = deep_clone(item.original.body)

        -- Substitute type variables
        cloned = substitute_types(cloned, item.type_args)

        -- Resolve trait method calls for now-concrete types
        cloned = resolve_trait_dispatch(cloned, item.type_args, &env)

        -- Walk cloned body for new generic call sites
        walk_expr_for_call_sites(cloned, &env)

        -- Add specialized decl to output
        append(&env.output_decls, cloned with name=specialized_name)

    -- Phase 3: Rewrite call sites in all declarations
    for decl in tfile.decls:
        rewrite_calls(decl, env.specializations)

    -- Phase 4: Combine original non-generic decls + specialized decls
    return TFile{decls = rewritten_originals + env.output_decls}
```

### 5.3 Type Substitution

When specializing `add<I64>`:

```odin
substitute_types :: proc(expr: TExpr, type_args: map[Intern_ID]Type_Var_ID, store: ^Type_Store) -> TExpr:
    -- Walk the expression tree
    -- For each TExpr_Name where name is a type parameter:
    --   Replace its type_id with the concrete type from type_args
    -- For each TExpr_Call:
    --   Recurse into callee and args
    --   If callee is generic, record a new Mono_Item
    -- For each TExpr_Lambda:
    --   Substitute type_params, param types, return type, effect row
    -- For all nodes:
    --   Update type_id and eff_id if they reference substituted vars
```

### 5.4 Trait Method Resolution

During mono, when a `TExpr_Method_Call` has a concrete receiver type:

```odin
resolve_trait_dispatch :: proc(expr: TExpr, type_args: map[Intern_ID]Type_Var_ID, env: ^Mono_Env) -> TExpr:
    case ^TExpr_Method_Call:
        receiver_type = resolve_type(e.receiver.type_id, env.store)

        if receiver_type is concrete:
            -- Look up trait impl
            for impl in env.store.trait_impls:
                if impl.type_name == receiver_type_name and method_matches(impl, e.method):
                    -- Replace method call with direct call to impl function
                    impl_fn = impl.methods[e.method.name]
                    return TExpr_Call{
                        callee = TExpr_Name{name = impl_fn},
                        args = [e.receiver, ..e.args],
                        type_id = e.type_id,
                        eff_id = e.eff_id,
                    }

        -- If receiver is still generic, leave as method call
        -- (this would be an error — all generics should be resolved by now)
```

### 5.5 Specialization Key / Mangling

```odin
specialization_key :: proc(item: Mono_Item, store: Type_Store, interner: Intern_Table) -> string:
    -- "module.name$Type1_Type2"
    base = format_canonical_name(item.original, interner)
    type_parts: [dynamic]string
    for _, type_var in item.type_args:
        append(&type_parts, format_type_var(store, type_var))
    return base + "$" + join("_", type_parts[:])
```

Examples:
- `add<I64>` → `module$add$I64`
- `map<List(I64), Str>` → `module$map$List_I64_Str`
- `format<UserId>` → `module$format$UserId`

The `$` separator is guaranteed not to collide with Camp identifiers because `$` is only valid as a mutable-variable prefix (e.g., `$count`), never in the middle of a name.

---

## 6. Typechecker Changes

### 6.1 Trait Declaration Processing

```odin
typecheck_decl case ^CDecl_Trait:
    -- Register trait in registry
    info = Trait_Info{
        name = d.name.name,
        module = d.name.module,
        parent = d.parent,  -- NO_NAME if no parent
        methods = ...,
    }

    -- For each method, create type vars for params and return
    for m in d.methods:
        method_info = Trait_Method_Info{
            name = m.name,
            param_types = [fresh_value_var for each param],
            return_type = fresh_value_var or convert_type_to_var(m.return_type),
        }
        append(&info.methods, method_info)

    store.trait_registry[d.name.name] = info

    -- Register in env so trait name is in scope
    env.bindings[d.name.name] = trait_var
```

### 6.2 `is` Verification

When a newtype declares `is Trait`:

```odin
verify_trait_conformance :: proc(
    type_name: Intern_ID,
    type_module: Intern_ID,
    trait_name: Intern_ID,
    store: ^Type_Store,
    env: ^Type_Env,
) -> bool:

    -- 1. Orphan rule: must be in type's module or trait's module
    trait_info = store.trait_registry[trait_name]
    if type_module != trait_info.module and type_module != current_module:
        emit diag_orphan_rule_violation(...)
        return false

    -- 2. Check for overlapping instances
    for impl in store.trait_impls:
        if impl.trait_name == trait_name and impl.type_name == type_name:
            emit diag_overlapping_instance(...)
            return false

    -- 3. Collect all required traits (transitive inheritance)
    required_traits = collect_all_traits(trait_name, store.trait_registry)
    -- required_traits includes Eq when checking Ord is Eq

    -- 4. For each required trait, verify methods
    for req_trait in required_traits:
        req_info = store.trait_registry[req_trait]
        for method in req_info.methods:
            -- Look up the implementing function
            impl_fn_name = derive_impl_name(type_name, method.name)
            if impl_fn_name not in env.bindings:
                emit diag_missing_trait_method(type_name, req_trait, method.name)
                return false

            -- Structural verification: unify param/return types
            impl_fn_type = env.bindings[impl_fn_name]
            -- Unify Self (param_types[0]) with the type's var
            unify(store, method.param_types[0], type_var)
            -- Unify remaining params and return type
            ...

    -- 5. Record the impl
    impl = Trait_Impl{
        trait_name = trait_name,
        type_name = type_name,
        type_module = type_module,
        methods = { method.name → impl_fn for each method },
    }
    append(&store.trait_impls, impl)

    return true
```

### 6.3 Transitive Trait Collection

```odin
collect_all_traits :: proc(trait_name: Intern_ID, registry: map[Intern_ID]Trait_Info) -> []Intern_ID:
    visited: map[Intern_ID]bool
    result: [dynamic]Intern_ID

    -- BFS from trait_name up the inheritance chain
    worklist = [trait_name]
    while len(worklist) > 0:
        current = pop_front(&worklist)
        if visited[current]: continue
        visited[current] = true
        append(&result, current)

        info = registry[current]
        if info.parent != NO_NAME:
            append(&worklist, info.parent)

    return result[:]
```

### 6.4 Constraint Checking on Unification

When `unify(store, constrained_var, concrete_var)` is called and `constrained_var` has constraints:

```odin
-- After successful unification in unify():
constraints, has_constraints = store.type_constraints[ra]
if has_constraints:
    resolved_concrete = resolve_var(store, rb)
    for trait_name in constraints:
        if !has_trait_impl(store, trait_name, resolved_concrete):
            emit diag_constraint_violation(
                type_var_name, trait_name, concrete_type_name)
```

### 6.5 UFCS in Typecheck

When the typechecker encounters `TExpr_Method_Call{receiver, method, args}`:

1. Synth the receiver type
2. If the receiver type is a known type with a trait impl containing `method`, resolve immediately to the impl function
3. If the receiver type is a constrained type variable (`a is Display`), leave the method call as-is — mono will resolve it
4. If no matching method found anywhere, emit "method not found" error

---

## 7. Parser Changes

### 7.1 Type Parameter Constraints

```
type_params ::= '<' type_param (',' type_param)* '>'
type_param  ::= NAME is_clause?
is_clause   ::= 'is' trait_name (',' trait_name)*
```

In `parser_parse_lambda`:

```odin
-- After parsing '<', for each type param:
type_param = Type_Param{name = name_id}

-- Check for 'is' keyword
if lexer_peek(p.lexer) == .Kw_Is:
    lexer_consume(p.lexer)  -- consume 'is'
    -- Parse constraint: trait name, possibly comma-separated
    append(&type_param.constraints, trait_name_id)
    while lexer_peek(p.lexer) == .Comma:
        lexer_consume(p.lexer)
        append(&type_param.constraints, next_trait_name_id)

append(&type_params, type_param)
```

### 7.2 `Self` Keyword

Add `Kw_Self` to `Token_Kind`. In the lexer, `Self` is recognized as a keyword only when:
- Inside a trait method signature (tracked by parser context)

Otherwise, `Self` is treated as an ordinary UpperCamelCase identifier.

The parser sets a flag `in_trait_signature: bool` when parsing trait method declarations. When this flag is set, `Self` in a type annotation position creates a `CType_Variable` with a special name (interned as `"Self"`).

The typechecker recognizes `Self` in trait method contexts and creates a fresh type var that will be unified during `is` verification.

---

## 8. Canonical AST Changes

### 8.1 Type_Param Replaces Raw Intern_ID

```odin
-- Before:
CExpr_Lambda :: struct {
    type_params: [dynamic]Intern_ID,
    ...
}

-- After:
CExpr_Lambda :: struct {
    type_params: [dynamic]Type_Param,
    ...
}
```

Same change for `CDecl_Newtype.type_params` (when newtypes are added).

### 8.2 Canonicalize Propagation

In `canonicalize.odin`, when converting `Expr_Lambda` to `CExpr_Lambda`:
- Convert `type_params` from `[dynamic]Intern_ID` to `[dynamic]Type_Param`
- For each type param with `is` constraints, resolve trait names via the canonicalize scope

---

## 9. Implementation Order

| Phase | What | File(s) | Est. Lines |
|-------|------|---------|------------|
| **G1** | `Type_Param` struct; parser `<a is Display>` | `ast.odin`, `canonical.odin`, `parser.odin`, `canonicalize.odin` | ~60 |
| **G8** | `Self` contextual keyword | `lexer.odin`, `parser.odin` | ~25 |
| **G2** | `Trait_Info`, `Trait_Impl`, `type_constraints` in `Type_Store` | `types.odin` | ~40 |
| **G2b** | Trait registry + impl methods on Type_Store | `types.odin` | ~100 |
| **G3** | Typecheck trait decls: register, `is` verification, orphan rule, structural verification, inheritance | `typecheck.odin` | ~120 |
| **G4** | Constrained type param checking: verify on unification | `typecheck.odin`, `unify.odin` | ~30 |
| **G5** | UFCS dispatch in typecheck: resolve for concrete types, defer for constrained vars | `typecheck.odin` | ~50 |
| **G9** | Typed IR: `TExpr`, `TDecl`, `TFile` structs | `typed.odin` (new) | ~200 |
| **G10** | Annotate pass: `CFile` + `Type_Store` → `TFile` | `annotate.odin` (new) | ~150 |
| **G6** | Mono pass: worklist BFS, type substitution, trait dispatch, call rewriting | `mono.odin` (new) | ~250 |
| **G7** | Wire mono into pipeline: typecheck → annotate → mono → lower | `build.odin` or main | ~15 |
| **G11** | Update lower to take `TFile` | `lower.odin` | ~50 |
| **G12** | Diagnostic types: orphan rule, overlapping instance, constraint violation, missing trait method | `diag.odin` | ~40 |
| **G13** | Unit tests | `test_typecheck.odin`, `test_mono.odin` (new) | ~120 |
| **G14** | E2E tests: generic functions, trait impl, UFCS, constraints | `tests/e2e/` | ~15 files |
| | | **Total** | ~1250 |

### Recommended Order

```
G1 → G8 → G2 → G2b → G12 → G3 → G4 → G5 → G9 → G10 → G6 → G7 → G11 → G13 → G14
```

Parser + type system first (G1, G8, G2, G2b, G12) so we can write and typecheck test programs. Then trait verification (G3, G4, G5). Then the typed IR + mono pipeline (G9, G10, G6, G7, G11). Then testing (G13, G14).

---

## 10. Invariants

1. **After typecheck**: All trait declarations registered. All `is` declarations verified. All constraint violations reported.
2. **After mono**: No generic type variables remain. No unresolved trait dispatch remains. Every function has concrete parameter and return types.
3. **Orphan rule**: Every `is` declaration is in the type's module or the trait's module.
4. **Transitive inheritance**: `is Ord` implies `is Eq`. The compiler checks all parent trait methods.
5. **No overlapping instances**: At most one `is` per (type, trait) pair.
6. **Static-only dispatch**: All trait method calls become direct WASM `call` instructions after monomorphization.
7. **Eager constraint checking**: Constraint violations are reported when the constrained variable is unified with a concrete type — never deferred past typecheck.

---

## 11. Future Work (Out of Scope)

| Feature | Why deferred | Design note |
|---------|-------------|-------------|
| Dynamic dispatch / trait objects | Requires vtable layout, fat pointers, box conventions | Add `Trait_Obj<T>` type later; vtable as hidden first field |
| `@derive` expansion | Needs comptime evaluation | Trait impl stubs generated by comptime functions |
| Associated types | Significantly more complex type inference | Can be added without breaking existing code |
| Default method implementations | Requires priority ordering for overrides | Simple once trait objects exist |
| Generic newtypes (`Result(a, e)`) | Depends on newtype implementation | Type parameters already designed to work with newtypes |

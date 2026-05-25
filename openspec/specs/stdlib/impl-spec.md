# Stdlib Implementation Specification

## Overview

This spec defines the exact `.camp` source files for the 6 core stdlib modules: `Str`, `List`, `Map`, `Set`, `Iter`, `Num`. Each module specifies:
1. The type declaration
2. Which functions are **intrinsic** (need runtime/WASM support) vs **pure Camp** (implementable in the language itself)
3. The exact implementation code using correct syntax from `docs/syntax-recipe.md`
4. Effect row annotations where needed

### Intrinsic Convention

Functions requiring runtime support use `crash "intrinsic: Module.function"` as their body. The compiler's lowering pass recognizes these signatures and replaces them with calls to the Odin/WASM runtime. This is a compiler-internal convention, not a language feature.

---

## Str Module

### Design

`Str` is a **builtin type** — the compiler provides it natively. The `.camp` file does not declare the type (the compiler owns it). All string operations are **intrinsic** because they require:
- UTF-8 byte-level traversal
- Unicode grapheme cluster analysis (Unicode 15.0+ grapheme break rules)
- Unicode case mapping (to_lower, to_upper)
- Memory allocation for new strings

Per D18: `Str.length` counts graphemes, `Str.slice` is grapheme-safe, case ops are Unicode, `split_first`/`split_last` return `Result((Str, Str), [NotFound])`.

### Implementation

```camp
-- Str.camp
-- Str is a builtin type. This file declares the public API.
-- All functions are intrinsic (require runtime UTF-8/Unicode support).

-- Queries
pub length : Str -> I64
pub length = |s| crash "intrinsic: Str.length"

pub byte_size : Str -> I64
pub byte_size = |s| crash "intrinsic: Str.byte_size"

pub is_empty : Str -> Bool
pub is_empty = |s| length(s) == 0

-- Comparison
pub starts_with : Str, Str -> Bool
pub starts_with = |s, prefix| crash "intrinsic: Str.starts_with"

pub ends_with : Str, Str -> Bool
pub ends_with = |s, suffix| crash "intrinsic: Str.ends_with"

pub contains : Str, Str -> Bool
pub contains = |s, substr| crash "intrinsic: Str.contains"

-- Slicing (grapheme-safe)
pub take : Str, I64 -> Str
pub take = |s, n| crash "intrinsic: Str.take"

pub drop : Str, I64 -> Str
pub drop = |s, n| crash "intrinsic: Str.drop"

pub slice : Str, I64, I64 -> Str
pub slice = |s, start, len| crash "intrinsic: Str.slice"

-- Splitting
pub split : Str, Str -> List(Str)
pub split = |s, sep| crash "intrinsic: Str.split"

pub split_first : Str, Str -> Result((Str, Str), [NotFound])
pub split_first = |s, sep| crash "intrinsic: Str.split_first"

pub split_last : Str, Str -> Result((Str, Str), [NotFound])
pub split_last = |s, sep| crash "intrinsic: Str.split_last"

-- Trimming
pub trim : Str -> Str
pub trim = |s| crash "intrinsic: Str.trim"

pub trim_start : Str -> Str
pub trim_start = |s| crash "intrinsic: Str.trim_start"

pub trim_end : Str -> Str
pub trim_end = |s| crash "intrinsic: Str.trim_end"

-- Case (Unicode)
pub to_lower : Str -> Str
pub to_lower = |s| crash "intrinsic: Str.to_lower"

pub to_upper : Str -> Str
pub to_upper = |s| crash "intrinsic: Str.to_upper"

-- Concatenation
pub concat : Str, Str -> Str
pub concat = |a, b| crash "intrinsic: Str.concat"

pub join : List(Str), Str -> Str
pub join = |parts, sep| crash "intrinsic: Str.join"

pub repeat : Str, I64 -> Str
pub repeat = |s, n| crash "intrinsic: Str.repeat"

-- Replacement
pub replace : Str, Str, Str -> Str
pub replace = |s, pattern, replacement| crash "intrinsic: Str.replace"

pub replace_first : Str, Str, Str -> Str
pub replace_first = |s, pattern, replacement| crash "intrinsic: Str.replace_first"

-- Prefix/Suffix manipulation
pub drop_prefix : Str, Str -> Str
pub drop_prefix = |s, prefix| crash "intrinsic: Str.drop_prefix"

pub drop_suffix : Str, Str -> Str
pub drop_suffix = |s, suffix| crash "intrinsic: Str.drop_suffix"

-- Conversion
pub to_bytes : Str -> Bytes
pub to_bytes = |s| crash "intrinsic: Str.to_bytes"

pub from_bytes : Bytes -> Result(Str, [InvalidUtf8])
pub from_bytes = |b| crash "intrinsic: Str.from_bytes"

pub from_bytes_lossy : Bytes -> Str
pub from_bytes_lossy = |b| crash "intrinsic: Str.from_bytes_lossy"

-- Parsing (numeric)
pub to_i64 : Str -> Result(I64, [InvalidFormat])
pub to_i64 = |s| crash "intrinsic: Str.to_i64"

pub to_f64 : Str -> Result(F64, [InvalidFormat])
pub to_f64 = |s| crash "intrinsic: Str.to_f64"

-- Iteration
pub to_iter : Str -> Iter(Str)
pub to_iter = |s| crash "intrinsic: Str.to_iter"

-- Display/Eq instances provided by compiler for builtin type
```

### Notes

- `is_empty` is pure Camp (delegates to `length`), but `length` is intrinsic — so `is_empty` is transitively intrinsic. Could be made directly intrinsic for performance (avoid counting all graphemes just to check empty).
- `from_bytes` uses `TryFrom(Bytes, Str, [InvalidUtf8])` per D19, but declaring it as a standalone function is simpler for now. The `TryFrom` instance can be added when the trait system supports it.
- No `walk_utf8` or `walk_graphemes` — iteration goes through `to_iter` which returns `Iter(Str)` (grapheme-by-grapheme).

---

## List Module

### Design

`List` is a **builtin type** declared as `@List(a): pub [Cons(a, List(a)) | Nil]`. The compiler provides list literals (`[1, 2, 3]`), pattern matching (`[h, ...t]`), and basic construction.

Per D8: List is lean — construction, structural access, sort, conversion. Iter does all transformation.

Most List operations **can** be implemented in pure Camp via pattern matching and recursion. The exceptions are:
- `List.sort` / `List.sort_by` — need Ord trait dispatch and merge sort (complex but doable in pure Camp)
- `List.from_iter` — needs Iter consumption (circular dependency; implemented after Iter)

### Implementation

```camp
-- List.camp
-- @List(a): pub [Cons(a, List(a)) | Nil]  -- declared by compiler

-- Construction

pub empty : List(a)
pub empty = Nil

pub singleton : a -> List(a)
pub singleton = |x| Cons(x, Nil)

pub append : List(a), List(a) -> List(a)
pub append = |xs, ys|
  match xs {
    Nil => ys
    Cons(h, t) => Cons(h, append(t, ys))
  }

-- Structural queries

pub length : List(a) -> I64
pub length = |xs|
  match xs {
    Nil => 0
    Cons(_, t) => 1 + length(t)
  }

pub is_empty : List(a) -> Bool
pub is_empty = |xs|
  match xs { Nil => True | Cons(_, _) => False }

-- Head/tail access (return Result per D3)

pub first : List(a) -> Result(a, [ListWasEmpty])
pub first = |xs|
  match xs {
    Cons(h, _) => Ok(h)
    Nil => Err(ListWasEmpty)
  }

pub last : List(a) -> Result(a, [ListWasEmpty])
pub last = |xs|
  match xs {
    Nil => Err(ListWasEmpty)
    Cons(h, Nil) => Ok(h)
    Cons(_, t) => last(t)
  }

pub rest : List(a) -> Result(List(a), [ListWasEmpty])
pub rest = |xs|
  match xs {
    Cons(_, t) => Ok(t)
    Nil => Err(ListWasEmpty)
  }

-- Sorting (needs Ord — implemented as intrinsic for now)

pub sort : List(a) -> List(a)
pub sort = |xs| crash "intrinsic: List.sort"

pub sort_by : List(a), (a, a) -> Order -> List(a)
pub sort_by = |xs, cmp| crash "intrinsic: List.sort_by"

-- Conversion (gateway to/from Iter)
-- These are implemented after Iter is available.

pub to_iter : List(a) -> Iter(a)
pub to_iter = |xs| crash "intrinsic: List.to_iter"

pub from_iter : Iter(a) -> List(a)
pub from_iter = |iter| crash "intrinsic: List.from_iter"
```

### Notes

- `append` is O(n) in the first list — standard immutable linked list. This is intentional; for frequent appending, use `List.from_iter` with `Iter.chain`.
- `last` is O(n) — walks to the end. This is inherent to linked lists.
- `sort`/`sort_by` are marked intrinsic for v1. A pure-Camp merge sort is possible but complex (needs Ord dispatch). Mark intrinsic until the trait system is mature enough.
- `to_iter`/`from_iter` bridge to Iter. Marked intrinsic to avoid circular dependency with Iter module. The runtime provides efficient implementations.
- No `map`, `filter`, `fold` — those live on `Iter`. Use `xs->to_iter()->map(f)->from_iter()`.
- No `head`/`tail` that return `Option` — use `first`/`rest` that return `Result(a, [ListWasEmpty])` per D3.

---

## Map Module

### Design

`Map` is an **opaque builtin type** — an ordered tree map (e.g., B-tree or red-black tree). The compiler/runtime provides the data structure. ALL operations are intrinsic — you cannot implement a balanced tree in pure Camp without mutation or FFI.

Per D7: Map MUST be ordered for referential transparency (hash maps have non-deterministic iteration order).
Per D20: `Map.update` uses `Result(v, [KeyNotFound])` callback, `Map.union` is left-biased, `Map.min`/`Map.max` included.

The type is declared as `@Map(k, v)` — a nominal opaque type. Its internal structure is not exposed to Camp code.

### Implementation

```camp
-- Map.camp
-- @Map(k, v) -- opaque ordered tree map, provided by runtime
-- Keys require Eq and Ord for ordered tree operations.

-- Construction

pub new : Map(k, v)
pub new = crash "intrinsic: Map.new"

pub singleton : k, v -> Map(k, v)
pub singleton = |k, v| crash "intrinsic: Map.singleton"

-- Lookup

pub get : k, Map(k, v) -> Result(v, [KeyNotFound])
pub get = |k, m| crash "intrinsic: Map.get"

pub contains : k, Map(k, v) -> Bool
pub contains = |k, m| crash "intrinsic: Map.contains"

pub size : Map(k, v) -> I64
pub size = |m| crash "intrinsic: Map.size"

pub is_empty : Map(k, v) -> Bool
pub is_empty = |m| size(m) == 0

-- Min/Max (O(log n) on ordered tree)

pub min : Map(k, v) -> Result((k, v), [EmptyMap])
pub min = |m| crash "intrinsic: Map.min"

pub max : Map(k, v) -> Result((k, v), [EmptyMap])
pub max = |m| crash "intrinsic: Map.max"

-- Modification

pub insert : k, v, Map(k, v) -> Map(k, v)
pub insert = |k, v, m| crash "intrinsic: Map.insert"

pub remove : k, Map(k, v) -> Map(k, v)
pub remove = |k, m| crash "intrinsic: Map.remove"

pub update : k, (Result(v, [KeyNotFound]) -> Result(v, [KeyNotFound])) -> Map(k, v) -> Map(k, v)
pub update = |k, f, m| crash "intrinsic: Map.update"

-- Transformation

pub map : Map(k, v), (v) -> w -> Map(k, w)
pub map = |m, f| crash "intrinsic: Map.map"

pub filter : Map(k, v), (k, v) -> Bool -> Map(k, v)
pub filter = |m, pred| crash "intrinsic: Map.filter"

pub fold : Map(k, v), b, (b, k, v) -> b -> b
pub fold = |m, init, f| crash "intrinsic: Map.fold"

-- Conversion

pub to_iter : Map(k, v) -> Iter((k, v))
pub to_iter = |m| crash "intrinsic: Map.to_iter"

pub keys : Map(k, v) -> Iter(k)
pub keys = |m| crash "intrinsic: Map.keys"

pub values : Map(k, v) -> Iter(v)
pub values = |m| crash "intrinsic: Map.values"

pub from_list : List((k, v)) -> Map(k, v)
pub from_list = |entries| crash "intrinsic: Map.from_list"

pub to_list : Map(k, v) -> List((k, v))
pub to_list = |m| crash "intrinsic: Map.to_list"

-- Set-like operations (efficient on ordered trees)

pub union : Map(k, v), Map(k, v) -> Map(k, v)
pub union = |m1, m2| crash "intrinsic: Map.union"

pub intersection : Map(k, v), Map(k, v) -> Map(k, v)
pub intersection = |m1, m2| crash "intrinsic: Map.intersection"

pub difference : Map(k, v), Map(k, v) -> Map(k, v)
pub difference = |m1, m2| crash "intrinsic: Map.difference"
```

### Notes

- `is_empty` is pure Camp (delegates to `size`), but `size` is intrinsic. Could be made directly intrinsic.
- `Map.update` signature: the callback receives `Result(v, [KeyNotFound])` — `Err(KeyNotFound)` if key absent, `Ok(v)` if present. Returns `Err(KeyNotFound)` to remove the key, `Ok(new_v)` to insert/update. Per D20.
- `Map.union` is left-biased on key conflict for v1. A `Map.union_with` taking a conflict-resolution function can be added later.
- All set-like operations (`union`, `intersection`, `difference`) are O(m+n) on ordered trees — efficient.
- `from_list`/`to_list` bridge to List. `from_list` is equivalent to `FromIter.from_iter` but provided as a convenience.

---

## Set Module

### Design

Per D21: Set is implemented as `Map(a, {})` internally. This means:
- The type declaration is `@Set(a)` (opaque, wraps `Map(a, {})`)
- All operations delegate to `Map` operations
- `Set.map` requires `Ord` on the output type (since the internal Map requires Ord on keys)

Most Set operations are intrinsic (they delegate to Map intrinsics). A few could be pure Camp wrappers, but marking them intrinsic allows the runtime to use a more efficient representation.

### Implementation

```camp
-- Set.camp
-- @Set(a) -- opaque, implemented as Map(a, {}) internally

-- Construction

pub new : Set(a)
pub new = crash "intrinsic: Set.new"

pub singleton : a -> Set(a)
pub singleton = |x| crash "intrinsic: Set.singleton"

-- Queries

pub contains : a, Set(a) -> Bool
pub contains = |x, s| crash "intrinsic: Set.contains"

pub size : Set(a) -> I64
pub size = |s| crash "intrinsic: Set.size"

pub is_empty : Set(a) -> Bool
pub is_empty = |s| size(s) == 0

pub min : Set(a) -> Result(a, [EmptySet])
pub min = |s| crash "intrinsic: Set.min"

pub max : Set(a) -> Result(a, [EmptySet])
pub max = |s| crash "intrinsic: Set.max"

-- Modification

pub insert : a, Set(a) -> Set(a)
pub insert = |x, s| crash "intrinsic: Set.insert"

pub remove : a, Set(a) -> Set(a)
pub remove = |x, s| crash "intrinsic: Set.remove"

-- Set operations

pub union : Set(a), Set(a) -> Set(a)
pub union = |s1, s2| crash "intrinsic: Set.union"

pub intersection : Set(a), Set(a) -> Set(a)
pub intersection = |s1, s2| crash "intrinsic: Set.intersection"

pub difference : Set(a), Set(a) -> Set(a)
pub difference = |s1, s2| crash "intrinsic: Set.difference"

pub symmetric_difference : Set(a), Set(a) -> Set(a)
pub symmetric_difference = |s1, s2| crash "intrinsic: Set.symmetric_difference"

pub is_subset : Set(a), Set(a) -> Bool
pub is_subset = |s1, s2| crash "intrinsic: Set.is_subset"

pub is_disjoint : Set(a), Set(a) -> Bool
pub is_disjoint = |s1, s2| crash "intrinsic: Set.is_disjoint"

-- Transformation

pub map : Set(a), (a) -> b -> Set(b)
pub map = |s, f| crash "intrinsic: Set.map"

pub filter : Set(a), (a) -> Bool -> Set(a)
pub filter = |s, pred| crash "intrinsic: Set.filter"

pub fold : Set(a), b, (b, a) -> b -> b
pub fold = |s, init, f| crash "intrinsic: Set.fold"

-- Conversion

pub to_iter : Set(a) -> Iter(a)
pub to_iter = |s| crash "intrinsic: Set.to_iter"

pub from_list : List(a) -> Set(a)
pub from_list = |xs| crash "intrinsic: Set.from_list"

pub to_list : Set(a) -> List(a)
pub to_list = |s| crash "intrinsic: Set.to_list"
```

### Notes

- `is_empty` is pure Camp (delegates to `size`).
- `Set.map` requires `Ord` on `b` — this is a trait constraint that the compiler must enforce. Since Camp traits don't have associated types and `Set.map` needs `Ord` on the output, this is a where clause: `where b is Ord`.
- `Set.symmetric_difference` = `(s1 union s2) difference (s1 intersection s2)` — provided as intrinsic for efficiency.
- `Set.is_subset` and `Set.is_disjoint` are O(m+n) on ordered trees.

---

## Iter Module

### Design

Per D2: `Iter.next` returns `[Yield(a) | Done]`.
Per D22: `Iter(a, e)` carries an effect row parameter. No standalone `collect` (use `FromIter.from_iter`). No `Iter.sorted`.

Iter is the most interesting module because **most operations CAN be implemented in pure Camp**. The type is a record of closures:

```
@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }
```

Key implementation challenges:
1. **Mutable state in closures** — iterators need `$` mutable variables to track position. Camp supports `$var` for mutable bindings.
2. **Recursion instead of while** — the recipe has no `while` keyword. Use tail-recursive helper functions.
3. **Effect rows** — `Iter(a, e)` carries effect row `e`. Functions that transform iterators propagate `e`.
4. **No `while`** — `fold`, `collect`, `for_each`, `find` need tail-recursive loops.

### Implementation

```camp
-- Iter.camp

@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }

-- Construction

pub empty : Iter(a, e)
pub empty = @{ next = || Done }

pub singleton : a -> Iter(a, e)
pub singleton = |x| @{
  $consumed = False
  next = || if $consumed { Done } else { $consumed = True; Yield(x) }
}

pub from_list : List(a) -> Iter(a, e)
pub from_list = |$list| @{
  next = ||
    match $list {
      Cons(head, rest) => $list = rest; Yield(head)
      Nil => Done
    }
}

-- Core transformations

pub map : Iter(a, e), (a) -> b -> Iter(b, e)
pub map = |iter, f| @{
  next = || match iter.next() {
    Yield(x) => Yield(f(x))
    Done => Done
  }
}

pub filter : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub filter = |iter, pred| @{
  next = ||
    match iter.next() {
      Yield(x) => if pred(x) { Yield(x) } else { iter.next() }
      Done => Done
    }
}

pub flat_map : Iter(a, e), (a) -> Iter(b, e) -> Iter(b, e)
pub flat_map = |iter, f| @{
  $inner = empty
  next = ||
    match $inner.next() {
      Yield(b) => Yield(b)
      Done => match iter.next() {
        Yield(a) => $inner = f(a); $inner.next()
        Done => Done
      }
    }
}

pub filter_map : Iter(a, e), (a) -> Result(b, err) -> Iter(b, e)
pub filter_map = |iter, f| @{
  next = ||
    match iter.next() {
      Yield(x) => match f(x) {
        Ok(b) => Yield(b)
        Err(_) => -- skip, try next
          match iter.next() {
            Yield(y) => match f(y) {
              Ok(b2) => Yield(b2)
              Err(_) => -- recursive: keep trying
              $inner = filter_map(iter, f)
              $inner.next()
            }
            Done => Done
          }
      }
      Done => Done
    }
}
```

Wait — `filter_map` with the recursive self-call inside a closure is problematic. Let me reconsider.

The issue: `filter_map` needs to skip items where `f` returns `Err` and try the next one. With the closure-based approach, when `f(x)` returns `Err`, we need to call `iter.next()` again. But we're inside the `next` closure already.

A simpler approach: make `filter_map` wrap `flat_map` + `filter`:

```camp
pub filter_map : Iter(a, e), (a) -> Result(b, err) -> Iter(b, e)
pub filter_map = |iter, f|
  flat_map(iter, |x| match f(x) {
    Ok(b) => singleton(b)
    Err(_) => empty
  })
```

This is cleaner! `flat_map` handles the "some yield, some skip" pattern naturally.

Let me rewrite the full Iter module more carefully.

```camp
-- Iter.camp

@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }

-- Construction

pub empty : Iter(a, e)
pub empty = @{ next = || Done }

pub singleton : a -> Iter(a, e)
pub singleton = |x| @{
  $consumed = False
  next = || if $consumed { Done } else { $consumed = True; Yield(x) }
}

pub from_list : List(a) -> Iter(a, e)
pub from_list = |$list| @{
  next = ||
    match $list {
      Cons(head, rest) => $list = rest; Yield(head)
      Nil => Done
    }
}

-- Core transformations

pub map : Iter(a, e), (a) -> b -> Iter(b, e)
pub map = |iter, f| @{
  next = || match iter.next() {
    Yield(x) => Yield(f(x))
    Done => Done
  }
}

pub filter : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub filter = |iter, pred| @{
  next = || loop(iter, pred)
}
-- Helper for filter (tail-recursive)
loop = |iter, pred|
  match iter.next() {
    Yield(x) => if pred(x) { Yield(x) } else { loop(iter, pred) }
    Done => Done
  }
```

Hmm, but `loop` as a free function is exposed. And the closure needs to capture `iter` and `pred`. Let me think about this differently.

Actually, the closure already captures `iter` and `pred` from the enclosing scope. The issue is that within the closure, we need to potentially call `iter.next()` multiple times until we find a matching element or exhaust the iterator.

In the current (old-syntax) code, `filter` just calls `iter.next()` again inside the `else` branch:
```
filter = |iter, pred| @{
  next = ||
    match iter.next() {
      Some(x) => if pred(x) { Some(x) } else { iter.next() },
      None => None,
    },
}
```

But this is wrong! If the first element doesn't match, calling `iter.next()` gives the second element, but if that also doesn't match, we stop. We'd need to keep going. The current implementation has a bug.

The correct implementation needs recursion or a loop. Since Camp doesn't have `while`, we need a recursive helper. Let me use a local recursive function:

```camp
pub filter : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub filter = |iter, pred| @{
  next = || find_next()
  find_next = || match iter.next() {
    Yield(x) => if pred(x) { Yield(x) } else { find_next() }
    Done => Done
  }
}
```

Wait, `find_next` is defined inside the record literal. Can we have local function definitions inside record literals? I'm not sure about Camp's scoping rules here.

Alternative: define `find_next` as a parameter to the outer function:

```camp
pub filter : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub filter = |iter, pred| {
  find_next = || match iter.next() {
    Yield(x) => if pred(x) { Yield(x) } else { find_next() }
    Done => Done
  }
  @{ next = find_next }
}
```

This should work! `find_next` is a local binding that captures `iter` and `pred`, and is recursive (references itself). The record is constructed with `next = find_next`.

Similarly, `fold` needs a recursive helper:

```camp
pub fold : Iter(a, e), b, (b, a) -> b -> b
pub fold = |iter, init, f| {
  go = |acc| match iter.next() {
    Yield(x) => go(f(acc, x))
    Done => acc
  }
  go(init)
}
```

OK, this pattern works. Let me now write the full Iter module.

Actually, I realize there's another issue with `filter`. The `find_next` function is recursive — it calls itself when `pred(x)` is False. But each call to `find_next()` calls `iter.next()`, which mutates the iterator. This works because `iter` is captured by the closure, and each call to `iter.next()` advances the iterator.

But there's a subtlety: `find_next` is a closure that captures `iter`. When we set `next = find_next`, the `next` field holds this closure. Each call to `iter.next()` from within `find_next` advances the iterator's internal state. So repeated calls to the outer `next()` will correctly skip non-matching elements.

Wait, actually there's a problem. The `next` field is set to `find_next`, which is a closure. But `find_next` is a recursive function. When we call `iter.next()` from outside (via the Iter's `next` field), it calls `find_next()`. If the first element doesn't match, `find_next()` calls itself recursively, which calls `iter.next()` again. This is correct.

But: when `find_next()` returns `Yield(x)` (found a match), the next call to the Iter's `next` field calls `find_next()` again — starting from where `iter` left off. This is also correct, because `iter`'s state has advanced past the yielded element.

Great, this works. Let me write the full Iter.

One more thing: the `flat_map` implementation. When we call `f(a)` on a yielded element, we get a new `Iter(b, e)`. We need to iterate through that inner iterator before moving to the next outer element.

```camp
pub flat_map : Iter(a, e), (a) -> Iter(b, e) -> Iter(b, e)
pub flat_map = |iter, f| @{
  $inner = empty
  next = || {
    -- Try inner iterator first
    match $inner.next() {
      Yield(b) => Yield(b)
      Done => -- Inner exhausted, get next outer and create new inner
        match iter.next() {
          Yield(a) => $inner = f(a); $inner.next()
          Done => Done
        }
    }
  }
}
```

Wait, but `$inner` is a mutable variable in the record closure. Each call to `next()` can update it. This should work: when the inner iterator is exhausted, we advance the outer and create a new inner.

But there's a problem: `$inner = empty` sets inner to the empty iterator. When `next()` is first called, `$inner.next()` returns `Done` immediately. Then we go to the outer, get `Yield(a)`, set `$inner = f(a)`, and call `$inner.next()`.

But what if `$inner.next()` after setting the new inner also returns `Done` (because `f(a)` returned an empty iterator)? Then we need to advance the outer again. The current code doesn't handle this — it would return `Done` from `$inner.next()`, but we're not in the right place to try again.

The fix: use a recursive helper for `flat_map` too:

```camp
pub flat_map : Iter(a, e), (a) -> Iter(b, e) -> Iter(b, e)
pub flat_map = |iter, f| @{
  $inner = empty
  next = || advance()
  advance = || match $inner.next() {
    Yield(b) => Yield(b)
    Done => match iter.next() {
      Yield(a) => $inner = f(a); advance()
      Done => Done
    }
  }
}
```

When the inner is exhausted and we get a new outer element, we set `$inner = f(a)` and recursively call `advance()`. If `f(a)` returned an empty iterator, `advance()` will see `$inner.next() => Done` again, go back to the outer, get the next element, etc. This is correct.

OK, let me now write the complete Iter module. I'll also handle `fold`, `collect`, `for_each`, `find`, `any`, `all`, `contains`, `take`, `skip`, `take_while`, `skip_while`, `chain`, `zip`, `enumerate`.

For `fold`:
```camp
pub fold : Iter(a, e), b, (b, a) -> b -> b
pub fold = |iter, init, f| {
  go = |acc| match iter.next() {
    Yield(x) => go(f(acc, x))
    Done => acc
  }
  go(init)
}
```

For `for_each`:
```camp
pub for_each : Iter(a, e), (a) -> () -> ()
pub for_each = |iter, f| {
  go = || match iter.next() {
    Yield(x) => f(x); go()
    Done => {}
  }
  go()
}
```

For `count`:
```camp
pub count : Iter(a, e) -> I64
pub count = |iter| fold(iter, 0, |n, _| n + 1)
```

For `find`:
```camp
pub find : Iter(a, e), (a) -> Bool -> Result(a, [NotFound])
pub find = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if pred(x) { Ok(x) } else { go() }
    Done => Err(NotFound)
  }
  go()
}
```

For `any`/`all`:
```camp
pub any : Iter(a, e), (a) -> Bool -> Bool
pub any = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if pred(x) { True } else { go() }
    Done => False
  }
  go()
}

pub all : Iter(a, e), (a) -> Bool -> Bool
pub all = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if not pred(x) { False } else { go() }
    Done => True
  }
  go()
}
```

For `contains`:
```camp
pub contains : Iter(a, e), a -> Bool
pub contains = |iter, target| any(iter, |x| Eq.eq(x, target))
```

Wait, `Eq.eq` is a trait method. Camp's trait dispatch works via `Eq.eq(x, target)` qualified syntax. But we need `a` to implement `Eq`. This is a trait constraint. In Camp, where clauses go on the function definition.

Actually, `contains` needs `where a is Eq`. The syntax is:
```camp
pub contains : Iter(a, e), a -> Bool where a is Eq
```

Hmm, but the recipe says `where` clauses are on function declarations. Let me check... The recipe says:
- Generic: `add = |x: a, y: a| -> a where a is Add { x + y }`
- where clause: `|items| where a is Ord { ... }`

So `where a is Eq` goes after the type signature. Let me include it.

For `take`/`skip`:
```camp
pub take : Iter(a, e), I64 -> Iter(a, e)
pub take = |iter, n| @{
  $remaining = n
  next = || if $remaining <= 0 { Done } else {
    $remaining = $remaining - 1
    iter.next()
  }
}

pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| {
  $skipped = False
  $to_skip = n
  go = || {
    if not $skipped {
      while $to_skip > 0 {  -- wait, no while in recipe!
    }
  }
}
```

Hmm, `skip` needs to advance the iterator N times before yielding. Without `while`, we need a recursive helper:

```camp
pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| @{
  $remaining = n
  next = || {
    drain = || if $remaining > 0 {
      $remaining = $remaining - 1
      match iter.next() { Yield(_) => drain() | Done => {} }
      iter.next()  -- wrong! after drain, we already consumed one
    }
  }
}
```

This is getting complicated. Let me think about `skip` more carefully.

`skip(iter, n)` should:
1. When first called, advance `iter` N times (consuming and discarding N elements)
2. Then yield all remaining elements

The problem: we need to do the skipping lazily (only when `next()` is first called), not eagerly at construction time.

```camp
pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| @{
  $remaining = n
  next = || {
    -- Drain remaining elements to skip
    skip_remaining = || if $remaining > 0 {
      $remaining = $remaining - 1
      match iter.next() {
        Yield(_) => skip_remaining()
        Done => Done
      }
    } else {
      -- All skipped, now pass through
      iter.next()
    }
    skip_remaining()
  }
}
```

Wait, this has a type problem. `skip_remaining()` returns `[Yield(a) | Done]` in the base case (when remaining <= 0, it returns `iter.next()` which is `[Yield(a) | Done]`). But in the recursive case, after consuming an element and calling `skip_remaining()` again, it eventually reaches the base case and returns the result.

Actually, the issue is that when `$remaining > 0`, we consume an element via `iter.next()`. If it's `Yield(_)`, we recurse. If it's `Done`, the iterator is exhausted, and we should return `Done`. Let me fix:

```camp
pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| @{
  $remaining = n
  next = || {
    go = || {
      if $remaining > 0 {
        $remaining = $remaining - 1
        match iter.next() {
          Yield(_) => go()
          Done => Done
        }
      } else {
        iter.next()
      }
    }
    go()
  }
}
```

Hmm, but `go` is defined inside the `next` closure. Can we have nested function definitions inside closures? I think so — Camp allows local bindings, and a function binding is just a binding whose value is a closure.

Actually, let me reconsider the approach. Instead of defining `go` inside `next`, define it as a captured local:

```camp
pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| {
  $remaining = n
  go = || {
    if $remaining > 0 {
      $remaining = $remaining - 1
      match iter.next() {
        Yield(_) => go()
        Done => Done
      }
    } else {
      iter.next()
    }
  }
  @{ next = go }
}
```

This is cleaner. `go` captures `$remaining` and `iter`, and is recursive. The record's `next` field is set to `go`.

But wait: `go` is a closure that captures `$remaining` (mutable). Each call to `go()` decrements `$remaining`. But `$remaining` is shared between all calls to `go` (they capture the same mutable variable). So the first call to `next()` will skip N elements, and subsequent calls will pass through directly (since `$remaining` is now 0). This is correct!

OK, I think I have a workable approach. Let me write the full Iter module now.

For `take_while`/`skip_while`:
```camp
pub take_while : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub take_while = |iter, pred| @{
  $done = False
  next = || {
    if $done { Done } else {
      match iter.next() {
        Yield(x) => if pred(x) { Yield(x) } else { $done = True; Done }
        Done => Done
      }
    }
  }
}

pub skip_while : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub skip_while = |iter, pred| {
  $skipping = True
  go = || {
    if $skipping {
      match iter.next() {
        Yield(x) => if pred(x) { go() } else { $skipping = False; Yield(x) }
        Done => Done
      }
    } else {
      iter.next()
    }
  }
  @{ next = go }
}
```

For `chain`:
```camp
pub chain : Iter(a, e), Iter(a, e) -> Iter(a, e)
pub chain = |first, second| @{
  next = || match first.next() {
    Yield(x) => Yield(x)
    Done => second.next()
  }
}
```

For `zip`:
```camp
pub zip : Iter(a, e), Iter(b, e) -> Iter((a, b), e)
pub zip = |left, right| @{
  next = ||
    match left.next() {
      Yield(a) => match right.next() {
        Yield(b) => Yield((a, b))
        Done => Done
      }
      Done => Done
    }
}
```

For `enumerate`:
```camp
pub enumerate : Iter(a, e) -> Iter((I64, a), e)
pub enumerate = |iter| @{
  $index = 0
  next = || match iter.next() {
    Yield(x) => idx = $index; $index = $index + 1; Yield((idx, x))
    Done => Done
  }
}
```

Wait, `idx = $index` captures the current value of `$index` before incrementing. But the recipe says "No shadowing". If `idx` is a fresh binding, it's fine — it's not shadowing `$index` (different name).

Actually, looking at the syntax more carefully: `idx = $index` creates a new immutable binding `idx` with the current value of `$index`. Then `$index = $index + 1` mutates the existing mutable binding. This should work.

But wait: in a single expression, is `idx = $index; $index = $index + 1; Yield((idx, x))` valid? The `;` separator... actually, the recipe says newline-separated statements in blocks. But we're inside a match arm, which is a single expression. Can we have multiple statements?

Looking at the recipe: "Blocks: `{ stmt1\nstmt2\nresult_expr }`". And match arms use `=> body`. The body is a single expression, but could be a block.

So the enumerate case should be:
```camp
Yield(x) => {
  idx = $index
  $index = $index + 1
  Yield((idx, x))
}
```

Let me rewrite with block syntax for multi-statement match arms.

OK, let me now write the complete Iter module with all these corrections. I need to be very careful about syntax.

Let me also reconsider `filter_map`. The simplest implementation is via `flat_map`:

```camp
pub filter_map : Iter(a, e), (a) -> Result(b, err) -> Iter(b, e)
pub filter_map = |iter, f|
  flat_map(iter, |x| match f(x) {
    Ok(b) => singleton(b)
    Err(_) => empty
  })
```

This is clean and correct. `flat_map` handles the "some yield, some skip" pattern by creating a singleton or empty iterator for each element.

Now let me put it all together.

Actually wait, I also need to think about effect rows. The `Iter(a, e)` type has effect row `e`. Functions that create new iterators should propagate `e`. Functions that consume iterators (fold, for_each, find) should have effect `-[e]->`.

Let me annotate the type signatures properly.

For `map`:
```camp
pub map : (Iter(a, e), (a) -> b) -> Iter(b, e)
```

But the closure `f` might also have effects! If `f` is `|x| -[Console!]-> b`, then calling `f(x)` inside `next` adds `Console!` to the effect row. So the result iterator's effect row should include both `e` (from `iter.next`) and whatever effects `f` has.

This is where effect row inference becomes important. In Camp, the effect row of the resulting Iter should be `e | effects_of_f`. But without HKT and with the current trait system, expressing this precisely is tricky.

For now, I'll use a simplified approach: assume that `f` and `pred` closures are pure (no extra effects beyond `e`). The compiler's type inference will handle the actual effect merging. This matches how Koka handles it — effect rows are inferred and merged automatically.

Actually, looking at the current old-syntax code, the signatures use `-[e]->` for the closure and `Iter(a)` (no effect param). The design notes (D22) say `Iter(a, e)` with effect row parameter. But the exact syntax for generic effect rows on function signatures is still evolving.

For now, I'll write the function bodies correctly and use simplified type signatures. The compiler's type inference should handle effect row propagation.

Let me write the final Iter module now. I'll use the approach of local recursive functions and mutable variables.

Actually, I realize there's one more syntax question. The `@Iter(a, e): { next: ... }` declaration uses `@` for nominal type. But construction would be `@Iter({ next = ... })`. Is this the right syntax?

Per the recipe:
- `@Name(params): body` for declaration
- `@Name(args)` for construction (when constructor name = type name, i.e., newtype pattern)
- Records: `{ field: Type }` in types, `{ field = value }` in construction

So `@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }` declares Iter as a nominal type wrapping a record.

Construction: `@Iter({ next = || Yield(42) })`.

But wait, that's verbose. Can we use record update syntax? No, this is construction, not update.

Hmm, actually looking at the recipe more carefully: `@UserId: I64` desugars to `@UserId: pub [UserId(I64)]`. So a nominal type with a record body would be `@Iter(a, e): { next: ... }`, and construction would be `@Iter({ next = ... })`.

This is a lot of boilerplate. Can we just use bare record construction without `@Iter(...)`? No — because Iter is a nominal type, you need the `@Iter` wrapper for type safety.

OK, this is the correct syntax. It's verbose but correct.

But wait — if `@Iter` is a nominal type wrapping a record, then to access `iter.next`, you'd need to "unwrap" the nominal type first. In Roc, newtype access is automatic. In Camp, does `iter.next` work on a nominal type wrapping a record?

The recipe says:
- `obj.field` — field access
- For a nominal type wrapping a record, I think field access should work transparently (zero-cost abstraction)

Let me assume this works. If not, we'd need `match iter { @Iter(r) => r.next }` which is terrible.

Actually, looking at the recipe's method block:
```
@Counter : U64 {
  increment = |self: Self| -> Self { @Counter(self + 1) }
}
```

Here, `@Counter` wraps `U64`. Methods defined in the method block access `self` which is the unwrapped value. For `@Iter` wrapping a record, methods in the method block would access `self.next`. But we're not defining methods in a method block — we're just using field access.

I think `iter.next` should work on `@Iter({ next = fn })` because the nominal type is transparent for field access. This is the zero-cost newtype abstraction pattern.

OK, let me write the final files. Let me also think about `Num`.

For Num, per D27: `Num` is a namespace with per-type submodules. The directory structure would be:

```
stdlib/
  Num/
    I64.camp
    I32.camp
    I16.camp
    I8.camp
    U64.camp
    U32.camp
    U16.camp
    U8.camp
    F64.camp
    F32.camp
```

Each submodule provides operations for its type. The numeric types themselves (I64, F64, etc.) are builtin — the compiler provides them. The Num submodules provide functions like `abs`, `clamp`, `max`, `min`, `to_str`, `from_str`, etc.

Arithmetic operators (`+`, `-`, `*`, `/`, `%`) are built into the language — they don't need stdlib functions.

For I64:
```camp
-- Num/I64.camp

pub abs : I64 -> I64
pub abs = |n| if n < 0 { 0 - n } else { n }

pub clamp : I64, I64, I64 -> I64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : I64, I64 -> I64
pub max = |a, b| if a > b { a } else { b }

pub min : I64, I64 -> I64
pub min = |a, b| if a < b { a } else { b }

pub to_str : I64 -> Str
pub to_str = |n| crash "intrinsic: Num.I64.to_str"

pub from_str : Str -> Result(I64, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.I64.from_str"

pub range : I64, I64 -> Iter(I64)
pub range = |start, end| crash "intrinsic: Num.I64.range"

pub checked_add : I64, I64 -> Result(I64, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.I64.checked_add"

pub checked_sub : I64, I64 -> Result(I64, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.I64.checked_sub"

pub checked_mul : I64, I64 -> Result(I64, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.I64.checked_mul"

pub wrapping_add : I64, I64 -> I64
pub wrapping_add = |a, b| crash "intrinsic: Num.I64.wrapping_add"

pub saturating_add : I64, I64 -> I64
pub saturating_add = |a, b| crash "intrinsic: Num.I64.saturating_add"

-- Bitwise operations (intrinsic for efficiency, but could be pure Camp via operators)
pub bitwise_and : I64, I64 -> I64
pub bitwise_and = |a, b| a & b

pub bitwise_or : I64, I64 -> I64
pub bitwise_or = |a, b| a | b

pub bitwise_xor : I64, I64 -> I64
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : I64 -> I64
pub bitwise_not = |a| ~a

pub shift_left : I64, I64 -> I64
pub shift_left = |a, n| a << n

pub shift_right : I64, I64 -> I64
pub shift_right = |a, n| a >> n
```

Wait, bitwise operations are already operators in the language (`& | ^ ~ << >>`). Do we need function wrappers? Looking at Gleam and Roc:
- Gleam: Has `bitwise_and`, `bitwise_or`, etc. as functions (no operator syntax for bitwise)
- Roc: Uses `Num.bitwise_and`, etc.
- Rust: Uses operator syntax

Since Camp already has `& | ^ ~ << >>` as operators, we might not need function wrappers. But for UFCS (e.g., `n->bitwise_and(mask)`), having function forms is useful.

Actually, for UFCS, you'd write `n->Num.I64.bitwise_and(mask)`. That's verbose. Better to just use `n & mask`.

Let me keep the bitwise functions for completeness but note they're just wrappers around operators.

For F64:
```camp
-- Num/F64.camp

pub abs : F64 -> F64
pub abs = |n| crash "intrinsic: Num.F64.abs"

pub clamp : F64, F64, F64 -> F64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : F64, F64 -> F64
pub max = |a, b| crash "intrinsic: Num.F64.max"  -- handles NaN

pub min : F64, F64 -> F64
pub min = |a, b| crash "intrinsic: Num.F64.min"  -- handles NaN

pub sqrt : F64 -> F64
pub sqrt = |n| crash "intrinsic: Num.F64.sqrt"

pub ceiling : F64 -> F64
pub ceiling = |n| crash "intrinsic: Num.F64.ceiling"

pub floor : F64 -> F64
pub floor = |n| crash "intrinsic: Num.F64.floor"

pub round : F64 -> F64
pub round = |n| crash "intrinsic: Num.F64.round"

pub truncate : F64 -> F64
pub truncate = |n| crash "intrinsic: Num.F64.truncate"

pub to_str : F64 -> Str
pub to_str = |n| crash "intrinsic: Num.F64.to_str"

pub from_str : Str -> Result(F64, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.F64.from_str"

pub is_nan : F64 -> Bool
pub is_nan = |n| crash "intrinsic: Num.F64.is_nan"

pub is_infinite : F64 -> Bool
pub is_infinite = |n| crash "intrinsic: Num.F64.is_infinite"

pub pi : F64
pub pi = 3.14159265358979323846

pub e : F64
pub e = 2.71828182845904523536

-- Trigonometry (intrinsic — needs libm)
pub sin : F64 -> F64
pub sin = |n| crash "intrinsic: Num.F64.sin"

pub cos : F64 -> F64
pub cos = |n| crash "intrinsic: Num.F64.cos"

pub tan : F64 -> F64
pub tan = |n| crash "intrinsic: Num.F64.tan"

pub asin : F64 -> F64
pub asin = |n| crash "intrinsic: Num.F64.asin"

pub acos : F64 -> F64
pub acos = |n| crash "intrinsic: Num.F64.acos"

pub atan : F64 -> F64
pub atan = |n| crash "intrinsic: Num.F64.atan"

pub atan2 : F64, F64 -> F64
pub atan2 = |y, x| crash "intrinsic: Num.F64.atan2"

-- Exponential/Logarithmic
pub exp : F64 -> F64
pub exp = |n| crash "intrinsic: Num.F64.exp"

pub log : F64 -> F64
pub log = |n| crash "intrinsic: Num.F64.log"

pub log2 : F64 -> F64
pub log2 = |n| crash "intrinsic: Num.F64.log2"

pub log10 : F64 -> F64
pub log10 = |n| crash "intrinsic: Num.F64.log10"

-- Power
pub pow : F64, F64 -> F64
pub pow = |base, exp| crash "intrinsic: Num.F64.pow"
```

Note: `F64.abs` is intrinsic because it needs to handle the sign bit directly. `F64.max`/`F64.min` are intrinsic because of NaN handling (NaN comparisons are special in IEEE 754). `F64.clamp` can be pure Camp if we don't worry about NaN, but it's safer to make it intrinsic.

For the other integer types (I8, I16, I32, U8, U16, U32, U64), the module structure is similar to I64 but with different type annotations. Many operations are the same.

OK, I think I have enough to write the full implementation spec. Let me now create the document.

Actually, let me reconsider the `Num` module structure. Since each integer type has nearly identical functions, maybe we should have a shared template and then specialize. But Camp doesn't have HKT or macros, so we'd need to repeat the definitions for each type.

For the implementation spec, I'll write out I64 and F64 fully, then describe the pattern for the other 8 types.

Let me also reconsider the `Iter` type declaration. Currently it's `@Iter(a, e): { next: ... }`. But `@Iter` is a nominal type. When we construct `@Iter({ next = ... })`, is this the right syntax?

Actually, per the recipe, `@Name(args)` in expression position is for newtype construction. So `@Iter({ next = fn })` constructs an `Iter` value from a record. This should work.

But wait — the recipe says `@UserId(42)` is construction, and `@UserId: I64` is the declaration. So `@Iter({ next = fn })` would be `@Iter` applied to a record argument. But `@Iter` takes two type params `(a, e)` — does it also take a value argument?

I think the syntax is:
- Declaration: `@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }`
- Construction: `@Iter({ next = || Yield(42) })`

The type params are inferred from the record type. This is consistent with how `@UserId(42)` works — `UserId` wraps `I64`, and `@UserId(42)` constructs it with value `42`. Similarly, `Iter(a, e)` wraps a record, and `@Iter({ next = fn })` constructs it with the record value.

OK, this should work. Let me write the full spec now.

One more thing — I need to decide whether `Iter` is a nominal type (`@Iter`) or just a type alias. If it's a type alias:
```
Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }
```

Then construction is just `{ next = fn }` (a bare record). No `@Iter` wrapper needed. Field access is `iter.next`.

But then `Iter` is structurally typed — any record with a `next` field of the right type is an `Iter`. This loses nominal type safety. You could accidentally pass any record with a `next` field as an Iter.

With `@Iter`, it's nominally typed — only explicitly constructed `@Iter(...)` values are of type `Iter`. This is safer.

The design notes say `@Iter : (a, e) @{ ... }`, using `@`. Let me go with nominal type.

OK, let me now write the comprehensive spec document.</think>Now let me write the comprehensive implementation spec.<tool_call>write<arg_key>content</arg_key><arg_value># Stdlib Module Implementation Specification

Defines the exact `.camp` source files for 6 core stdlib modules: `Str`, `List`, `Map`, `Set`, `Iter`, `Num`.

## Syntax Convention

All code follows `docs/syntax-recipe.md`:
- Type params: `(a, e)` not `<a, e>`
- Pure function arrow: `->` not `-[]->`
- Effectful: `-[Effect!]->`
- Iter result: `[Yield(a) | Done]` not `[Some(a) | None]`
- Mutable vars: `$` prefix
- No `while` — use tail-recursive helpers
- No `Option` — use `Result(a, [SpecificTag])`
- Nominal types: `@Name(params): body`
- `@` prefix on construction when constructor = type name (newtype)

## Intrinsic Convention

Functions requiring runtime/WASM support use `crash "intrinsic: Module.function"`. The compiler's lowering pass recognizes these signatures and replaces them with calls to the Odin/WASM runtime.

---

## 1. Str Module

**All operations are intrinsic.** UTF-8/Unicode/grapheme handling requires runtime support.

Per D18: `Str.length` counts graphemes, `Str.slice` is grapheme-safe, case ops are Unicode, `split_first`/`split_last` return `Result((Str, Str), [NotFound])`.

```camp
-- Str.camp
-- Str is a builtin type. This file declares the public API.
-- All functions are intrinsic (require runtime UTF-8/Unicode support).

-- Queries
pub length : Str -> I64
pub length = |s| crash "intrinsic: Str.length"

pub byte_size : Str -> I64
pub byte_size = |s| crash "intrinsic: Str.byte_size"

pub is_empty : Str -> Bool
pub is_empty = |s| byte_size(s) == 0

-- Comparison
pub starts_with : Str, Str -> Bool
pub starts_with = |s, prefix| crash "intrinsic: Str.starts_with"

pub ends_with : Str, Str -> Bool
pub ends_with = |s, suffix| crash "intrinsic: Str.ends_with"

pub contains : Str, Str -> Bool
pub contains = |s, substr| crash "intrinsic: Str.contains"

-- Slicing (grapheme-safe)
pub take : Str, I64 -> Str
pub take = |s, n| crash "intrinsic: Str.take"

pub drop : Str, I64 -> Str
pub drop = |s, n| crash "intrinsic: Str.drop"

pub slice : Str, I64, I64 -> Str
pub slice = |s, start, len| crash "intrinsic: Str.slice"

-- Splitting
pub split : Str, Str -> List(Str)
pub split = |s, sep| crash "intrinsic: Str.split"

pub split_first : Str, Str -> Result((Str, Str), [NotFound])
pub split_first = |s, sep| crash "intrinsic: Str.split_first"

pub split_last : Str, Str -> Result((Str, Str), [NotFound])
pub split_last = |s, sep| crash "intrinsic: Str.split_last"

-- Trimming (Unicode whitespace)
pub trim : Str -> Str
pub trim = |s| crash "intrinsic: Str.trim"

pub trim_start : Str -> Str
pub trim_start = |s| crash "intrinsic: Str.trim_start"

pub trim_end : Str -> Str
pub trim_end = |s| crash "intrinsic: Str.trim_end"

-- Case (Unicode)
pub to_lower : Str -> Str
pub to_lower = |s| crash "intrinsic: Str.to_lower"

pub to_upper : Str -> Str
pub to_upper = |s| crash "intrinsic: Str.to_upper"

-- Concatenation
pub concat : Str, Str -> Str
pub concat = |a, b| crash "intrinsic: Str.concat"

pub join : List(Str), Str -> Str
pub join = |parts, sep| crash "intrinsic: Str.join"

pub repeat : Str, I64 -> Str
pub repeat = |s, n| crash "intrinsic: Str.repeat"

-- Replacement
pub replace : Str, Str, Str -> Str
pub replace = |s, pattern, replacement| crash "intrinsic: Str.replace"

pub replace_first : Str, Str, Str -> Str
pub replace_first = |s, pattern, replacement| crash "intrinsic: Str.replace_first"

-- Prefix/Suffix manipulation
pub drop_prefix : Str, Str -> Str
pub drop_prefix = |s, prefix| crash "intrinsic: Str.drop_prefix"

pub drop_suffix : Str, Str -> Str
pub drop_suffix = |s, suffix| crash "intrinsic: Str.drop_suffix"

-- Conversion
pub to_bytes : Str -> Bytes
pub to_bytes = |s| crash "intrinsic: Str.to_bytes"

pub from_bytes : Bytes -> Result(Str, [InvalidUtf8])
pub from_bytes = |b| crash "intrinsic: Str.from_bytes"

pub from_bytes_lossy : Bytes -> Str
pub from_bytes_lossy = |b| crash "intrinsic: Str.from_bytes_lossy"

-- Parsing (numeric)
pub to_i64 : Str -> Result(I64, [InvalidFormat])
pub to_i64 = |s| crash "intrinsic: Str.to_i64"

pub to_f64 : Str -> Result(F64, [InvalidFormat])
pub to_f64 = |s| crash "intrinsic: Str.to_f64"

-- Iteration (grapheme-by-grapheme)
pub to_iter : Str -> Iter(Str)
pub to_iter = |s| crash "intrinsic: Str.to_iter"
```

### Design Notes

- `is_empty` uses `byte_size` not `length` — O(1) vs O(n). A zero-byte string is always empty regardless of grapheme count.
- No `walk_utf8`/`walk_graphemes` — iteration goes through `to_iter` → `Iter(Str)`.
- `from_bytes` implements `TryFrom(Bytes, Str, [InvalidUtf8])` per D19. A separate `TryFrom` instance can be added when the trait system supports it.
- No `to_i8`/`to_i32` etc. — use `Str.to_i64` then `Num.I32.from_i64` for narrowing conversions.
- `drop_prefix`/`drop_suffix` return `Str` unconditionally (not Result) — if prefix/suffix not present, returns the original string unchanged. Matches Roc's behavior.

---

## 2. List Module

**Mostly pure Camp.** List is a builtin type with pattern matching support. Construction, structural access, and conversion are implemented. Sort and Iter conversion are intrinsic.

Per D8: Lean List — construction, structural access, sort, conversion. Iter does all transformation.

```camp
-- List.camp
-- @List(a): pub [Cons(a, List(a)) | Nil]  -- declared by compiler

-- Construction

pub empty : List(a)
pub empty = Nil

pub singleton : a -> List(a)
pub singleton = |x| Cons(x, Nil)

pub append : List(a), List(a) -> List(a)
pub append = |xs, ys|
  match xs {
    Nil => ys
    Cons(h, t) => Cons(h, append(t, ys))
  }

-- Structural queries

pub length : List(a) -> I64
pub length = |xs|
  match xs {
    Nil => 0
    Cons(_, t) => 1 + length(t)
  }

pub is_empty : List(a) -> Bool
pub is_empty = |xs|
  match xs { Nil => True | Cons(_, _) => False }

-- Head/tail access (Result per D3)

pub first : List(a) -> Result(a, [ListWasEmpty])
pub first = |xs|
  match xs {
    Cons(h, _) => Ok(h)
    Nil => Err(ListWasEmpty)
  }

pub last : List(a) -> Result(a, [ListWasEmpty])
pub last = |xs|
  match xs {
    Nil => Err(ListWasEmpty)
    Cons(h, Nil) => Ok(h)
    Cons(_, t) => last(t)
  }

pub rest : List(a) -> Result(List(a), [ListWasEmpty])
pub rest = |xs|
  match xs {
    Cons(_, t) => Ok(t)
    Nil => Err(ListWasEmpty)
  }

-- Sorting (intrinsic — needs Ord dispatch + merge sort)

pub sort : List(a) -> List(a)
pub sort = |xs| crash "intrinsic: List.sort"

pub sort_by : List(a), (a, a) -> Order -> List(a)
pub sort_by = |xs, cmp| crash "intrinsic: List.sort_by"

-- Conversion (gateway to/from Iter)

pub to_iter : List(a) -> Iter(a)
pub to_iter = |xs| crash "intrinsic: List.to_iter"

pub from_iter : Iter(a) -> List(a)
pub from_iter = |iter| crash "intrinsic: List.from_iter"
```

### Design Notes

- `append` is O(n) in first list. For frequent appends, use Iter: `xs->to_iter()->chain(ys->to_iter())->from_iter()`.
- `last` is O(n) — inherent to linked lists. For frequent last access, consider `List.from_iter(iter->collect())` with a different data structure.
- No `map`, `filter`, `fold`, `head`, `tail` — those are on Iter. Use `xs->to_iter()->map(f)->from_iter()`.
- `sort`/`sort_by` are intrinsic for v1. A pure-Camp merge sort requires Ord trait dispatch, which the compiler doesn't fully support yet.

---

## 3. Map Module

**All operations are intrinsic.** Ordered tree map requires runtime support — cannot be implemented in pure Camp.

Per D7: MUST be ordered (not hash-based) for referential transparency.
Per D20: `Map.update` uses `Result(v, [KeyNotFound])` callback, `Map.union` left-biased, `Map.min`/`Map.max` included.

```camp
-- Map.camp
-- @Map(k, v) -- opaque ordered tree map, provided by runtime
-- Keys require Eq and Ord for ordered tree operations.

-- Construction

pub new : Map(k, v)
pub new = crash "intrinsic: Map.new"

pub singleton : k, v -> Map(k, v)
pub singleton = |k, v| crash "intrinsic: Map.singleton"

-- Lookup

pub get : k, Map(k, v) -> Result(v, [KeyNotFound])
pub get = |k, m| crash "intrinsic: Map.get"

pub contains : k, Map(k, v) -> Bool
pub contains = |k, m| crash "intrinsic: Map.contains"

pub size : Map(k, v) -> I64
pub size = |m| crash "intrinsic: Map.size"

pub is_empty : Map(k, v) -> Bool
pub is_empty = |m| size(m) == 0

-- Min/Max (O(log n) on ordered tree)

pub min : Map(k, v) -> Result((k, v), [EmptyMap])
pub min = |m| crash "intrinsic: Map.min"

pub max : Map(k, v) -> Result((k, v), [EmptyMap])
pub max = |m| crash "intrinsic: Map.max"

-- Modification

pub insert : k, v, Map(k, v) -> Map(k, v)
pub insert = |k, v, m| crash "intrinsic: Map.insert"

pub remove : k, Map(k, v) -> Map(k, v)
pub remove = |k, m| crash "intrinsic: Map.remove"

-- Update: callback receives Err(KeyNotFound) if absent, Ok(v) if present.
-- Return Err(KeyNotFound) to remove, Ok(new_v) to insert/update.
pub update : k, (Result(v, [KeyNotFound]) -> Result(v, [KeyNotFound])) -> Map(k, v) -> Map(k, v)
pub update = |k, f, m| crash "intrinsic: Map.update"

-- Transformation

pub map : Map(k, v), (v) -> w -> Map(k, w)
pub map = |m, f| crash "intrinsic: Map.map"

pub filter : Map(k, v), (k, v) -> Bool -> Map(k, v)
pub filter = |m, pred| crash "intrinsic: Map.filter"

pub fold : Map(k, v), b, (b, k, v) -> b -> b
pub fold = |m, init, f| crash "intrinsic: Map.fold"

-- Conversion

pub to_iter : Map(k, v) -> Iter((k, v))
pub to_iter = |m| crash "intrinsic: Map.to_iter"

pub keys : Map(k, v) -> Iter(k)
pub keys = |m| crash "intrinsic: Map.keys"

pub values : Map(k, v) -> Iter(v)
pub values = |m| crash "intrinsic: Map.values"

pub from_list : List((k, v)) -> Map(k, v)
pub from_list = |entries| crash "intrinsic: Map.from_list"

pub to_list : Map(k, v) -> List((k, v))
pub to_list = |m| crash "intrinsic: Map.to_list"

-- Set-like operations (efficient on ordered trees)

pub union : Map(k, v), Map(k, v) -> Map(k, v)
pub union = |m1, m2| crash "intrinsic: Map.union"

pub intersection : Map(k, v), Map(k, v) -> Map(k, v)
pub intersection = |m1, m2| crash "intrinsic: Map.intersection"

pub difference : Map(k, v), Map(k, v) -> Map(k, v)
pub difference = |m1, m2| crash "intrinsic: Map.difference"
```

### Design Notes

- `Map.update` signature follows Roc's pattern: callback receives `Result(v, [KeyNotFound])`. Returns `Ok(new_v)` to set, `Err(KeyNotFound)` to remove. This unifies insert/update/remove in one operation.
- `Map.union` is left-biased for v1. A future `Map.union_with` can take a conflict-resolution function `(v, v) -> v`.
- `is_empty` is pure Camp (delegates to `size`), but could be made directly intrinsic for O(1) check.
- `from_list`/`to_list` are convenience bridges. The `FromIter`/`IntoIter` trait instances provide the same functionality generically.

---

## 4. Set Module

**All operations are intrinsic.** Implemented as `Map(a, {})` internally (per D21).

```camp
-- Set.camp
-- @Set(a) -- opaque, Map(a, {}) internally

-- Construction

pub new : Set(a)
pub new = crash "intrinsic: Set.new"

pub singleton : a -> Set(a)
pub singleton = |x| crash "intrinsic: Set.singleton"

-- Queries

pub contains : a, Set(a) -> Bool
pub contains = |x, s| crash "intrinsic: Set.contains"

pub size : Set(a) -> I64
pub size = |s| crash "intrinsic: Set.size"

pub is_empty : Set(a) -> Bool
pub is_empty = |s| size(s) == 0

pub min : Set(a) -> Result(a, [EmptySet])
pub min = |s| crash "intrinsic: Set.min"

pub max : Set(a) -> Result(a, [EmptySet])
pub max = |s| crash "intrinsic: Set.max"

-- Modification

pub insert : a, Set(a) -> Set(a)
pub insert = |x, s| crash "intrinsic: Set.insert"

pub remove : a, Set(a) -> Set(a)
pub remove = |x, s| crash "intrinsic: Set.remove"

-- Set operations

pub union : Set(a), Set(a) -> Set(a)
pub union = |s1, s2| crash "intrinsic: Set.union"

pub intersection : Set(a), Set(a) -> Set(a)
pub intersection = |s1, s2| crash "intrinsic: Set.intersection"

pub difference : Set(a), Set(a) -> Set(a)
pub difference = |s1, s2| crash "intrinsic: Set.difference"

pub symmetric_difference : Set(a), Set(a) -> Set(a)
pub symmetric_difference = |s1, s2| crash "intrinsic: Set.symmetric_difference"

pub is_subset : Set(a), Set(a) -> Bool
pub is_subset = |s1, s2| crash "intrinsic: Set.is_subset"

pub is_disjoint : Set(a), Set(a) -> Bool
pub is_disjoint = |s1, s2| crash "intrinsic: Set.is_disjoint"

-- Transformation

pub map : Set(a), (a) -> b -> Set(b)
pub map = |s, f| crash "intrinsic: Set.map"

pub filter : Set(a), (a) -> Bool -> Set(a)
pub filter = |s, pred| crash "intrinsic: Set.filter"

pub fold : Set(a), b, (b, a) -> b -> b
pub fold = |s, init, f| crash "intrinsic: Set.fold"

-- Conversion

pub to_iter : Set(a) -> Iter(a)
pub to_iter = |s| crash "intrinsic: Set.to_iter"

pub from_list : List(a) -> Set(a)
pub from_list = |xs| crash "intrinsic: Set.from_list"

pub to_list : Set(a) -> List(a)
pub to_list = |s| crash "intrinsic: Set.to_list"
```

### Design Notes

- `Set.map` requires `Ord` on output type `b` (since internal Map needs Ord on keys). Trait constraint: `where b is Ord`.
- `is_empty` is pure Camp (delegates to `size`).
- `Set.symmetric_difference` = `(s1 ∪ s2) \ (s1 ∩ s2)`. Provided as intrinsic for single-pass efficiency.

---

## 5. Iter Module

**Mostly pure Camp.** The most implementable module — Iter is a record of closures.

Per D2: `Iter.next` returns `[Yield(a) | Done]`.
Per D22: `Iter(a, e)` carries effect row. No standalone `collect`. No `Iter.sorted`.

Key implementation pattern: **local recursive functions** for consumption (no `while` in recipe). **Mutable variables** (`$`) for stateful closures.

```camp
-- Iter.camp

@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }

-- ========================
-- Construction
-- ========================

pub empty : Iter(a, e)
pub empty = @Iter({ next = || Done })

pub singleton : a -> Iter(a, e)
pub singleton = |x| {
  $consumed = False
  @Iter({ next = || if $consumed { Done } else { $consumed = True; Yield(x) } })
}

pub from_list : List(a) -> Iter(a, e)
pub from_list = |$list| {
  @Iter({
    next = ||
      match $list {
        Cons(head, rest) => $list = rest; Yield(head)
        Nil => Done
      }
  })
}

-- ========================
-- Core transformations
-- ========================

pub map : Iter(a, e), (a) -> b -> Iter(b, e)
pub map = |iter, f| @Iter({
  next = || match iter.next() {
    Yield(x) => Yield(f(x))
    Done => Done
  }
})

pub filter : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub filter = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if pred(x) { Yield(x) } else { go() }
    Done => Done
  }
  @Iter({ next = go })
}

pub flat_map : Iter(a, e), (a) -> Iter(b, e) -> Iter(b, e)
pub flat_map = |iter, f| {
  $inner = empty
  advance = || match $inner.next() {
    Yield(b) => Yield(b)
    Done => match iter.next() {
      Yield(a) => $inner = f(a); advance()
      Done => Done
    }
  }
  @Iter({ next = advance })
}

pub filter_map : Iter(a, e), (a) -> Result(b, err) -> Iter(b, e)
pub filter_map = |iter, f|
  flat_map(iter, |x| match f(x) {
    Ok(b) => singleton(b)
    Err(_) => empty
  })

-- ========================
-- Consumption
-- ========================

pub fold : Iter(a, e), b, (b, a) -> b -> b
pub fold = |iter, init, f| {
  go = |acc| match iter.next() {
    Yield(x) => go(f(acc, x))
    Done => acc
  }
  go(init)
}

pub for_each : Iter(a, e), (a) -> () -> ()
pub for_each = |iter, f| {
  go = || match iter.next() {
    Yield(x) => f(x); go()
    Done => {}
  }
  go()
}

pub count : Iter(a, e) -> I64
pub count = |iter| fold(iter, 0, |n, _| n + 1)

-- ========================
-- Search
-- ========================

pub find : Iter(a, e), (a) -> Bool -> Result(a, [NotFound])
pub find = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if pred(x) { Ok(x) } else { go() }
    Done => Err(NotFound)
  }
  go()
}

pub any : Iter(a, e), (a) -> Bool -> Bool
pub any = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if pred(x) { True } else { go() }
    Done => False
  }
  go()
}

pub all : Iter(a, e), (a) -> Bool -> Bool
pub all = |iter, pred| {
  go = || match iter.next() {
    Yield(x) => if not pred(x) { False } else { go() }
    Done => True
  }
  go()
}

-- ========================
-- Slicing
-- ========================

pub take : Iter(a, e), I64 -> Iter(a, e)
pub take = |iter, n| {
  $remaining = n
  @Iter({
    next = || if $remaining <= 0 { Done } else {
      $remaining = $remaining - 1
      iter.next()
    }
  })
}

pub skip : Iter(a, e), I64 -> Iter(a, e)
pub skip = |iter, n| {
  $remaining = n
  go = || {
    if $remaining > 0 {
      $remaining = $remaining - 1
      match iter.next() {
        Yield(_) => go()
        Done => Done
      }
    } else {
      iter.next()
    }
  }
  @Iter({ next = go })
}

pub take_while : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub take_while = |iter, pred| {
  $done = False
  @Iter({
    next = || {
      if $done { Done } else {
        match iter.next() {
          Yield(x) => if pred(x) { Yield(x) } else { $done = True; Done }
          Done => Done
        }
      }
    }
  })
}

pub skip_while : Iter(a, e), (a) -> Bool -> Iter(a, e)
pub skip_while = |iter, pred| {
  $skipping = True
  go = || {
    if $skipping {
      match iter.next() {
        Yield(x) => if pred(x) { go() } else { $skipping = False; Yield(x) }
        Done => Done
      }
    } else {
      iter.next()
    }
  }
  @Iter({ next = go })
}

-- ========================
-- Composition
-- ========================

pub chain : Iter(a, e), Iter(a, e) -> Iter(a, e)
pub chain = |first, second| @Iter({
  next = || match first.next() {
    Yield(x) => Yield(x)
    Done => second.next()
  }
})

pub zip : Iter(a, e), Iter(b, e) -> Iter((a, b), e)
pub zip = |left, right| @Iter({
  next = ||
    match left.next() {
      Yield(a) => match right.next() {
        Yield(b) => Yield((a, b))
        Done => Done
      }
      Done => Done
    }
})

pub enumerate : Iter(a, e) -> Iter((I64, a), e)
pub enumerate = |iter| {
  $index = 0
  @Iter({
    next = || match iter.next() {
      Yield(x) => {
        idx = $index
        $index = $index + 1
        Yield((idx, x))
      }
      Done => Done
    }
  })
}
```

### Design Notes

- **No `while` loops.** All iteration uses tail-recursive local functions (`go`, `advance`). This matches the recipe which has no `while` keyword.
- **Local recursive functions.** `go` captures `iter` from enclosing scope and calls itself. Camp must support self-referential local bindings (not shadowing — recursive definition).
- **Mutable state.** `$consumed`, `$remaining`, `$inner`, `$done`, `$skipping`, `$index` use `$` prefix for mutable closures. Each closure call can read and update these.
- **`filter_map` via `flat_map`.** Clean implementation: each element maps to `singleton(b)` or `empty`. `flat_map` handles the "some yield, some skip" pattern.
- **`flat_map` uses `advance` helper.** When inner iterator exhausts, creates a new inner from the next outer element and recurses. Handles empty inner iterators correctly.
- **Effect rows.** Type signatures omit explicit effect row annotations for brevity. The compiler infers effect rows from closure calls. `Iter(a, e)` carries effect `e` from `next` calls.
- **`@Iter({ next = ... })` construction.** Per recipe: `@Name(args)` for newtype construction. `@Iter` wraps a record.
- **`enumerate` uses block in match arm.** Multi-statement match arms need `{ ... }` blocks.

---

## 6. Num Namespace

Per D27: `Num` is a namespace with per-type submodules: `Num.I64`, `Num.F64`, etc.

**Directory structure:**
```
stdlib/
  Num/
    I64.camp
    I32.camp
    I16.camp
    I8.camp
    U64.camp
    U32.camp
    U16.camp
    U8.camp
    F64.camp
    F32.camp
```

**Numeric types are builtin.** Arithmetic operators (`+`, `-`, `*`, `/`, `%`) and bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`) are built into the language. Num submodules provide:
- Checked/saturating/wrapping arithmetic
- Mathematical functions (sqrt, sin, etc. for floats)
- Conversion and formatting
- Range iteration

### Num.I64

```camp
-- Num/I64.camp
-- Operations on I64. Arithmetic operators are built into the language.

-- Basic operations (pure Camp)

pub abs : I64 -> I64
pub abs = |n| if n < 0 { 0 - n } else { n }

pub clamp : I64, I64, I64 -> I64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : I64, I64 -> I64
pub max = |a, b| if a > b { a } else { b }

pub min : I64, I64 -> I64
pub min = |a, b| if a < b { a } else { b }

pub neg : I64 -> I64
pub neg = |n| 0 - n

-- Checked arithmetic (intrinsic — overflow detection)

pub checked_add : I64, I64 -> Result(I64, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.I64.checked_add"

pub checked_sub : I64, I64 -> Result(I64, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.I64.checked_sub"

pub checked_mul : I64, I64 -> Result(I64, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.I64.checked_mul"

-- Wrapping/saturating arithmetic (intrinsic)

pub wrapping_add : I64, I64 -> I64
pub wrapping_add = |a, b| crash "intrinsic: Num.I64.wrapping_add"

pub saturating_add : I64, I64 -> I64
pub saturating_add = |a, b| crash "intrinsic: Num.I64.saturating_add"

pub saturating_sub : I64, I64 -> I64
pub saturating_sub = |a, b| crash "intrinsic: Num.I64.saturating_sub"

-- Conversion (intrinsic)

pub to_str : I64 -> Str
pub to_str = |n| crash "intrinsic: Num.I64.to_str"

pub from_str : Str -> Result(I64, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.I64.from_str"

-- Range iteration (intrinsic — needs efficient generator)

pub range : I64, I64 -> Iter(I64)
pub range = |start, end| crash "intrinsic: Num.I64.range"

-- Bitwise function wrappers (pure Camp — just operator sugar for UFCS)

pub bitwise_and : I64, I64 -> I64
pub bitwise_and = |a, b| a & b

pub bitwise_or : I64, I64 -> I64
pub bitwise_or = |a, b| a | b

pub bitwise_xor : I64, I64 -> I64
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : I64 -> I64
pub bitwise_not = |a| ~a

pub shift_left : I64, U64 -> I64
pub shift_left = |a, n| a << n

pub shift_right : U64 -> I64
pub shift_right = |a, n| a >> n

-- Counting (intrinsic)

pub count_ones : I64 -> I64
pub count_ones = |n| crash "intrinsic: Num.I64.count_ones"

pub count_zeros : I64 -> I64
pub count_zeros = |n| crash "intrinsic: Num.I64.count_zeros"

pub leading_zeros : I64 -> I64
pub leading_zeros = |n| crash "intrinsic: Num.I64.leading_zeros"

pub trailing_zeros : I64 -> I64
pub trailing_zeros = |n| crash "intrinsic: Num.I64.trailing_zeros"
```

### Num.F64

```camp
-- Num/F64.camp
-- Operations on F64.

-- Basic operations (abs is intrinsic due to sign bit handling)

pub abs : F64 -> F64
pub abs = |n| crash "intrinsic: Num.F64.abs"

pub clamp : F64, F64, F64 -> F64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : F64, F64 -> F64
pub max = |a, b| crash "intrinsic: Num.F64.max"

pub min : F64, F64 -> F64
pub min = |a, b| crash "intrinsic: Num.F64.min"

pub neg : F64 -> F64
pub neg = |n| 0.0 - n

-- Rounding (intrinsic — needs libm)

pub ceiling : F64 -> F64
pub ceiling = |n| crash "intrinsic: Num.F64.ceiling"

pub floor : F64 -> F64
pub floor = |n| crash "intrinsic: Num.F64.floor"

pub round : F64 -> F64
pub round = |n| crash "intrinsic: Num.F64.round"

pub truncate : F64 -> F64
pub truncate = |n| crash "intrinsic: Num.F64.truncate"

-- Classification (intrinsic — IEEE 754 bit inspection)

pub is_nan : F64 -> Bool
pub is_nan = |n| crash "intrinsic: Num.F64.is_nan"

pub is_infinite : F64 -> Bool
pub is_infinite = |n| crash "intrinsic: Num.F64.is_infinite"

pub is_finite : F64 -> Bool
pub is_finite = |n| crash "intrinsic: Num.F64.is_finite"

-- Constants

pub pi : F64
pub pi = 3.14159265358979323846

pub e : F64
pub e = 2.71828182845904523536

pub nan : F64
pub nan = crash "intrinsic: Num.F64.nan"

pub infinity : F64
pub infinity = crash "intrinsic: Num.F64.infinity"

pub neg_infinity : F64
pub neg_infinity = crash "intrinsic: Num.F64.neg_infinity"

-- Trigonometry (intrinsic — needs libm)

pub sin : F64 -> F64
pub sin = |n| crash "intrinsic: Num.F64.sin"

pub cos : F64 -> F64
pub cos = |n| crash "intrinsic: Num.F64.cos"

pub tan : F64 -> F64
pub tan = |n| crash "intrinsic: Num.F64.tan"

pub asin : F64 -> F64
pub asin = |n| crash "intrinsic: Num.F64.asin"

pub acos : F64 -> F64
pub acos = |n| crash "intrinsic: Num.F64.acos"

pub atan : F64 -> F64
pub atan = |n| crash "intrinsic: Num.F64.atan"

pub atan2 : F64, F64 -> F64
pub atan2 = |y, x| crash "intrinsic: Num.F64.atan2"

-- Exponential/Logarithmic (intrinsic — needs libm)

pub exp : F64 -> F64
pub exp = |n| crash "intrinsic: Num.F64.exp"

pub log : F64 -> F64
pub log = |n| crash "intrinsic: Num.F64.log"

pub log2 : F64 -> F64
pub log2 = |n| crash "intrinsic: Num.F64.log2"

pub log10 : F64 -> F64
pub log10 = |n| crash "intrinsic: Num.F64.log10"

-- Power (intrinsic — needs libm)

pub pow : F64, F64 -> F64
pub pow = |base, exp| crash "intrinsic: Num.F64.pow"

pub sqrt : F64 -> F64
pub sqrt = |n| crash "intrinsic: Num.F64.sqrt"

-- Conversion

pub to_str : F64 -> Str
pub to_str = |n| crash "intrinsic: Num.F64.to_str"

pub from_str : Str -> Result(F64, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.F64.from_str"

pub to_i64 : F64 -> I64
pub to_i64 = |n| crash "intrinsic: Num.F64.to_i64"

pub from_i64 : I64 -> F64
pub from_i64 = |n| crash "intrinsic: Num.F64.from_i64"
```

### Other Integer Submodules

`Num.I32`, `Num.I16`, `Num.I8`, `Num.U64`, `Num.U32`, `Num.U16`, `Num.U8` follow the same pattern as `Num.I64` with:
- Type substituted (e.g., `I32` instead of `I64`)
- Unsigned types have no `abs` or `neg`
- Unsigned types use `U64` for shift amounts
- No `F32`/`F64` constants or trig functions
- Same checked/wrapping/saturating arithmetic
- Same bitwise operations and counting functions

### Num.F32

Same as `Num.F64` with `F32` substituted. Fewer significant digits for constants:
```
pub pi : F32 = 3.14159265
pub e : F32 = 2.71828182
```

---

## Summary: Intrinsic vs Pure Camp

| Module | Pure Camp | Intrinsic |
|--------|-----------|-----------|
| **Str** | `is_empty` | Everything else (UTF-8, Unicode, grapheme) |
| **List** | `empty`, `singleton`, `append`, `length`, `is_empty`, `first`, `last`, `rest` | `sort`, `sort_by`, `to_iter`, `from_iter` |
| **Map** | `is_empty` | Everything else (ordered tree) |
| **Set** | `is_empty` | Everything else (delegates to Map) |
| **Iter** | `empty`, `singleton`, `from_list`, `map`, `filter`, `flat_map`, `filter_map`, `fold`, `for_each`, `count`, `find`, `any`, `all`, `take`, `skip`, `take_while`, `skip_while`, `chain`, `zip`, `enumerate` | (none needed — all pure Camp) |
| **Num.I64** | `abs`, `clamp`, `max`, `min`, `neg`, bitwise wrappers | Checked/wrapping/saturating arithmetic, `to_str`, `from_str`, `range`, counting |
| **Num.F64** | `clamp`, `neg`, constants | `abs`, `max`, `min`, rounding, classification, trig, exp/log, conversion |

**Iter is 100% pure Camp.** It's the most implementable module and can be fully tested once the compiler supports closures, pattern matching, and recursive local functions.

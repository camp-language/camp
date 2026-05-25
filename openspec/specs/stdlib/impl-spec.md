# Stdlib Implementation Specification

## Overview

This spec documents the 38 stdlib modules implemented as `.camp` source files, embedded in the compiler via `src/build/stdlib.odin`. Each module specifies:
1. The type declaration (if any)
2. Which functions are **intrinsic** (need runtime/WASM support) vs **pure Camp** (implementable in the language itself)
3. The exact implementation code using correct syntax from `docs/syntax-recipe.md`
4. Effect row annotations where needed

### Intrinsic Convention

Functions requiring runtime support use `crash "intrinsic: Module.function"` as their body. The compiler's lowering pass recognizes these signatures and replaces them with calls to the Odin/WASM runtime. This is a compiler-internal convention, not a language feature.

### Module Registry (38 modules)

| Module | File | Lines | Category | Pure/Intrinsic |
|--------|------|-------|----------|----------------|
| Result | `stdlib/Result.camp` | 93 | Data type | Pure Camp |
| Bool | `stdlib/Bool.camp` | 18 | Data type | Pure Camp |
| Str | `stdlib/Str.camp` | 105 | Data type | All intrinsic |
| List | `stdlib/List.camp` | 70 | Data type | Mostly pure, sort/iter intrinsic |
| Iter | `stdlib/Iter.camp` | 229 | Data type | Pure Camp |
| Map | `stdlib/Map.camp` | 85 | Data type | All intrinsic |
| Set | `stdlib/Set.camp` | 77 | Data type | All intrinsic |
| Display | `stdlib/Display.camp` | 5 | Trait | Declaration only |
| Num.I64 | `stdlib/Num/I64.camp` | 88 | Numeric | Mixed |
| Num.I32 | `stdlib/Num/I32.camp` | 71 | Numeric | Mixed |
| Num.I16 | `stdlib/Num/I16.camp` | 68 | Numeric | Mixed |
| Num.I8 | `stdlib/Num/I8.camp` | 68 | Numeric | Mixed |
| Num.U64 | `stdlib/Num/U64.camp` | 65 | Numeric | Mixed |
| Num.U32 | `stdlib/Num/U32.camp` | 62 | Numeric | Mixed |
| Num.U16 | `stdlib/Num/U16.camp` | 62 | Numeric | Mixed |
| Num.U8 | `stdlib/Num/U8.camp` | 62 | Numeric | Mixed |
| Num.F64 | `stdlib/Num/F64.camp` | 120 | Numeric | Mostly intrinsic |
| Num.F32 | `stdlib/Num/F32.camp` | 104 | Numeric | Mostly intrinsic |
| Bytes | `stdlib/Bytes.camp` | 57 | Data type | All intrinsic |
| Eq | `stdlib/Eq.camp` | 5 | Trait | Declaration only |
| Ord | `stdlib/Ord.camp` | 8 | Trait | Declaration only |
| Hash | `stdlib/Hash.camp` | 8 | Trait | Declaration only |
| Debug | `stdlib/Debug.camp` | 5 | Trait | Declaration only |
| Default | `stdlib/Default.camp` | 5 | Trait | Declaration only |
| IntoIter | `stdlib/IntoIter.camp` | 5 | Trait | Declaration only |
| FromIter | `stdlib/FromIter.camp` | 5 | Trait | Declaration only |
| From | `stdlib/From.camp` | 5 | Trait | Declaration only |
| TryFrom | `stdlib/TryFrom.camp` | 5 | Trait | Declaration only |
| Console | `stdlib/Console.camp` | 8 | Effect | Declaration only |
| Throw | `stdlib/Throw.camp` | 7 | Effect | Declaration only |
| File | `stdlib/File.camp` | 19 | Effect | Declaration only |
| Env | `stdlib/Env.camp` | 9 | Effect | Declaration only |
| Time | `stdlib/Time.camp` | 7 | Effect | Declaration only |
| Random | `stdlib/Random.camp` | 9 | Effect | Declaration only |
| Log | `stdlib/Log.camp` | 9 | Effect | Declaration only |
| Path | `stdlib/Path.camp` | 56 | Data type | All intrinsic |
| Duration | `stdlib/Duration.camp` | 72 | Data type | All intrinsic |
| Fmt | `stdlib/Fmt.camp` | 26 | Formatting | All intrinsic |

---

## 1. Result Module

**Pure Camp.** The core error-handling type. Per D1: Drop Option, keep Result + Throw!.

```camp
@Result(a, e): pub [Ok(a) | Err(e)]

-- Core combinators

pub map : Result(a, e), (a) -> b -> Result(b, e)
pub map = |r, f|
  match r { Ok(v) => Ok(f(v)) | Err(e) => Err(e) }

pub map_err : Result(a, e), (e) -> f -> Result(a, f)
pub map_err = |r, f|
  match r { Ok(v) => Ok(v) | Err(e) => Err(f(e)) }

pub and_then : Result(a, e), (a) -> Result(b, e) -> Result(b, e)
pub and_then = |r, f|
  match r { Ok(v) => f(v) | Err(e) => Err(e) }

pub or_else : Result(a, e), || -> Result(a, f) -> Result(a, e | f)
pub or_else = |r, f|
  match r { Ok(v) => Ok(v) | Err(_) => f() }

-- Predicates

pub is_ok : Result(a, e) -> Bool
pub is_ok = |r|
  match r { Ok(_) => True | Err(_) => False }

pub is_err : Result(a, e) -> Bool
pub is_err = |r|
  match r { Ok(_) => False | Err(_) => True }

-- Unwrapping

pub unwrap : Result(a, e) -> a
pub unwrap = |r|
  match r { Ok(v) => v | Err(_) => crash "Result.unwrap: called on Err" }

pub unwrap_or : Result(a, e), a -> a
pub unwrap_or = |r, default|
  match r { Ok(v) => v | Err(_) => default }

pub unwrap_or_else : Result(a, e), (e) -> a -> a
pub unwrap_or_else = |r, f|
  match r { Ok(v) => v | Err(e) => f(e) }

-- Boolean composition

pub or : Result(a, e), Result(a, e) -> Result(a, e)
pub or = |r1, r2|
  match r1 { Ok(v) => Ok(v) | Err(_) => r2 }

-- Filtering

pub filter : Result(a, e), (a) -> Bool, e -> Result(a, e)
pub filter = |r, pred, err|
  match r {
    Ok(v) => if pred(v) { Ok(v) } else { Err(err) }
    Err(e) => Err(e)
  }

-- Flattening

pub flatten : Result(Result(a, e), e) -> Result(a, e)
pub flatten = |r|
  match r { Ok(inner) => inner | Err(e) => Err(e) }

-- Conversion

pub to_list : Result(a, e) -> List(a)
pub to_list = |r|
  match r { Ok(v) => [v] | Err(_) => [] }

pub from_list : List(a) -> Result(a, [EmptyList])
pub from_list = |xs|
  match xs {
    Cons(h, _) => Ok(h)
    Nil => Err(EmptyList)
  }

-- Default

pub unwrap_or_default : Result(a, e) -> a
pub unwrap_or_default = |r|
  match r { Ok(v) => v | Err(_) => Default.default }

-- Effect bridging

pub unwrap! : Result(a, e) -> -[Throw!(e)]-> a
pub unwrap! = |r|
  match r { Ok(v) => v | Err(e) => Throw.raise!(e) }

pub catch : || -[Throw!(e)]-> a -> Result(a, e)
pub catch = |action|
  handle Throw! in { Ok(action()) } with {
    .raise!(resume, err) => Err(err)
  }
```

### Design Notes

- `unwrap_or_default` uses `Default.default` — requires `a is Default` constraint (D6).
- `catch` bridges Throw! → Result. `unwrap!` bridges Result → Throw!. Together they form the error-handling round-trip.
- `from_list` returns `Err(EmptyList)` for `Nil`, `Ok(head)` for any non-empty list (ignores tail).

---

## 2. Bool Module

**Pure Camp.** Compiler declares `@Bool : pub [True | False]`.

```camp
pub not : Bool -> Bool
pub not = |b|
  match b { True => False | False => True }

pub xor : Bool, Bool -> Bool
pub xor = |a, b|
  match a { True => not(b) | False => b }

pub and : Bool, Bool -> Bool
pub and = |a, b|
  match a { True => b | False => False }

pub or : Bool, Bool -> Bool
pub or = |a, b|
  match a { True => True | False => b }
```

### Design Notes

- Uses `and`/`or` keywords per syntax recipe (no `&&`/`||`/`!`).
- `and`/`or` are short-circuit (match on first arg, only evaluate second if needed).

---

## 3. Str Module

**All intrinsic.** Str is a builtin type — the compiler provides it natively. All string operations require runtime UTF-8/Unicode/grapheme support.

Per D18: `Str.length` counts graphemes, `Str.is_empty` uses `byte_size` (O(1)), `Str.slice` is grapheme-safe, case ops are Unicode, `split_first`/`split_last` return `Result((Str, Str), [NotFound])`.

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

- `is_empty` uses `byte_size` not `length` — O(1) vs O(n). A zero-byte string is always empty.
- No `walk_utf8`/`walk_graphemes` — iteration goes through `to_iter` → `Iter(Str)`.
- `drop_prefix`/`drop_suffix` return `Str` unconditionally — if prefix/suffix not present, returns original string unchanged.
- `from_bytes` implements `TryFrom(Bytes, Str, [InvalidUtf8])` per D19. A separate `TryFrom` instance can be added when the trait system supports it.

---

## 4. List Module

**Mostly pure Camp.** List is a builtin type `@List(a): pub [Cons(a, List(a)) | Nil]`. Sort and Iter conversion are intrinsic.

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

- `append` is O(n) in the first list — standard immutable linked list.
- `last` is O(n) — walks to the end. Inherent to linked lists.
- `sort`/`sort_by` are intrinsic for v1. A pure-Camp merge sort is possible but complex (needs Ord dispatch).
- No `map`, `filter`, `fold` — those live on `Iter`. Use `xs->to_iter()->map(f)->from_iter()`.
- No `head`/`tail` returning `Option` — use `first`/`rest` returning `Result(a, [ListWasEmpty])` per D3.

---

## 5. Iter Module

**Pure Camp.** The most complex module — most operations are implementable in the language itself using closures, mutable variables, and tail recursion.

Per D2: `Iter.next` returns `[Yield(a) | Done]`.
Per D22: `Iter(a, e)` carries an effect row parameter.

```camp
-- Iter.camp

@Iter(a, e): { next: || -[e]-> [Yield(a) | Done] }

-- Construction

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

-- Core transformations

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

-- Consumption

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

-- Search

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

pub contains : Iter(a, e), a -> Bool
pub contains = |iter, target| any(iter, |x| Eq.eq(x, target))

-- Slicing

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

-- Composition

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

- **Implementation pattern**: Local recursive `go` functions + `$mutable` closures + `@Iter({ next = go })` construction.
- `flat_map` uses `$inner` mutable + `advance` recursive helper. When inner is exhausted, advances outer and creates new inner. Recursively calls `advance()` to handle empty inner iterators.
- `filter_map` = `flat_map` + `singleton`/`empty` — clean composition.
- `contains` uses `Eq.eq` (D7) — requires `where a is Eq` constraint.
- No `while` — all loops use tail-recursive helpers.
- No standalone `collect` — use `FromIter.from_iter`.
- No `Iter.sorted` — use `List.from_iter` + `List.sort`.

---

## 6. Map Module

**All intrinsic.** Map is an opaque ordered tree map. You cannot implement a balanced tree in pure Camp without mutation or FFI.

Per D7: Map MUST be ordered for referential transparency.
Per D20: `Map.update` uses `Result(v, [KeyNotFound])` callback, `Map.union` is left-biased.

```camp
-- Map.camp
-- @Map(k, v) -- opaque ordered tree map, provided by runtime

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

-- Set-like operations
pub union : Map(k, v), Map(k, v) -> Map(k, v)
pub union = |m1, m2| crash "intrinsic: Map.union"

pub intersection : Map(k, v), Map(k, v) -> Map(k, v)
pub intersection = |m1, m2| crash "intrinsic: Map.intersection"

pub difference : Map(k, v), Map(k, v) -> Map(k, v)
pub difference = |m1, m2| crash "intrinsic: Map.difference"
```

### Design Notes

- `is_empty` is pure Camp (delegates to `size`), but `size` is intrinsic.
- `Map.update` callback: receives `Err(KeyNotFound)` if key absent, `Ok(v)` if present. Returns `Err(KeyNotFound)` to remove, `Ok(new_v)` to insert/update. Per D20.
- `Map.union` is left-biased on key conflict for v1.
- All set-like operations are O(m+n) on ordered trees.

---

## 7. Set Module

**All intrinsic.** Per D21: Set is `Map(a, {})` internally.

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

- `Set.map` requires `Ord` on `b` — trait constraint enforced by compiler.
- `Set.symmetric_difference` = `(s1 union s2) difference (s1 intersection s2)` — intrinsic for efficiency.

---

## 8. Bytes Module

**All intrinsic.** Opaque contiguous byte buffer provided by runtime.

Per D19: Lean module (construction, queries, access, slicing, concat). Conversions via traits.

```camp
-- Bytes.camp
-- @Bytes -- opaque contiguous byte buffer, provided by runtime

-- Construction
pub new : Bytes
pub new = crash "intrinsic: Bytes.new"

pub from_list : List(U8) -> Bytes
pub from_list = |xs| crash "intrinsic: Bytes.from_list"

pub singleton : U8 -> Bytes
pub singleton = |b| crash "intrinsic: Bytes.singleton"

-- Queries
pub length : Bytes -> I64
pub length = |b| crash "intrinsic: Bytes.length"

pub is_empty : Bytes -> Bool
pub is_empty = |b| length(b) == 0

-- Access
pub get : I64, Bytes -> Result(U8, [IndexOutOfBounds])
pub get = |i, b| crash "intrinsic: Bytes.get"

-- Slicing
pub take : Bytes, I64 -> Bytes
pub take = |b, n| crash "intrinsic: Bytes.take"

pub drop : Bytes, I64 -> Bytes
pub drop = |b, n| crash "intrinsic: Bytes.drop"

pub slice : Bytes, I64, I64 -> Bytes
pub slice = |b, start, len| crash "intrinsic: Bytes.slice"

-- Concatenation
pub concat : Bytes, Bytes -> Bytes
pub concat = |a, b| crash "intrinsic: Bytes.concat"

-- Iteration
pub to_iter : Bytes -> Iter(U8)
pub to_iter = |b| crash "intrinsic: Bytes.to_iter"

-- Conversion
pub to_list : Bytes -> List(U8)
pub to_list = |b| crash "intrinsic: Bytes.to_list"

pub to_str : Bytes -> Str
pub to_str = |b| crash "intrinsic: Bytes.to_str"
```

---

## 9. Path Module

**All intrinsic.** Opaque filesystem path, normalized on construction.

Per D25: Opaque type, auto-normalized. No I/O on Path — that's in File!.

```camp
-- Path.camp
-- @Path — opaque filesystem path, normalized on construction

@Path : -- opaque, provided by runtime

-- Construction
pub new : Str -> Path
pub new = |s| crash "intrinsic: Path.new"

pub join : Path, Path -> Path
pub join = |a, b| crash "intrinsic: Path.join"

pub from_list : List(Str) -> Path
pub from_list = |parts| crash "intrinsic: Path.from_list"

-- Decomposition
pub parent : Path -> Result(Path, [HasNoParent])
pub parent = |p| crash "intrinsic: Path.parent"

pub filename : Path -> Str
pub filename = |p| crash "intrinsic: Path.filename"

pub stem : Path -> Str
pub stem = |p| crash "intrinsic: Path.stem"

pub extension : Path -> Str
pub extension = |p| crash "intrinsic: Path.extension"

-- Manipulation
pub with_extension : Path, Str -> Path
pub with_extension = |p, ext| crash "intrinsic: Path.with_extension"

pub with_filename : Path, Str -> Path
pub with_filename = |p, name| crash "intrinsic: Path.with_filename"

pub with_parent : Path, Path -> Path
pub with_parent = |p, parent| crash "intrinsic: Path.with_parent"

-- Queries
pub is_absolute : Path -> Bool
pub is_absolute = |p| crash "intrinsic: Path.is_absolute"

pub is_relative : Path -> Bool
pub is_relative = |p| crash "intrinsic: Path.is_relative"

-- Conversion
pub to_str : Path -> Str
pub to_str = |p| crash "intrinsic: Path.to_str"

pub to_iter : Path -> Iter(Str)
pub to_iter = |p| crash "intrinsic: Path.to_iter"
```

---

## 10. Duration Module

**All intrinsic.** Rust-style `{ secs: I64, nanos: I64 }` internally. Signed, ~584B yr range.

Per D24: Duration only; DateTime is a separate package.

```camp
-- Duration.camp
-- @Duration — time duration (Rust-style signed struct)

@Duration : -- opaque, internally { secs: I64, nanos: I64 }

-- Constructors
pub from_seconds : F64 -> Duration
pub from_seconds = |s| crash "intrinsic: Duration.from_seconds"

pub from_millis : I64 -> Duration
pub from_millis = |ms| crash "intrinsic: Duration.from_millis"

pub from_micros : I64 -> Duration
pub from_micros = |us| crash "intrinsic: Duration.from_micros"

pub from_nanos : I64 -> Duration
pub from_nanos = |ns| crash "intrinsic: Duration.from_nanos"

-- Accessors
pub as_seconds : Duration -> F64
pub as_seconds = |d| crash "intrinsic: Duration.as_seconds"

pub as_millis : Duration -> I64
pub as_millis = |d| crash "intrinsic: Duration.as_millis"

pub as_micros : Duration -> I64
pub as_micros = |d| crash "intrinsic: Duration.as_micros"

pub as_nanos : Duration -> I64
pub as_nanos = |d| crash "intrinsic: Duration.as_nanos"

-- Arithmetic
pub add : Duration, Duration -> Duration
pub add = |a, b| crash "intrinsic: Duration.add"

pub sub : Duration, Duration -> Duration
pub sub = |a, b| crash "intrinsic: Duration.sub"

pub mul : Duration, I64 -> Duration
pub mul = |d, n| crash "intrinsic: Duration.mul"

pub neg : Duration -> Duration
pub neg = |d| crash "intrinsic: Duration.neg"

pub abs : Duration -> Duration
pub abs = |d| crash "intrinsic: Duration.abs"

-- Comparison
pub is_zero : Duration -> Bool
pub is_zero = |d| crash "intrinsic: Duration.is_zero"

-- Constants
pub zero : Duration
pub zero = crash "intrinsic: Duration.zero"

pub second : Duration
pub second = crash "intrinsic: Duration.second"

pub millisecond : Duration
pub millisecond = crash "intrinsic: Duration.millisecond"

pub microsecond : Duration
pub microsecond = crash "intrinsic: Duration.microsecond"

pub nanosecond : Duration
pub nanosecond = crash "intrinsic: Duration.nanosecond"
```

---

## 11. Fmt Module

**All intrinsic.** Formatting utilities. Per D28: Houses Display/Debug traits. Format specifiers go in interpolation syntax.

```camp
-- Fmt.camp
-- Display is declared separately in Display.camp
-- Debug is declared separately in Debug.camp

-- Concatenation helper for building formatted strings
pub concat : Str, Str -> Str
pub concat = |a, b| crash "intrinsic: Fmt.concat"

-- Numeric formatting with precision
pub f64_with_precision : F64, I64 -> Str
pub f64_with_precision = |n, precision| crash "intrinsic: Fmt.f64_with_precision"

pub f32_with_precision : F32, I64 -> Str
pub f32_with_precision = |n, precision| crash "intrinsic: Fmt.f32_with_precision"

-- Padding/alignment (used by interpolation runtime)
pub pad_left : Str, I64, Str -> Str
pub pad_left = |s, width, fill| crash "intrinsic: Fmt.pad_left"

pub pad_right : Str, I64, Str -> Str
pub pad_right = |s, width, fill| crash "intrinsic: Fmt.pad_right"
```

---

## 12. Trait Modules

### Display

```camp
Display : {
  to_str: (Self) -> Str,
}
```

### Eq

```camp
Eq(a) : {
  eq : (a, a) -> Bool,
}
```

### Ord

Per D16: Order is structural tag union `[Less | Equal | Greater]`.

```camp
@Order : pub [Less | Equal | Greater]

Ord(a) : is Eq(a) {
  compare : (a, a) -> Order,
}
```

### Hash

Per D29: Hasher is opaque (SipHash-1-3 internally).

```camp
@Hasher : -- opaque, provided by runtime

Hash(a) : {
  hash : (a, Hasher) -> Hasher,
}
```

### Debug

```camp
Debug(a) : {
  debug : a -> Str,
}
```

### Default

```camp
Default(a) : {
  default : a,
}
```

### IntoIter

```camp
IntoIter(a) : {
  to_iter : Self(a) -> Iter(a),
}
```

### FromIter

```camp
FromIter(c, a) : {
  from_iter : Iter(a) -> c,
}
```

### From

```camp
From(source, target) : {
  from : source -> target,
}
```

### TryFrom

```camp
TryFrom(source, target, e) : {
  try_from : source -> Result(target, e),
}
```

---

## 13. Effect Modules

### Console!

Per D23: Only `foo!` variants. Use `Result.catch` for Result versions.

```camp
effect Console! : {
  println! : Str -> -[Console!]-> (),
  print!   : Str -> -[Console!]-> (),
  readline! : -[Console!]-> Str,
}
```

### Throw!

Per D4: Throw! for propagated, effectful, action-level errors. Bridge: `Result.catch` (Throw!→Result) and `Result.unwrap!` (Result→Throw!).

```camp
effect Throw!(e) : {
  raise! : e -> -[Throw!(e)]-> a,
}
```

### File!

Per D23: Only `foo!` variants. FileErr keeps IoErr as catch-all for v1.

```camp
@FileErr : pub [NotFound | PermissionDenied | AlreadyExists | InvalidUtf8 | IoErr]

effect File! : {
  read_all!    : Path -> -[File!, Throw!([FileErr])]-> Str,
  write_all!   : Path, Str -> -[File!, Throw!([FileErr])]-> (),
  append_all!  : Path, Str -> -[File!, Throw!([FileErr])]-> (),
  read_bytes!  : Path -> -[File!, Throw!([FileErr])]-> Bytes,
  write_bytes! : Path, Bytes -> -[File!, Throw!([FileErr])]-> (),
  list_dir!    : Path -> -[File!, Throw!([FileErr])]-> List(Path),
  create_dir!  : Path -> -[File!, Throw!([FileErr])]-> (),
  remove!      : Path -> -[File!, Throw!([FileErr])]-> (),
  copy!        : Path, Path -> -[File!, Throw!([FileErr])]-> (),
  exists!      : Path -> -[File!]-> Bool,
  is_dir!      : Path -> -[File!]-> Bool,
  is_file!     : Path -> -[File!]-> Bool,
}
```

### Env!

Per D23: `Env.try_get` returns Result, not Throw!.

```camp
effect Env! : {
  get!     : Str -> -[Env!, Throw!([VarNotFound])]-> Str,
  try_get  : Str -> -[Env!]-> Result(Str, [VarNotFound]),
  vars!    : -[Env!]-> List((Str, Str)),
  args!    : -[Env!]-> List(Str),
}
```

### Time!

Per D24: Duration only; DateTime is a separate package.

```camp
effect Time! : {
  now!       : -[Time!]-> Duration,
  monotonic! : -[Time!]-> Duration,
}
```

### Random!

Fast PRNG (not cryptographic). For cryptographic random, use `Crypto.Random!`.

```camp
effect Random! : {
  int!   : I64, I64 -> -[Random!]-> I64,
  float! : F64, F64 -> -[Random!]-> F64,
  bytes! : I64 -> -[Random!]-> Bytes,
  bool!  : -[Random!]-> Bool,
}
```

### Log!

Per D15: Message-only. Structured logging is a package concern.

```camp
effect Log! : {
  debug! : Str -> -[Log!]-> (),
  info!  : Str -> -[Log!]-> (),
  warn!  : Str -> -[Log!]-> (),
  error! : Str -> -[Log!]-> (),
}
```

---

## 14. Num Namespace

Per D27: Num is a namespace with per-type submodules. Numeric types (I64, F64, etc.) are builtin — the compiler provides them. The Num submodules provide utility functions.

### Num.I64 (representative integer module)

**Mixed pure/intrinsic.** Basic operations are pure Camp. Checked/wrapping/saturating arithmetic, conversion, range, and bit counting are intrinsic.

```camp
-- Num/I64.camp

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

-- Bitwise function wrappers (pure Camp — operator sugar for UFCS)
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

### Other integer modules

`Num.I32`, `Num.I16`, `Num.I8`, `Num.U64`, `Num.U32`, `Num.U16`, `Num.U8` follow the same pattern as `Num.I64` with:
- Type-appropriate signatures (e.g., `I32` instead of `I64`, `U8` instead of `I64`)
- Unsigned types lack `abs` and `neg` (no sign bit)
- Unsigned types have `saturating_add`/`saturating_sub` but no wrapping variants beyond what I64 provides
- All have `checked_add`/`checked_sub`/`checked_mul`, `to_str`/`from_str`, `range`, bitwise wrappers, and bit counting

### Num.F64 (representative float module)

**Mostly intrinsic.** `clamp` is pure Camp. Everything else needs libm or IEEE 754 bit inspection.

```camp
-- Num/F64.camp

-- Basic operations (abs is intrinsic due to sign bit handling)
pub abs : F64 -> F64
pub abs = |n| crash "intrinsic: Num.F64.abs"

pub clamp : F64, F64, F64 -> F64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : F64, F64 -> F64
pub max = |a, b| crash "intrinsic: Num.F64.max"  -- handles NaN

pub min : F64, F64 -> F64
pub min = |a, b| crash "intrinsic: Num.F64.min"  -- handles NaN

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

### Num.F32

Follows the same pattern as `Num.F64` with `F32` type annotations. Same intrinsic functions, same constants (as `F32` values).

---

## 15. Not Yet Implemented (Priority 2/3)

The following modules are specified in `openspec/specs/stdlib/spec.md` but not yet implemented:

### Priority 2 (required for most REST APIs)
- **Json** — parsing, stringification, Value type, Encode/Decode trait instances, streaming parser
- **Regex** — compile, match, find, replace, split, capture groups
- **Uri** — URI/URL parsing and construction, percent encoding
- **Crypto.Random!** — cryptographically secure random (separate from fast PRNG `Random!`)
- **Uuid** — v4, v7 generation, parsing, formatting (depends on `Crypto.Random!`)
- **Base64** — Base64, Base64URL, Base32, Base16 (Hex) encoding/decoding

### Priority 3 (important for completeness)
- **Gzip** — pure compression/decompression on Bytes
- **EncoderFormatting** / **DecoderFormatting** — format-agnostic codec framework traits

### Also specified but deferred to packages
- **DateTime** — separate package, not stdlib (per D24)
- **Crypto.Hash** — official package, not stdlib (for independent security patch versioning)
- **Http** — official package
- **Database** — official package

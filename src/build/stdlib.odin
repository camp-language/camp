package build

import "camp:base"

// Stdlib module registry — embedded .camp source files
// These are parsed and typechecked on demand when imported by user code.
// Source is embedded from the stdlib/ directory at compiler build time.

Stdlib_Module :: struct {
	name:   string,
	source: string,
	path:   string,
}

RESULT_CAMP :: `@Result(a, e): pub [Ok(a) | Err(e)]

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

pub unwrap_or_default : Result(a, e) -> a
pub unwrap_or_default = |r|
  match r { Ok(v) => v | Err(_) => Default.default }

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

-- Effect bridging

pub unwrap! : Result(a, e) -> -[Throw!(e)]-> a
pub unwrap! = |r|
  match r { Ok(v) => v | Err(e) => Throw.raise!(e) }

pub catch : || -[Throw!(e)]-> a -> Result(a, e)
pub catch = |action|
  handle Throw! in { Ok(action()) } with {
    .raise!(resume, err) => Err(err)
  }`

BOOL_CAMP :: `-- @Bool: pub [True | False]  -- declared by compiler

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
  match a { True => True | False => b }`

STR_CAMP :: `-- Str is a builtin type. This file declares the public API.
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
pub to_iter = |s| crash "intrinsic: Str.to_iter"`

LIST_CAMP :: `-- @List(a): pub [Cons(a, List(a)) | Nil]  -- declared by compiler

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
pub from_iter = |iter| crash "intrinsic: List.from_iter"`

ITER_CAMP :: `-- Iter.camp

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

pub contains : Iter(a, e), a -> Bool
pub contains = |iter, target| any(iter, |x| Eq.eq(x, target))

-- ========================
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
}`

MAP_CAMP :: `-- @Map(k, v) -- opaque ordered tree map, provided by runtime

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
pub difference = |m1, m2| crash "intrinsic: Map.difference"`

SET_CAMP :: `-- @Set(a) -- opaque, Map(a, {}) internally

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
pub to_list = |s| crash "intrinsic: Set.to_list"`

DISPLAY_CAMP :: `Display : {
  to_str: (Self) -> Str,
}`

NUM_I64_CAMP :: `-- Num/I64.camp
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
pub trailing_zeros = |n| crash "intrinsic: Num.I64.trailing_zeros"`

NUM_I32_CAMP :: `-- Num/I32.camp
-- Operations on I32.

pub abs : I32 -> I32
pub abs = |n| if n < 0 { 0 - n } else { n }

pub clamp : I32, I32, I32 -> I32
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : I32, I32 -> I32
pub max = |a, b| if a > b { a } else { b }

pub min : I32, I32 -> I32
pub min = |a, b| if a < b { a } else { b }

pub neg : I32 -> I32
pub neg = |n| 0 - n

pub checked_add : I32, I32 -> Result(I32, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.I32.checked_add"

pub checked_sub : I32, I32 -> Result(I32, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.I32.checked_sub"

pub checked_mul : I32, I32 -> Result(I32, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.I32.checked_mul"

pub wrapping_add : I32, I32 -> I32
pub wrapping_add = |a, b| crash "intrinsic: Num.I32.wrapping_add"

pub saturating_add : I32, I32 -> I32
pub saturating_add = |a, b| crash "intrinsic: Num.I32.saturating_add"

pub saturating_sub : I32, I32 -> I32
pub saturating_sub = |a, b| crash "intrinsic: Num.I32.saturating_sub"

pub to_str : I32 -> Str
pub to_str = |n| crash "intrinsic: Num.I32.to_str"

pub from_str : Str -> Result(I32, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.I32.from_str"

pub range : I32, I32 -> Iter(I32)
pub range = |start, end| crash "intrinsic: Num.I32.range"

pub bitwise_and : I32, I32 -> I32
pub bitwise_and = |a, b| a & b

pub bitwise_or : I32, I32 -> I32
pub bitwise_or = |a, b| a | b

pub bitwise_xor : I32, I32 -> I32
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : I32 -> I32
pub bitwise_not = |a| ~a

pub shift_left : I32, I32 -> I32
pub shift_left = |a, n| a << n

pub shift_right : I32, I32 -> I32
pub shift_right = |a, n| a >> n

pub count_ones : I32 -> I32
pub count_ones = |n| crash "intrinsic: Num.I32.count_ones"

pub leading_zeros : I32 -> I32
pub leading_zeros = |n| crash "intrinsic: Num.I32.leading_zeros"

pub trailing_zeros : I32 -> I32
pub trailing_zeros = |n| crash "intrinsic: Num.I32.trailing_zeros"`

NUM_I16_CAMP :: `-- Num/I16.camp
-- Operations on I16.

pub abs : I16 -> I16
pub abs = |n| if n < 0 { 0 - n } else { n }

pub clamp : I16, I16, I16 -> I16
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : I16, I16 -> I16
pub max = |a, b| if a > b { a } else { b }

pub min : I16, I16 -> I16
pub min = |a, b| if a < b { a } else { b }

pub neg : I16 -> I16
pub neg = |n| 0 - n

pub checked_add : I16, I16 -> Result(I16, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.I16.checked_add"

pub checked_sub : I16, I16 -> Result(I16, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.I16.checked_sub"

pub checked_mul : I16, I16 -> Result(I16, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.I16.checked_mul"

pub wrapping_add : I16, I16 -> I16
pub wrapping_add = |a, b| crash "intrinsic: Num.I16.wrapping_add"

pub saturating_add : I16, I16 -> I16
pub saturating_add = |a, b| crash "intrinsic: Num.I16.saturating_add"

pub saturating_sub : I16, I16 -> I16
pub saturating_sub = |a, b| crash "intrinsic: Num.I16.saturating_sub"

pub to_str : I16 -> Str
pub to_str = |n| crash "intrinsic: Num.I16.to_str"

pub from_str : Str -> Result(I16, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.I16.from_str"

pub bitwise_and : I16, I16 -> I16
pub bitwise_and = |a, b| a & b

pub bitwise_or : I16, I16 -> I16
pub bitwise_or = |a, b| a | b

pub bitwise_xor : I16, I16 -> I16
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : I16 -> I16
pub bitwise_not = |a| ~a

pub shift_left : I16, I16 -> I16
pub shift_left = |a, n| a << n

pub shift_right : I16, I16 -> I16
pub shift_right = |a, n| a >> n

pub count_ones : I16 -> I16
pub count_ones = |n| crash "intrinsic: Num.I16.count_ones"

pub leading_zeros : I16 -> I16
pub leading_zeros = |n| crash "intrinsic: Num.I16.leading_zeros"

pub trailing_zeros : I16 -> I16
pub trailing_zeros = |n| crash "intrinsic: Num.I16.trailing_zeros"`

NUM_I8_CAMP :: `-- Num/I8.camp
-- Operations on I8.

pub abs : I8 -> I8
pub abs = |n| if n < 0 { 0 - n } else { n }

pub clamp : I8, I8, I8 -> I8
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : I8, I8 -> I8
pub max = |a, b| if a > b { a } else { b }

pub min : I8, I8 -> I8
pub min = |a, b| if a < b { a } else { b }

pub neg : I8 -> I8
pub neg = |n| 0 - n

pub checked_add : I8, I8 -> Result(I8, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.I8.checked_add"

pub checked_sub : I8, I8 -> Result(I8, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.I8.checked_sub"

pub checked_mul : I8, I8 -> Result(I8, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.I8.checked_mul"

pub wrapping_add : I8, I8 -> I8
pub wrapping_add = |a, b| crash "intrinsic: Num.I8.wrapping_add"

pub saturating_add : I8, I8 -> I8
pub saturating_add = |a, b| crash "intrinsic: Num.I8.saturating_add"

pub saturating_sub : I8, I8 -> I8
pub saturating_sub = |a, b| crash "intrinsic: Num.I8.saturating_sub"

pub to_str : I8 -> Str
pub to_str = |n| crash "intrinsic: Num.I8.to_str"

pub from_str : Str -> Result(I8, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.I8.from_str"

pub bitwise_and : I8, I8 -> I8
pub bitwise_and = |a, b| a & b

pub bitwise_or : I8, I8 -> I8
pub bitwise_or = |a, b| a | b

pub bitwise_xor : I8, I8 -> I8
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : I8 -> I8
pub bitwise_not = |a| ~a

pub shift_left : I8, I8 -> I8
pub shift_left = |a, n| a << n

pub shift_right : I8, I8 -> I8
pub shift_right = |a, n| a >> n

pub count_ones : I8 -> I8
pub count_ones = |n| crash "intrinsic: Num.I8.count_ones"

pub leading_zeros : I8 -> I8
pub leading_zeros = |n| crash "intrinsic: Num.I8.leading_zeros"

pub trailing_zeros : I8 -> I8
pub trailing_zeros = |n| crash "intrinsic: Num.I8.trailing_zeros"`

NUM_U64_CAMP :: `-- Num/U64.camp
-- Operations on U64. Unsigned — no abs or neg.

pub clamp : U64, U64, U64 -> U64
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : U64, U64 -> U64
pub max = |a, b| if a > b { a } else { b }

pub min : U64, U64 -> U64
pub min = |a, b| if a < b { a } else { b }

pub checked_add : U64, U64 -> Result(U64, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.U64.checked_add"

pub checked_sub : U64, U64 -> Result(U64, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.U64.checked_sub"

pub checked_mul : U64, U64 -> Result(U64, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.U64.checked_mul"

pub wrapping_add : U64, U64 -> U64
pub wrapping_add = |a, b| crash "intrinsic: Num.U64.wrapping_add"

pub saturating_add : U64, U64 -> U64
pub saturating_add = |a, b| crash "intrinsic: Num.U64.saturating_add"

pub saturating_sub : U64, U64 -> U64
pub saturating_sub = |a, b| crash "intrinsic: Num.U64.saturating_sub"

pub to_str : U64 -> Str
pub to_str = |n| crash "intrinsic: Num.U64.to_str"

pub from_str : Str -> Result(U64, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.U64.from_str"

pub range : U64, U64 -> Iter(U64)
pub range = |start, end| crash "intrinsic: Num.U64.range"

pub bitwise_and : U64, U64 -> U64
pub bitwise_and = |a, b| a & b

pub bitwise_or : U64, U64 -> U64
pub bitwise_or = |a, b| a | b

pub bitwise_xor : U64, U64 -> U64
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : U64 -> U64
pub bitwise_not = |a| ~a

pub shift_left : U64, U64 -> U64
pub shift_left = |a, n| a << n

pub shift_right : U64, U64 -> U64
pub shift_right = |a, n| a >> n

pub count_ones : U64 -> U64
pub count_ones = |n| crash "intrinsic: Num.U64.count_ones"

pub leading_zeros : U64 -> U64
pub leading_zeros = |n| crash "intrinsic: Num.U64.leading_zeros"

pub trailing_zeros : U64 -> U64
pub trailing_zeros = |n| crash "intrinsic: Num.U64.trailing_zeros"`

NUM_U32_CAMP :: `-- Num/U32.camp
-- Operations on U32. Unsigned — no abs or neg.

pub clamp : U32, U32, U32 -> U32
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : U32, U32 -> U32
pub max = |a, b| if a > b { a } else { b }

pub min : U32, U32 -> U32
pub min = |a, b| if a < b { a } else { b }

pub checked_add : U32, U32 -> Result(U32, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.U32.checked_add"

pub checked_sub : U32, U32 -> Result(U32, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.U32.checked_sub"

pub checked_mul : U32, U32 -> Result(U32, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.U32.checked_mul"

pub wrapping_add : U32, U32 -> U32
pub wrapping_add = |a, b| crash "intrinsic: Num.U32.wrapping_add"

pub saturating_add : U32, U32 -> U32
pub saturating_add = |a, b| crash "intrinsic: Num.U32.saturating_add"

pub saturating_sub : U32, U32 -> U32
pub saturating_sub = |a, b| crash "intrinsic: Num.U32.saturating_sub"

pub to_str : U32 -> Str
pub to_str = |n| crash "intrinsic: Num.U32.to_str"

pub from_str : Str -> Result(U32, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.U32.from_str"

pub bitwise_and : U32, U32 -> U32
pub bitwise_and = |a, b| a & b

pub bitwise_or : U32, U32 -> U32
pub bitwise_or = |a, b| a | b

pub bitwise_xor : U32, U32 -> U32
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : U32 -> U32
pub bitwise_not = |a| ~a

pub shift_left : U32, U32 -> U32
pub shift_left = |a, n| a << n

pub shift_right : U32, U32 -> U32
pub shift_right = |a, n| a >> n

pub count_ones : U32 -> U32
pub count_ones = |n| crash "intrinsic: Num.U32.count_ones"

pub leading_zeros : U32 -> U32
pub leading_zeros = |n| crash "intrinsic: Num.U32.leading_zeros"

pub trailing_zeros : U32 -> U32
pub trailing_zeros = |n| crash "intrinsic: Num.U32.trailing_zeros"`

NUM_U16_CAMP :: `-- Num/U16.camp
-- Operations on U16. Unsigned — no abs or neg.

pub clamp : U16, U16, U16 -> U16
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : U16, U16 -> U16
pub max = |a, b| if a > b { a } else { b }

pub min : U16, U16 -> U16
pub min = |a, b| if a < b { a } else { b }

pub checked_add : U16, U16 -> Result(U16, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.U16.checked_add"

pub checked_sub : U16, U16 -> Result(U16, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.U16.checked_sub"

pub checked_mul : U16, U16 -> Result(U16, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.U16.checked_mul"

pub wrapping_add : U16, U16 -> U16
pub wrapping_add = |a, b| crash "intrinsic: Num.U16.wrapping_add"

pub saturating_add : U16, U16 -> U16
pub saturating_add = |a, b| crash "intrinsic: Num.U16.saturating_add"

pub saturating_sub : U16, U16 -> U16
pub saturating_sub = |a, b| crash "intrinsic: Num.U16.saturating_sub"

pub to_str : U16 -> Str
pub to_str = |n| crash "intrinsic: Num.U16.to_str"

pub from_str : Str -> Result(U16, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.U16.from_str"

pub bitwise_and : U16, U16 -> U16
pub bitwise_and = |a, b| a & b

pub bitwise_or : U16, U16 -> U16
pub bitwise_or = |a, b| a | b

pub bitwise_xor : U16, U16 -> U16
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : U16 -> U16
pub bitwise_not = |a| ~a

pub shift_left : U16, U16 -> U16
pub shift_left = |a, n| a << n

pub shift_right : U16, U16 -> U16
pub shift_right = |a, n| a >> n

pub count_ones : U16 -> U16
pub count_ones = |n| crash "intrinsic: Num.U16.count_ones"

pub leading_zeros : U16 -> U16
pub leading_zeros = |n| crash "intrinsic: Num.U16.leading_zeros"

pub trailing_zeros : U16 -> U16
pub trailing_zeros = |n| crash "intrinsic: Num.U16.trailing_zeros"`

NUM_U8_CAMP :: `-- Num/U8.camp
-- Operations on U8. Unsigned — no abs or neg.

pub clamp : U8, U8, U8 -> U8
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : U8, U8 -> U8
pub max = |a, b| if a > b { a } else { b }

pub min : U8, U8 -> U8
pub min = |a, b| if a < b { a } else { b }

pub checked_add : U8, U8 -> Result(U8, [Overflow])
pub checked_add = |a, b| crash "intrinsic: Num.U8.checked_add"

pub checked_sub : U8, U8 -> Result(U8, [Overflow])
pub checked_sub = |a, b| crash "intrinsic: Num.U8.checked_sub"

pub checked_mul : U8, U8 -> Result(U8, [Overflow])
pub checked_mul = |a, b| crash "intrinsic: Num.U8.checked_mul"

pub wrapping_add : U8, U8 -> U8
pub wrapping_add = |a, b| crash "intrinsic: Num.U8.wrapping_add"

pub saturating_add : U8, U8 -> U8
pub saturating_add = |a, b| crash "intrinsic: Num.U8.saturating_add"

pub saturating_sub : U8, U8 -> U8
pub saturating_sub = |a, b| crash "intrinsic: Num.U8.saturating_sub"

pub to_str : U8 -> Str
pub to_str = |n| crash "intrinsic: Num.U8.to_str"

pub from_str : Str -> Result(U8, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.U8.from_str"

pub bitwise_and : U8, U8 -> U8
pub bitwise_and = |a, b| a & b

pub bitwise_or : U8, U8 -> U8
pub bitwise_or = |a, b| a | b

pub bitwise_xor : U8, U8 -> U8
pub bitwise_xor = |a, b| a ^ b

pub bitwise_not : U8 -> U8
pub bitwise_not = |a| ~a

pub shift_left : U8, U8 -> U8
pub shift_left = |a, n| a << n

pub shift_right : U8, U8 -> U8
pub shift_right = |a, n| a >> n

pub count_ones : U8 -> U8
pub count_ones = |n| crash "intrinsic: Num.U8.count_ones"

pub leading_zeros : U8 -> U8
pub leading_zeros = |n| crash "intrinsic: Num.U8.leading_zeros"

pub trailing_zeros : U8 -> U8
pub trailing_zeros = |n| crash "intrinsic: Num.U8.trailing_zeros"`

NUM_F64_CAMP :: `-- Num/F64.camp
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
pub from_i64 = |n| crash "intrinsic: Num.F64.from_i64"`

NUM_F32_CAMP :: `-- Num/F32.camp
-- Operations on F32.

pub abs : F32 -> F32
pub abs = |n| crash "intrinsic: Num.F32.abs"

pub clamp : F32, F32, F32 -> F32
pub clamp = |lo, hi, n| if n < lo { lo } else if n > hi { hi } else { n }

pub max : F32, F32 -> F32
pub max = |a, b| crash "intrinsic: Num.F32.max"

pub min : F32, F32 -> F32
pub min = |a, b| crash "intrinsic: Num.F32.min"

pub neg : F32 -> F32
pub neg = |n| 0.0 - n

pub ceiling : F32 -> F32
pub ceiling = |n| crash "intrinsic: Num.F32.ceiling"

pub floor : F32 -> F32
pub floor = |n| crash "intrinsic: Num.F32.floor"

pub round : F32 -> F32
pub round = |n| crash "intrinsic: Num.F32.round"

pub truncate : F32 -> F32
pub truncate = |n| crash "intrinsic: Num.F32.truncate"

pub is_nan : F32 -> Bool
pub is_nan = |n| crash "intrinsic: Num.F32.is_nan"

pub is_infinite : F32 -> Bool
pub is_infinite = |n| crash "intrinsic: Num.F32.is_infinite"

pub is_finite : F32 -> Bool
pub is_finite = |n| crash "intrinsic: Num.F32.is_finite"

pub pi : F32
pub pi = 3.14159265

pub e : F32
pub e = 2.71828182

pub nan : F32
pub nan = crash "intrinsic: Num.F32.nan"

pub infinity : F32
pub infinity = crash "intrinsic: Num.F32.infinity"

pub neg_infinity : F32
pub neg_infinity = crash "intrinsic: Num.F32.neg_infinity"

pub sin : F32 -> F32
pub sin = |n| crash "intrinsic: Num.F32.sin"

pub cos : F32 -> F32
pub cos = |n| crash "intrinsic: Num.F32.cos"

pub tan : F32 -> F32
pub tan = |n| crash "intrinsic: Num.F32.tan"

pub asin : F32 -> F32
pub asin = |n| crash "intrinsic: Num.F32.asin"

pub acos : F32 -> F32
pub acos = |n| crash "intrinsic: Num.F32.acos"

pub atan : F32 -> F32
pub atan = |n| crash "intrinsic: Num.F32.atan"

pub atan2 : F32, F32 -> F32
pub atan2 = |y, x| crash "intrinsic: Num.F32.atan2"

pub exp : F32 -> F32
pub exp = |n| crash "intrinsic: Num.F32.exp"

pub log : F32 -> F32
pub log = |n| crash "intrinsic: Num.F32.log"

pub log2 : F32 -> F32
pub log2 = |n| crash "intrinsic: Num.F32.log2"

pub log10 : F32 -> F32
pub log10 = |n| crash "intrinsic: Num.F32.log10"

pub pow : F32, F32 -> F32
pub pow = |base, exp| crash "intrinsic: Num.F32.pow"

pub sqrt : F32 -> F32
pub sqrt = |n| crash "intrinsic: Num.F32.sqrt"

pub to_str : F32 -> Str
pub to_str = |n| crash "intrinsic: Num.F32.to_str"

pub from_str : Str -> Result(F32, [InvalidFormat])
pub from_str = |s| crash "intrinsic: Num.F32.from_str"

pub to_i64 : F32 -> I64
pub to_i64 = |n| crash "intrinsic: Num.F32.to_i64"

pub from_i64 : I64 -> F32
pub from_i64 = |n| crash "intrinsic: Num.F32.from_i64"`

BYTES_CAMP :: `-- @Bytes -- opaque contiguous byte buffer, provided by runtime
-- Per D19: Lean module (construction, queries, access, slicing, concat).
-- Conversions via traits: From(Str, Bytes) infallible,
-- TryFrom(Bytes, Str, [InvalidUtf8]) fallible.

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
pub to_str = |b| crash "intrinsic: Bytes.to_str"`

EQ_CAMP :: `-- Eq trait -- structural equality

Eq(a) : {
  eq : (a, a) -> Bool,
}`

ORD_CAMP :: `-- Ord trait -- total ordering
-- Per D16: Order is structural tag union [Less | Equal | Greater]

@Order : pub [Less | Equal | Greater]

Ord(a) : is Eq(a) {
  compare : (a, a) -> Order,
}`

HASH_CAMP :: `-- Hash trait -- hashing for map/set keys
-- Per D29: Hasher is opaque (SipHash-1-3 internally)

@Hasher : -- opaque, provided by runtime

Hash(a) : {
  hash : (a, Hasher) -> Hasher,
}`

DEBUG_CAMP :: `-- Debug trait -- developer-facing string representation

Debug(a) : {
  debug : a -> Str,
}`

DEFAULT_CAMP :: `-- Default trait -- default/zero values

Default(a) : {
  default : a,
}`


INTO_ITER_CAMP :: `-- IntoIter trait -- convert a collection into an iterator

IntoIter(a) : {
  to_iter : Self(a) -> Iter(a),
}`

FROM_ITER_CAMP :: `-- FromIter trait -- construct a collection from an iterator

FromIter(c, a) : {
  from_iter : Iter(a) -> c,
}`

FROM_CAMP :: `-- From trait -- infallible type conversion

From(source, target) : {
  from : source -> target,
}`

TRY_FROM_CAMP :: `-- TryFrom trait -- fallible type conversion

TryFrom(source, target, e) : {
  try_from : source -> Result(target, e),
}`

CONSOLE_CAMP :: `-- Console! effect -- standard I/O
-- Per D23: Only foo! variants. Use Result.catch for Result versions.

effect Console! : {
  println! : Str -> -[Console!]-> (),
  print!   : Str -> -[Console!]-> (),
  readline! : -[Console!]-> Str,
}`

THROW_CAMP :: `-- Throw! effect -- error propagation
-- Per D4: Throw! for propagated, effectful, action-level errors.
-- Bridge: Result.catch (Throw!-->Result) and Result.unwrap! (Result-->Throw!)

effect Throw!(e) : {
  raise! : e -> -[Throw!(e)]-> a,
}`

FILE_CAMP :: `-- File! effect -- filesystem access
-- Per D23: Only foo! variants. FileErr keeps IoErr as catch-all for v1.

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
}`

ENV_CAMP :: `-- Env! effect -- environment variables
-- Per D23: Env.try_get returns Result, not Throw!

effect Env! : {
  get!     : Str -> -[Env!, Throw!([VarNotFound])]-> Str,
  try_get  : Str -> -[Env!]-> Result(Str, [VarNotFound]),
  vars!    : -[Env!]-> List((Str, Str)),
  args!    : -[Env!]-> List(Str),
}`

TIME_CAMP :: `-- Time! effect -- time access
-- Per D24: Duration only; DateTime is a separate package.

effect Time! : {
  now!       : -[Time!]-> Duration,
  monotonic! : -[Time!]-> Duration,
}`

RANDOM_CAMP :: `-- Random! effect — two handlers: random_prng (fast PRNG) and random_crypto (WASI random_get)
-- Per D31: one effect, two handlers. Handler choice determines security guarantees.

effect Random! : {
  int!   : I64, I64 -> -[Random!]-> I64,
  float! : F64, F64 -> -[Random!]-> F64,
  bytes! : I64 -> -[Random!]-> Bytes,
  bool!  : -[Random!]-> Bool,
}`

LOG_CAMP :: `-- Log! effect -- message-only logging
-- Per D15: Message-only. Structured logging is a package concern.

effect Log! : {
  debug! : Str -> -[Log!]-> (),
  info!  : Str -> -[Log!]-> (),
  warn!  : Str -> -[Log!]-> (),
  error! : Str -> -[Log!]-> (),
}`

PATH_CAMP :: `-- @Path -- opaque filesystem path, normalized on construction
-- Per D25: Opaque type, auto-normalized. No I/O on Path -- that's in File!.

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
pub to_iter = |p| crash "intrinsic: Path.to_iter"`

DURATION_CAMP :: `-- @Duration -- time duration (Rust-style signed struct)
-- Per D24: { secs: I64, nanos: I64 } internally. Signed, ~584B yr range.
-- DateTime is a separate package, not stdlib.

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

-- Comparison (via Ord)

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
pub nanosecond = crash "intrinsic: Duration.nanosecond"`

FMT_CAMP :: `-- Fmt module -- formatting utilities
-- Per D28: Houses Display/Debug traits. Format specifiers go in interpolation syntax.

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
pub pad_right = |s, width, fill| crash "intrinsic: Fmt.pad_right"`

UUID_CAMP :: `-- Uuid.camp — Universally Unique Identifiers
-- Per D38: v4!/v7! use Random! only. Handler choice determines security.

@Uuid : pub Bytes                              -- 16 bytes, opaque

@UuidErr : pub [
    InvalidFormat(Str)
  | InvalidLength(U64)
  | InvalidVersion(U8)
]

@UuidVariant : pub [V4 | V7 | Unknown(U8)]
@UuidFormat  : pub [Standard | Compact | Urn | Braced]

-- Generation — effectful (intrinsic)

pub v4! : -[Random!]-> Uuid
pub v4! = || crash "intrinsic: Uuid.v4"

pub v7! : I64 -> -[Random!]-> Uuid              -- timestamp in milliseconds
pub v7! = |_ts| crash "intrinsic: Uuid.v7"

-- Parsing — pure Camp

pub parse : Str -> Result(Uuid, UuidErr)
pub parse = |_s| crash "intrinsic: Uuid.parse"  -- TODO: pure Camp implementation

pub from_bytes : Bytes -> Result(Uuid, UuidErr)
pub from_bytes = |_b| crash "intrinsic: Uuid.from_bytes"  -- TODO: pure Camp implementation

-- Formatting — pure Camp

pub to_str : Uuid -> Str
pub to_str = |_u| crash "intrinsic: Uuid.to_str"  -- TODO: pure Camp implementation

pub format : UuidFormat, Uuid -> Str
pub format = |_fmt, _u| crash "intrinsic: Uuid.format"  -- TODO: pure Camp implementation

pub to_bytes : Uuid -> Bytes
pub to_bytes = |u| u                           -- @Uuid wraps Bytes

-- Inspection — pure Camp

pub version : Uuid -> U8
pub version = |_u| crash "intrinsic: Uuid.version"  -- TODO: pure Camp implementation

pub variant : Uuid -> UuidVariant
pub variant = |_u| crash "intrinsic: Uuid.variant"  -- TODO: pure Camp implementation

pub timestamp : Uuid -> Result(I64, [Absent])   -- V7 only; Err if not V7
pub timestamp = |_u| crash "intrinsic: Uuid.timestamp"  -- TODO: pure Camp implementation`

URI_CAMP :: `-- Uri.camp — URI/URL parsing and construction
-- Per D36: query stored as raw string with parse_query/format_query helpers.
-- Pure Camp — RFC 3986 parsing is bounded-complexity string scanning.

@UriAuthority : pub {
    userinfo : Result(Str, [Absent]),              -- "user:password" (deprecated per RFC 3986 §3.2.1)
    host     : Str,
    port     : Result(U16, [Absent])
}

@Uri : pub {
    scheme    : Str,
    authority : Result(UriAuthority, [Absent]),
    path      : Str,
    query     : Result(Str, [Absent]),             -- D36: raw percent-encoded string
    fragment  : Result(Str, [Absent])
}

@UriErr : pub [
    InvalidScheme(Str)
  | InvalidHost(Str)
  | InvalidPort(Str)
  | InvalidEscape(Str)
  | MissingScheme
]

-- Parsing and formatting — pure Camp

pub parse : Str -> Result(Uri, UriErr)
pub parse = |_s| crash "intrinsic: Uri.parse"  -- TODO: pure Camp implementation

pub to_str : Uri -> Str
pub to_str = |_u| crash "intrinsic: Uri.to_str"  -- TODO: pure Camp implementation

-- Component-level percent encoding — pure Camp

pub encode_component : Str -> Str               -- percent-encode for URI component
pub encode_component = |_s| crash "intrinsic: Uri.encode_component"  -- TODO: pure Camp implementation

pub decode_component : Str -> Result(Str, UriErr)  -- percent-decode
pub decode_component = |_s| crash "intrinsic: Uri.decode_component"  -- TODO: pure Camp implementation

-- Query string parsing (convenience) — pure Camp

pub parse_query : Str -> List((Str, Str))        -- "a=1&b=2" -> [("a","1"), ("b","2")]
pub parse_query = |_s| crash "intrinsic: Uri.parse_query"  -- TODO: pure Camp implementation

pub format_query : List((Str, Str)) -> Str      -- reverse
pub format_query = |_pairs| crash "intrinsic: Uri.format_query"  -- TODO: pure Camp implementation

-- Functional construction helpers — pure Camp

pub with_scheme : Str, Uri -> Uri
pub with_scheme = |s, u| { scheme: s, authority: u.authority, path: u.path, query: u.query, fragment: u.fragment }

pub with_authority : Result(UriAuthority, [Absent]), Uri -> Uri
pub with_authority = |a, u| { scheme: u.scheme, authority: a, path: u.path, query: u.query, fragment: u.fragment }

pub with_path : Str, Uri -> Uri
pub with_path = |p, u| { scheme: u.scheme, authority: u.authority, path: p, query: u.query, fragment: u.fragment }

pub with_query : Result(Str, [Absent]), Uri -> Uri
pub with_query = |q, u| { scheme: u.scheme, authority: u.authority, path: u.path, query: q, fragment: u.fragment }

pub with_fragment : Result(Str, [Absent]), Uri -> Uri
pub with_fragment = |f, u| { scheme: u.scheme, authority: u.authority, path: u.path, query: u.query, fragment: f }`

BASE64_CAMP :: `-- Base64.camp — Base64/Base32/Hex encoding and decoding
-- Per D39: parameterized by Base64Format plus shorthand convenience functions.
-- Pure Camp — lookup table + bit shifting, no C runtime needed.

@Base64Format : pub [Standard | UrlSafe | Base32 | Hex]

@Base64Err : pub [
    InvalidChar(U64, Str)                       -- position + bad character
  | InvalidLength
  | InvalidPadding
]

-- Core encode/decode (parameterized) — pure Camp

pub encode : Base64Format, Bytes -> Str
pub encode = |_fmt, _bytes| crash "intrinsic: Base64.encode"  -- TODO: pure Camp implementation

pub decode : Base64Format, Str -> Result(Bytes, Base64Err)
pub decode = |_fmt, _s| crash "intrinsic: Base64.decode"  -- TODO: pure Camp implementation

-- String convenience (UTF-8 encode/decode internally) — pure Camp

pub encode_str : Base64Format, Str -> Str
pub encode_str = |fmt, s| encode(fmt, Str.to_bytes(s))

pub decode_str : Base64Format, Str -> Result(Str, Base64Err)
pub decode_str = |fmt, s| match decode(fmt, s) {
  Ok(bytes) -> Ok(Bytes.to_str(bytes))
  Err(e)    -> Err(e)
}

-- Format-specific shorthands — pure Camp

pub encode64 : Bytes -> Str                     -- Standard Base64
pub encode64 = |b| encode(Standard, b)

pub decode64 : Str -> Result(Bytes, Base64Err)
pub decode64 = |s| decode(Standard, s)

pub encode64url : Bytes -> Str                  -- URL-safe Base64
pub encode64url = |b| encode(UrlSafe, b)

pub decode64url : Str -> Result(Bytes, Base64Err)
pub decode64url = |s| decode(UrlSafe, s)

pub encode16 : Bytes -> Str                     -- Hex, lowercase
pub encode16 = |b| encode(Hex, b)

pub decode16 : Str -> Result(Bytes, Base64Err)
pub decode16 = |s| decode(Hex, s)`

JSON_CAMP :: `-- Json.camp — JSON parsing, encoding, and streaming
-- Per D34: Obj uses Map(Str, JsonValue) for O(log n) lookup.
-- Per D35: JsonNumber preserves integer/float distinction.

@JsonNumber : pub [
    PosInt(U64)                                -- non-negative integer
  | NegInt(I64)                                -- negative integer
  | Float(F64)                                 -- finite float (never NaN/Inf)
]

@JsonValue : pub [
    Null
  | Bool(Bool)
  | Num(JsonNumber)                            -- D35: preserves int/float distinction
  | Str(Str)
  | Arr(List(JsonValue))
  | Obj(Map(Str, JsonValue))                   -- D34: Map for O(log n) lookup
]

@JsonErr : pub [
    UnexpectedChar(U64, Str)                  -- position + description
  | InvalidNumber(U64, Str)
  | UnexpectedEnd
  | TrailingContent(U64)
]

-- Core DOM API — intrinsic

pub decode : Str -> Result(JsonValue, JsonErr)
pub decode = |_s| crash "intrinsic: Json.decode"

pub encode : JsonValue -> Str
pub encode = |_v| crash "intrinsic: Json.encode"

pub encode_pretty : JsonValue -> Str            -- 2-space indent
pub encode_pretty = |_v| crash "intrinsic: Json.encode_pretty"

-- JsonNumber accessors — pure Camp

pub is_int : JsonNumber -> Bool
pub is_int = |n| match n {
  PosInt(_) -> True
  NegInt(_) -> True
  Float(_)  -> False
}

pub is_float : JsonNumber -> Bool
pub is_float = |n| match n {
  Float(_)  -> True
  PosInt(_) -> False
  NegInt(_) -> False
}

pub as_i64 : JsonNumber -> Result(I64, [Absent])
pub as_i64 = |n| match n {
  NegInt(i) -> Ok(i)
  PosInt(_) -> Err(Absent)   -- TODO: check if <= I64_MAX
  Float(_)  -> Err(Absent)
}

pub as_u64 : JsonNumber -> Result(U64, [Absent])
pub as_u64 = |n| match n {
  PosInt(u) -> Ok(u)
  NegInt(_) -> Err(Absent)
  Float(_)  -> Err(Absent)
}

pub as_f64 : JsonNumber -> Result(F64, [Absent])
pub as_f64 = |n| match n {
  Float(f)  -> Ok(f)
  PosInt(_) -> Err(Absent)   -- TODO: always Ok (every JsonNumber can be F64)
  NegInt(_) -> Err(Absent)   -- TODO: always Ok
}

-- JsonValue convenience accessors — pure Camp

pub get : JsonValue, Str -> Result(JsonValue, JsonErr)
pub get = |_v, _key| crash "intrinsic: Json.get"  -- TODO: pure Camp implementation

pub get_at : JsonValue, U64 -> Result(JsonValue, JsonErr)
pub get_at = |_v, _idx| crash "intrinsic: Json.get_at"  -- TODO: pure Camp implementation

pub keys : JsonValue -> Result(List(Str), [Absent])
pub keys = |_v| crash "intrinsic: Json.keys"  -- TODO: pure Camp implementation

pub values : JsonValue -> Result(List(JsonValue), [Absent])
pub values = |_v| crash "intrinsic: Json.values"  -- TODO: pure Camp implementation

pub length : JsonValue -> Result(U64, [Absent])
pub length = |_v| crash "intrinsic: Json.length"  -- TODO: pure Camp implementation

-- Streaming parser — intrinsic

@JsonEvent : pub [
    StartObj
  | EndObj
  | StartArr
  | EndArr
  | Key(Str)
  | Null
  | Bool(Bool)
  | Num(JsonNumber)
  | Str(Str)
]

@JsonParser : pub { source : Str, pos : U64, depth : U64 }

pub parse_init : Str -> JsonParser
pub parse_init = |_s| crash "intrinsic: Json.parse_init"

pub parse_next : JsonParser -> Result((JsonParser, JsonEvent), JsonErr)
pub parse_next = |_p| crash "intrinsic: Json.parse_next"

pub parse_all : Str -> Result(List(JsonEvent), JsonErr)
pub parse_all = |_s| crash "intrinsic: Json.parse_all"`

REGEX_CAMP :: `-- Regex.camp — RE2-style regular expressions
-- Per D37: guaranteed O(n), no backtracking, no backreferences, no lookahead/lookbehind.

@Regex : pub { pattern : Str }                  -- opaque compiled regex

@RegexErr : pub [
    CompileError(Str)
  | InvalidEscape(Str)
  | InvalidRepeat(Str)
]

@MatchGroup : pub { value : Str, start : U64, end : U64 }
@Match : pub { full : Str, start : U64, end : U64, groups : List(MatchGroup) }

-- Compilation — intrinsic

pub compile : Str -> Result(Regex, RegexErr)
pub compile = |_pat| crash "intrinsic: Regex.compile"

pub is_match : Regex, Str -> Bool
pub is_match = |_r, _s| crash "intrinsic: Regex.is_match"

-- Search — intrinsic

pub find : Regex, Str -> Result(Match, [Absent])   -- first match only
pub find = |_r, _s| crash "intrinsic: Regex.find"

pub find_all : Regex, Str -> List(Match)        -- all non-overlapping matches
pub find_all = |_r, _s| crash "intrinsic: Regex.find_all"

-- Transformation — intrinsic

pub replace : Regex, Str, Str -> Str            -- first match, literal replacement
pub replace = |_r, _s, _rep| crash "intrinsic: Regex.replace"

pub replace_all : Regex, Str, Str -> Str        -- all matches, literal replacement
pub replace_all = |_r, _s, _rep| crash "intrinsic: Regex.replace_all"

pub split : Regex, Str -> List(Str)             -- split on matches
pub split = |_r, _s| crash "intrinsic: Regex.split"

pub splitn : Regex, Str, U64 -> List(Str)       -- at most n-1 splits
pub splitn = |_r, _s, _n| crash "intrinsic: Regex.splitn"

-- Utility — pure Camp

pub escape : Str -> Str                          -- escape regex metacharacters
pub escape = |_s| crash "intrinsic: Regex.escape"  -- TODO: pure Camp implementation`

STDLIB_MODULES: []Stdlib_Module = []Stdlib_Module {
	{"Result", RESULT_CAMP, "stdlib/Result.camp"},
	{"Bool", BOOL_CAMP, "stdlib/Bool.camp"},
	{"Str", STR_CAMP, "stdlib/Str.camp"},
	{"List", LIST_CAMP, "stdlib/List.camp"},
	{"Iter", ITER_CAMP, "stdlib/Iter.camp"},
	{"Map", MAP_CAMP, "stdlib/Map.camp"},
	{"Set", SET_CAMP, "stdlib/Set.camp"},
	{"Display", DISPLAY_CAMP, "stdlib/Display.camp"},
	{"Num.I64", NUM_I64_CAMP, "stdlib/Num/I64.camp"},
	{"Num.I32", NUM_I32_CAMP, "stdlib/Num/I32.camp"},
	{"Num.I16", NUM_I16_CAMP, "stdlib/Num/I16.camp"},
	{"Num.I8", NUM_I8_CAMP, "stdlib/Num/I8.camp"},
	{"Num.U64", NUM_U64_CAMP, "stdlib/Num/U64.camp"},
	{"Num.U32", NUM_U32_CAMP, "stdlib/Num/U32.camp"},
	{"Num.U16", NUM_U16_CAMP, "stdlib/Num/U16.camp"},
	{"Num.U8", NUM_U8_CAMP, "stdlib/Num/U8.camp"},
	{"Num.F64", NUM_F64_CAMP, "stdlib/Num/F64.camp"},
	{"Num.F32", NUM_F32_CAMP, "stdlib/Num/F32.camp"},
	{"Bytes", BYTES_CAMP, "stdlib/Bytes.camp"},
	{"Eq", EQ_CAMP, "stdlib/Eq.camp"},
	{"Ord", ORD_CAMP, "stdlib/Ord.camp"},
	{"Hash", HASH_CAMP, "stdlib/Hash.camp"},
	{"Debug", DEBUG_CAMP, "stdlib/Debug.camp"},
	{"Default", DEFAULT_CAMP, "stdlib/Default.camp"},
	{"IntoIter", INTO_ITER_CAMP, "stdlib/IntoIter.camp"},
	{"FromIter", FROM_ITER_CAMP, "stdlib/FromIter.camp"},
	{"From", FROM_CAMP, "stdlib/From.camp"},
	{"TryFrom", TRY_FROM_CAMP, "stdlib/TryFrom.camp"},
	{"Console", CONSOLE_CAMP, "stdlib/Console.camp"},
	{"Throw", THROW_CAMP, "stdlib/Throw.camp"},
	{"File", FILE_CAMP, "stdlib/File.camp"},
	{"Env", ENV_CAMP, "stdlib/Env.camp"},
	{"Time", TIME_CAMP, "stdlib/Time.camp"},
	{"Random", RANDOM_CAMP, "stdlib/Random.camp"},
	{"Log", LOG_CAMP, "stdlib/Log.camp"},
	{"Path", PATH_CAMP, "stdlib/Path.camp"},
	{"Duration", DURATION_CAMP, "stdlib/Duration.camp"},
	{"Fmt", FMT_CAMP, "stdlib/Fmt.camp"},
	{"Uuid", UUID_CAMP, "stdlib/Uuid.camp"},
	{"Json", JSON_CAMP, "stdlib/Json.camp"},
	{"Regex", REGEX_CAMP, "stdlib/Regex.camp"},
	{"Uri", URI_CAMP, "stdlib/Uri.camp"},
	{"Base64", BASE64_CAMP, "stdlib/Base64.camp"},
}

stdlib_lookup :: proc(name: string) -> (Stdlib_Module, bool) {
	for mod in STDLIB_MODULES {
		if mod.name == name {
			return mod, true
		}
	}
	return Stdlib_Module{}, false
}

stdlib_is_module :: proc(name: string) -> bool {
	_, ok := stdlib_lookup(name)
	return ok
}

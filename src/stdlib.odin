package camp

// Stdlib module registry — embedded .camp source files
// These are parsed and typechecked on demand when imported by user code.

Stdlib_Module :: struct {
	name:   string,
	source: string,
	path:   string,
}

RESULT_CAMP :: `Result : <a, e> [Ok(a) | Err(e)]

is_ok = <a, e>|r: Result(a, e)| -> Bool {
  match r { Ok(_) => True | Err(_) => False }
}

is_err = <a, e>|r: Result(a, e)| -> Bool {
  match r { Ok(_) => False | Err(_) => True }
}

map = <a, b, e>|f: |a| -> b, r: Result(a, e)| -> Result(b, e) {
  match r { Ok(v) => Ok(f(v)) | Err(e) => Err(e) }
}

map_err = <a, e, f>|f: |e| -> f, r: Result(a, e)| -> Result(a, f) {
  match r { Ok(v) => Ok(v) | Err(e) => Err(f(e)) }
}

and_then = <a, b, e>|f: |a| -> Result(b, e), r: Result(a, e)| -> Result(b, e) {
  match r { Ok(v) => f(v) | Err(e) => Err(e) }
}

or_else = <a, e, f>|f: || -> Result(a, f), r: Result(a, e)| -> Result(a, e) {
  match r { Ok(v) => Ok(v) | Err(_) => f() }
}

unwrap = <a, e>|r: Result(a, e)| -> a {
  match r { Ok(v) => v | Err(_) => crash "unwrap on Err" }
}

unwrap_or = <a, e>|default: a, r: Result(a, e)| -> a {
  match r { Ok(v) => v | Err(_) => default }
}`

OPTION_CAMP :: `Option : <a> [Some(a) | None]

is_some = <a>|o: Option(a)| -> Bool {
  match o { Some(_) => True | None => False }
}

is_none = <a>|o: Option(a)| -> Bool {
  match o { Some(_) => False | None => True }
}

map = <a, b>|f: |a| -> b, o: Option(a)| -> Option(b) {
  match o { Some(v) => Some(f(v)) | None => None }
}

and_then = <a, b>|f: |a| -> Option(b), o: Option(a)| -> Option(b) {
  match o { Some(v) => f(v) | None => None }
}

unwrap = <a>|o: Option(a)| -> a {
  match o { Some(v) => v | None => crash "unwrap on None" }
}

unwrap_or = <a>|default: a, o: Option(a)| -> a {
  match o { Some(v) => v | None => default }
}`

BOOL_CAMP :: `not = |b: Bool| -> Bool {
  match b { True => False | False => True }
}

xor = |a: Bool, b: Bool| -> Bool {
  match a { True => not(b) | False => b }
}`

INT_CAMP :: `abs = |n: I64| -> I64 {
  if n < 0 { 0 - n } else { n }
}

clamp = |lo: I64, hi: I64, n: I64| -> I64 {
  if n < lo { lo } else if n > hi { hi } else { n }
}

max = |a: I64, b: I64| -> I64 {
  if a > b { a } else { b }
}

min = |a: I64, b: I64| -> I64 {
  if a < b { a } else { b }
}`

STR_CAMP :: `length = |s: Str| -> I64 {
  crash "Str.length: not yet implemented"
}

is_empty = |s: Str| -> Bool {
  length(s) == 0
}

concat = |a: Str, b: Str| -> Str {
  crash "Str.concat: not yet implemented"
}

eq = |a: Str, b: Str| -> Bool {
  crash "Str.eq: not yet implemented"
}`

LIST_CAMP :: `length = <a>|xs: List(a)| -> I64 {
  match xs { Nil => 0 | Cons(_, t) => 1 + length(t) }
}

is_empty = <a>|xs: List(a)| -> Bool {
  length(xs) == 0
}

map = <a, b>|f: |a| -> b, xs: List(a)| -> List(b) {
  match xs { Nil => Nil | Cons(h, t) => Cons(f(h), map(f, t)) }
}

filter = <a>|pred: |a| -> Bool, xs: List(a)| -> List(a) {
  match xs {
    Nil => Nil,
    Cons(h, t) => if pred(h) { Cons(h, filter(pred, t)) } else { filter(pred, t) }
  }
}

fold = <a, b>|f: |b, a| -> b, init: b, xs: List(a)| -> b {
  match xs { Nil => init | Cons(h, t) => fold(f, f(init, h), t) }
}

append = <a>|xs: List(a), ys: List(a)| -> List(a) {
  match xs { Nil => ys | Cons(h, t) => Cons(h, append(t, ys)) }
}

head = <a>|xs: List(a)| -> Option(a) {
  match xs { Nil => None | Cons(h, _) => Some(h) }
}

alloc = <a>|| -> List(a) {
  crash "List.alloc: compiler intrinsic"
}

get = <a>|xs: List(a), i: I64| -> a {
  crash "List.get: compiler intrinsic"
}

push = <a>|xs: List(a), x: a| -> List(a) {
  crash "List.push: compiler intrinsic"
}`

ITER_CAMP :: `Iter : @{
  next: || -[e]-> [Some(a) | None],
}

empty : || -[]-> Iter(a)
empty = || @{
  next = || None,
}

singleton : a -[]-> Iter(a)
singleton = |x| @{
  next = ||
    consumed = True
    if consumed { None } else { consumed = True; Some(x) },
}

from_list : List(a) -[]-> Iter(a)
from_list = |list| @{
  next = ||
    match list {
      Cons(head, rest) => list = rest; Some(head),
      Nil => None,
    },
}

map : Iter(a), |a| -[e]-> b -[]-> Iter(b)
map = |iter, f| @{
  next = || match iter.next() {
    Some(x) => Some(f(x)),
    None => None,
  },
}

filter : Iter(a), |a| -[e]-> Bool -[]-> Iter(a)
filter = |iter, pred| @{
  next = ||
    match iter.next() {
      Some(x) => if pred(x) { Some(x) } else { iter.next() },
      None => None,
    },
}

fold : Iter(a), b, |b, a| -[e]-> b -[]-> b
fold = |iter, init, f| {
  acc = init
  cur = iter.next()
  while cur != None {
    Some(x) = cur
    acc = f(acc, x)
    cur = iter.next()
  }
  acc
}

collect : Iter(a) -[]-> List(a)
collect = |iter| {
  acc = []
  cur = iter.next()
  while cur != None {
    Some(x) = cur
    acc = List.append(acc, [x])
    cur = iter.next()
  }
  acc
}

count : Iter(a) -[]-> I64
count = |iter| fold(iter, 0, |n, _| n + 1)

for_each : Iter(a), |a| -[e]-> {} -[]-> {}
for_each = |iter, f| fold(iter, {}, |_, x| f(x))

find : Iter(a), |a| -[]-> Bool -[]-> Option(a)
find = |iter, pred| {
  cur = iter.next()
  while cur != None {
    Some(x) = cur
    if pred(x) { return Some(x) }
    cur = iter.next()
  }
  None
}

chain : Iter(a), Iter(a) -[]-> Iter(a)
chain = |first, second| @{
  next = ||
    match first.next() {
      Some(x) => Some(x),
      None => second.next(),
    },
}

take : Iter(a), I64 -[]-> Iter(a)
take = |iter, n| @{
  remaining = n
  next = ||
    if remaining <= 0 { None } else {
      remaining = remaining - 1
      iter.next()
    },
}

skip : Iter(a), I64 -[]-> Iter(a)
skip = |iter, n| @{
  next = ||
    i = 0
    while i < n {
      iter.next()
      i = i + 1
    }
    n = 0
    iter.next()
}

enumerate : Iter(a) -[]-> Iter((I64, a))
enumerate = |iter| @{
  index = 0
  next = || match iter.next() {
    Some(x) => idx = index; index = index + 1; Some((idx, x)),
    None => None,
  },
}

zip : Iter(a), Iter(b) -[]-> Iter((a, b))
zip = |left, right| @{
  next = ||
    match left.next() {
      Some(a) => match right.next() {
        Some(b) => Some((a, b)),
        None => None,
      },
      None => None,
    },
}`

DISPLAY_CAMP :: `Display : {
  to_str: (Self) -> Str,
}`

STDLIB_MODULES: []Stdlib_Module = []Stdlib_Module{
	{"Result", RESULT_CAMP, "stdlib/Result.camp"},
	{"Option", OPTION_CAMP, "stdlib/Option.camp"},
	{"Bool", BOOL_CAMP, "stdlib/Bool.camp"},
	{"Int", INT_CAMP, "stdlib/Int.camp"},
	{"Str", STR_CAMP, "stdlib/Str.camp"},
	{"List", LIST_CAMP, "stdlib/List.camp"},
	{"Iter", ITER_CAMP, "stdlib/Iter.camp"},
	{"Display", DISPLAY_CAMP, "stdlib/Display.camp"},
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

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
  crash "List.length: not yet implemented"
}

is_empty = <a>|xs: List(a)| -> Bool {
  length(xs) == 0
}

map = <a, b>|f: |a| -> b, xs: List(a)| -> List(b) {
  crash "List.map: not yet implemented"
}

filter = <a>|pred: |a| -> Bool, xs: List(a)| -> List(a) {
  crash "List.filter: not yet implemented"
}

fold = <a, b>|f: |b, a| -> b, init: b, xs: List(a)| -> b {
  crash "List.fold: not yet implemented"
}

append = <a>|xs: List(a), ys: List(a)| -> List(a) {
  crash "List.append: not yet implemented"
}

head = <a>|xs: List(a)| -> Option(a) {
  if is_empty(xs) { None } else { crash "List.head: indexing not yet implemented" }
}`

STDLIB_MODULES: []Stdlib_Module = []Stdlib_Module{
	{"Result", RESULT_CAMP, "stdlib/Result.camp"},
	{"Option", OPTION_CAMP, "stdlib/Option.camp"},
	{"Bool", BOOL_CAMP, "stdlib/Bool.camp"},
	{"Int", INT_CAMP, "stdlib/Int.camp"},
	{"Str", STR_CAMP, "stdlib/Str.camp"},
	{"List", LIST_CAMP, "stdlib/List.camp"},
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

# Standard Library — Unit Test Plan

> Design document for the full suite of unit tests to be written in pure Camp
> for every stdlib module. Covers current coverage, test gaps, and concrete
> test scenarios for each module. Does NOT address test infrastructure or runner
> design — only **what** to test and **why**.

---

## Table of Contents

1. [Principles & Test Design Rules](#1-principles--test-design-rules)
2. [Current Coverage Assessment](#2-current-coverage-assessment)
3. [Priority 1 Modules — Tests](#3-priority-1-modules--tests)
   - [3.1 Bool](#31-bool)
   - [3.2 Result](#32-result)
   - [3.3 List](#33-list)
   - [3.4 Iter](#34-iter)
   - [3.5 Map](#35-map)
   - [3.6 Set](#36-set)
   - [3.7 Str](#37-str)
   - [3.8 Bytes](#38-bytes)
   - [3.9 Num (I64, U64, F64, etc.)](#39-num-submodules)
   - [3.10 Eq / Ord / Order](#310-eq--ord--order)
   - [3.11 Hash / Hasher](#311-hash--hasher)
   - [3.12 Debug / Display / Default / Fmt](#312-debug--display--default--fmt)
   - [3.13 From / TryFrom](#313-from--tryfrom)
   - [3.14 IntoIter / FromIter](#314-intoiter--fromiter)
4. [Priority 1 Effect Modules](#4-priority-1-effect-modules)
   - [4.1 Console!](#41-console)
   - [4.2 Throw!](#42-throw)
   - [4.3 Result.unwrap! / Result.catch](#43-result-bridge-functions)
   - [4.4 File!](#44-file)
   - [4.5 Env!](#45-env)
   - [4.6 Time!](#46-time)
   - [4.7 Random!](#47-random)
   - [4.8 Log!](#48-log)
5. [Priority 2 Modules — Tests](#5-priority-2-modules--tests)
   - [5.1 Duration](#51-duration)
   - [5.2 Path](#52-path)
   - [5.3 Json](#53-json)
   - [5.4 Regex](#54-regex)
   - [5.5 Uri](#55-uri)
   - [5.6 Uuid](#56-uuid)
   - [5.7 Base64](#57-base64)
6. [Integration Test Scenarios](#6-integration-test-scenarios)
7. [Property-Based Test Recipes](#7-property-based-test-recipes)

---

## 1. Principles & Test Design Rules

### R1: Pure over effectful
Prefer pure Camp tests (no effects). They are deterministic, fast, and
self-contained. Effectful tests go in separate test modules or use handler-based
isolation.

### R2: One concern per test
Each `test "..." { ... }` block exercises exactly one function under one
condition. The test name names the condition, not the function. Bad: `test "map
{ ... }"`. Good: `test "map preserves Err payload through identity function"`.

### R3: Boundary-first coverage
For every function, test in order:
1. **Happy path** — typical inputs
2. **Empty/zero** — empty collection, zero value, empty string
3. **Singleton/single** — single element
4. **Multi-element** — generic case
5. **Error/edge** — out of bounds, missing key, invalid format
6. **Identity** — map with identity, filter with constant-true, etc.

### R4: Test the Camp, not the host
Intrinsic functions (declared `crash "intrinsic: ..."`) run host runtime code.
Tests for intrinsics verify the Camp-level contract (return type, pattern match
behavior, error semantics) — not the host implementation. Pure Camp functions
get exhaustive logical coverage.

### R5: Each test file lives alongside its module
Tests go in `stdlib/<Module>.camp` at the bottom of the file, below the
implementation. This keeps the spec, implementation, and tests co-located.

### R6: Zero tests = untested module
Any module with zero `test "..."` blocks is considered untested. The goal is
zero untested modules.

### R7: Integration tests span modules
A separate file `stdlib/integration.camp` (or inline in kitchen-sink) tests
cross-module interactions: `List` + `Iter`, `Result` + `Map`, etc.

### R8: Property-style tests where natural
When a function satisfies an obvious law (e.g. `map(id) == id`), write a test
that verifies it for a small concrete case. Pure property-based testing
(generative) is deferred — the test plan calls for concrete instances of
properties.

---

## 2. Current Coverage Assessment

| Module | Tests? | Functions with Tests | Notes |
|--------|--------|---------------------|-------|
| Bool   | ✅ Full | not\_, and\_, or\_, xor\_ | Truth-table complete |
| Result | ✅ Good | is_ok, is_err, unwrap_or, unwrap_or_else, map, map_err, and_then, or_else, flatten, filter, to_list, from_list | Missing: unwrap, unwrap_or_default, or, map_err, flatten Err outer case, to_list Err, or_else Ok |
| List   | ✅ Good | empty, singleton, length, is_empty, append, first, last, rest | Missing: sort, sort_by, to_iter, from_iter, append non-empty right, length large |
| Iter   | ❌ None | — | All functions intrinsic; zero tests |
| Map    | ❌ None | — | Some Camp code (fold, map, filter, union, etc.), all intrinsic construction |
| Set    | ❌ None | — | Same situation as Map |
| Str    | ❌ None | — | All intrinsic |
| Bytes  | ❌ None | — | All intrinsic |
| Eq     | ❌ None | — | Trait only, no functions to test |
| Ord    | ❌ None | — | Order tag union; trait only |
| Hash   | ❌ None | — | Trait + opaque Hasher |
| Debug  | ❌ None | — | Trait only |
| Display| ❌ None | — | No file yet |
| Default| ❌ None | — | Trait only |
| Fmt    | ❌ None | — | All intrinsic |
| From   | ❌ None | — | Trait only |
| TryFrom| ❌ None | — | Trait only |
| IntoIter| ❌ None | — | Trait only |
| FromIter| ❌ None | — | Trait only |
| Clone  | ❌ None | — | Trait only |
| Throw! | ❌ None | — | Effect operation only |
| Console!| ❌ None | — | Effect operations only |
| File!  | ❌ None | — | Effect operations only |
| Env!   | ❌ None | — | Effect operations only |
| Time!  | ❌ None | — | Effect operations only |
| Random!| ❌ None | — | Effect operations only |
| Log!   | ❌ None | — | Effect operations only |
| Duration| ❌ None | — | All intrinsic |
| Path   | ❌ None | — | All intrinsic (and uses Option — needs updating) |
| Json   | ❌ None | — | Mixed: is_int, is_float, as_i64, as_u64, as_f64 are pure Camp |
| Regex  | ❌ None | — | All intrinsic |
| Uri    | ❌ None | — | All intrinsic |
| Uuid   | ❌ None | — | All intrinsic |
| Base64 | ❌ None | — | All intrinsic (TODO: pure Camp impl planned) |
| Num/{I64,U64,...} | ❌ None | — | abs, clamp, max, min, neg are pure Camp; rest intrinsic |

**Summary:** 32 modules total. 3 have tests (Bool, Result, List). **29 have zero
tests.** Coverage gap is severe — the entire effect system, collections (Map,
Set, Iter), strings, I/O, and standard library modules are untested.

---

## 3. Priority 1 Modules — Tests

### 3.1 Bool

**Current state:** Complete truth-table coverage for all 4 operations. 12 tests total (3 per function).

**Gaps:** None. Bool is the model for what complete coverage looks like.

**Maintain:** Current tests as-is. No additions needed.

### 3.2 Result

**Current state:** 18 tests. Strong coverage of core combinators. Missing some
edge cases and untested functions.

**Existing tests:**
- is_ok: Ok ✓, Err ✓
- is_err: Ok ✓, Err ✓
- unwrap_or: Ok ✓, Err ✓
- unwrap_or_else: Ok ✓, Err ✓
- map: Ok ✓, Err ✓
- map_err: Ok ✓, Err ✓
- and_then: Ok ✓, Err ✓
- or_else: Err ✓, Ok ✓
- flatten: nested Ok ✓, nested Err ✓
- filter: ok passes ✓, ok fails ✓, err ✓
- to_list: Ok ✓, Err ✓
- from_list: non-empty ✓

**Missing tests:**

| Test | Scenario | Rationale |
|------|----------|-----------|
| unwrap Ok | `unwrap(Ok(42)) == 42` | Should never reach crash path |
| unwrap Err | `unwrap(Err("x"))` crashes | Verify crash on Err — may need `crash` test harness |
| unwrap_or_default Ok | `unwrap_or_default(Ok(42))` with no Default | Type constraint test |
| unwrap_or_default Err | `unwrap_or_default(Err("x"))` where a has Default | |
| or: Ok first | `or(Ok(1), Ok(2))` yields Ok(1) | Short-circuit on first Ok |
| or: Err then Ok | `or(Err("e"), Ok(2))` yields Ok(2) | Falls through to second |
| or: Err then Err | `or(Err("a"), Err("b"))` yields Err("b") | Both fail |
| flatten Err outer | `flatten(Err("outer"))` yields Err("outer") | Outer Err passthrough |
| map_err preserves Ok | `map_err(Ok(42), \|e\| e)` yields Ok(42) | Ok untouched |
| from_list empty | `from_list([])` yields Err(EmptyList) | Edge: empty list |
| and_then Ok -> Err | `and_then(Ok(42), \|x\| Err("x"))` yields Err("x") | Chain breaks |
| or_else catches specific | `or_else(Err(ListWasEmpty), \|\| Ok(0))` yields Ok(0) | Error-specific recovery |
| filter err preserves | `filter(Err("base"), \|x\| True, "err")` yields Err("base") | Err unchanged |

**Potential additional tests (if supported by test framework):**
- `unwrap!` on Ok: produces value without raising
- `unwrap!` on Err: raises Throw!(e)
- `catch` on pure value: returns Ok(value)
- `catch` on thrown value: returns Err(e)

### 3.3 List

**Current state:** 14 tests covering basic operations. Missing: sort, to_iter,
from_iter, larger-scale append.

**Existing tests:**
- empty is Nil ✓
- singleton ✓
- length: empty ✓, singleton ✓, multiple ✓
- is_empty: empty ✓, non-empty ✓
- append: two lists ✓, empty left ✓, both empty ✓
- first: non-empty ✓, empty ✓
- last: single ✓, multiple ✓, empty ✓
- rest: non-empty ✓, empty ✓

**Missing tests:**

| Test | Scenario | Rationale |
|------|----------|-----------|
| length: large | length of longer list | Scale beyond 2 elements |
| append: non-empty right only | `append(Cons(1,Nil), empty)` == `[1]` | Symmetry of append/empty |
| append: three lists | `append(a, append(b, c))` == `append(append(a, b), c)` | Associativity (single instance) |
| singleton: type inference | `singleton("hello")` | Str variant |
| first: multi-element | `first([1,2,3]) == Ok(1)` | Head access on 3-element |
| last: multi-element | `last([1,2,3]) == Ok(3)` | Tail access on 3-element |
| rest: single element | `rest([42]) == Ok(Nil)` | Tail becomes empty |
| sort: already sorted | `sort([1,2,3]) == [1,2,3]` | Identity on sorted |
| sort: reversed | `sort([3,2,1]) == [1,2,3]` | Full reversal |
| sort: with duplicates | `sort([3,1,3,2]) == [1,2,3,3]` | Stability unspecified |
| sort: empty | `sort([]) == []` | Empty edge |
| sort: singleton | `sort([42]) == [42]` | Singleton edge |
| sort_by: custom comparator | `sort_by(["aa","b"], \|a,b\| ...)` | Ord parameter |
| to_iter -> from_iter roundtrip | `from_iter(to_iter([1,2,3])) == [1,2,3]` | Identity through Iter |
| from_iter: empty | `from_iter(Iter.empty) == []` | Empty edge |

### 3.4 Iter

**Current state:** Zero tests. All functions intrinsic (`crash "intrinsic"`).
Once runtime iterators land, every function needs tests.

**Planned tests (ordered by implementation priority):**

**Construction:**
| Test | Scenario |
|------|----------|
| empty: produces Done on first next | (requires unpacking the Iter struct — may use fold) |
| singleton: yields one element then Done | (via fold or for_each) |
| from_list: yields all elements in order | |

**Core transformations:**
| Test | Scenario |
|------|----------|
| map: identity function | `map(iter, \|x\| x)` produces same elements |
| map: increment | `map(iter, \|x\| x + 1)` on [1,2,3] yields [2,3,4] |
| map: empty | map over empty yields empty |
| filter: keep all | `filter(iter, \|x\| True)` yields same elements |
| filter: drop all | `filter(iter, \|x\| False)` yields empty |
| filter: keep even | `filter([1..5], \|x\| x % 2 == 0)` yields [2,4] |
| filter_map: Ok only | `filter_map(iter, \|x\| Ok(x))` yields all |
| filter_map: skip All | `filter_map(iter, \|x\| Err(()))` yields empty |
| flat_map: identity | `flat_map(iter, singleton)` yields same |
| flat_map: expand each | `flat_map([1,2], \|x\| [x, x])` yields [1,1,2,2] |

**Consumption:**
| Test | Scenario |
|------|----------|
| fold: sum | `fold([1,2,3], 0, add)` == 6 |
| fold: string concat | `fold(["a","b"], "", concat)` == "ab" |
| fold: empty returns init | `fold(empty, 42, \|acc,x\| acc)` == 42 |
| for_each: collects effects | (side-effect tracking; may need harness) |
| count: non-empty | `count([1,2,3])` == 3 |
| count: empty | `count(empty)` == 0 |
| count: singleton | `count([42])` == 1 |

**Search:**
| Test | Scenario |
|------|----------|
| find: present | `find([1,2,3], \|x\| x == 2)` == Ok(2) |
| find: absent | `find([1,2,3], \|x\| x == 5)` == Err(NotFound) |
| find: first match only | `find([1,2,2], \|x\| x == 2)` == Ok(2) — first not second |
| find: empty | `find(empty, \|x\| True)` == Err(NotFound) |
| any: true case | `any([1,2,3], \|x\| x > 2)` == True |
| any: false case | `any([1,2,3], \|x\| x > 5)` == False |
| any: empty | `any(empty, \|x\| True)` == False |
| all: all pass | `all([1,2,3], \|x\| x > 0)` == True |
| all: one fails | `all([1,0,3], \|x\| x > 0)` == False |
| all: empty | `all(empty, \|x\| True)` == True (vacuous truth) |
| contains: present | `contains([1,2,3], 2)` == True |
| contains: absent | `contains([1,2,3], 5)` == False |
| contains: empty | `contains(empty, 42)` == False |

**Slicing:**
| Test | Scenario |
|------|----------|
| take: n of m (n < m) | `take([1,2,3], 2)` via fold yields [1,2] |
| take: n > length | `take([1,2], 5)` yields all elements (stops at Done) |
| take: zero | `take([1,2,3], 0)` yields empty |
| take: negative | `take([1,2,3], -1)` yields empty (or all? — define behavior) |
| skip: n of m | `skip([1,2,3], 2)` yields [3] |
| skip: all | `skip([1,2,3], 5)` yields empty |
| skip: zero | `skip([1,2,3], 0)` yields all |
| take_while: predicate holds | `take_while([1,2,3,4], \|x\| x < 3)` yields [1,2] |
| take_while: fails first | `take_while([1,2], \|x\| False)` yields empty |
| skip_while: predicate holds | `skip_while([1,2,3,4], \|x\| x < 3)` yields [3,4] |
| skip_while: never holds | `skip_while([1,2], \|x\| False)` yields all |

**Composition:**
| Test | Scenario |
|------|----------|
| chain: disjoint | `chain([1,2], [3,4])` yields [1,2,3,4] |
| chain: empty left | `chain(empty, [1,2])` yields [1,2] |
| chain: empty right | `chain([1,2], empty)` yields [1,2] |
| chain: both empty | `chain(empty, empty)` yields empty |
| zip: equal lengths | `zip([1,2,3], ["a","b","c"])` yields [(1,"a"),(2,"b"),(3,"c")] |
| zip: first longer | `zip([1,2,3], ["a","b"])` yields [(1,"a"),(2,"b")] (truncates) |
| zip: second longer | `zip([1,2], ["a","b","c"])` yields [(1,"a"),(2,"b")] (truncates) |
| zip: empty left | `zip(empty, [1,2])` yields empty |
| enumerate: three elements | `enumerate(["a","b","c"])` yields [(0,"a"),(1,"b"),(2,"c")] |
| enumerate: empty | `enumerate(empty)` yields empty |

**Iter edge cases:**
| Test | Scenario |
|------|----------|
| map then filter pipeline | `[1..10] -> map(\|x\| x*2) -> filter(\|x\| x > 10)` yields [12,14,16,18,20] |
| zip with chain | `zip([1,2], chain([3],[4]))` — composition of composition ops |
| takes before filter | Order independence of skip/take and filter |
| flat_map of empty | `flat_map(empty, \|x\| [x, x])` yields empty |

### 3.5 Map

**Current state:** Zero tests. Map has partial Camp implementation for fold,
map, filter, union, intersection, difference, to_iter, keys, values, to_list.

**Implementation note:** Map relies on intrinsic operations (new, singleton,
insert, get, contains, remove, min, max, from_list). The Camp-level functions
(fold, map, filter, union, etc.) compose these intrinsics. Tests must verify
the composition logic, not the intrinsic host behavior.

**Planned tests:**

**Construction:**
| Test | Scenario |
|------|----------|
| new: empty | `is_empty(new)` == True |
| new: size 0 | `size(new)` == 0 |
| singleton: size 1 | `size(singleton("k", 1))` == 1 |
| singleton: contains | `contains("k", singleton("k", 1))` == True |
| singleton: get | `get("k", singleton("k", 1))` == Ok(1) |
| from_list: three entries | `from_list([("a",1),("b",2),("c",3)])` size == 3 |
| from_list: duplicates (last wins) | `from_list([("a",1),("a",2)])` get("a") == Ok(2) |

**Lookup:**
| Test | Scenario |
|------|----------|
| get: present | `get("k", insert("k", 1, new))` == Ok(1) |
| get: absent | `get("missing", singleton("k", 1))` == Err(KeyNotFound) |
| get: empty | `get("k", new)` == Err(KeyNotFound) |
| contains: present | `contains("k", singleton("k", 1))` == True |
| contains: absent | `contains("x", singleton("k", 1))` == False |
| contains: empty | `contains("k", new)` == False |
| size: one insert | after one insert into empty, size == 1 |
| size: one insert then remove | after insert then remove, size == 0 |

**Modification:**
| Test | Scenario |
|------|----------|
| insert: new key | after insert, contains + get return the value |
| insert: overwrite | insert same key twice, get returns second value |
| insert: size increases on new key | size == 1 after first insert |
| insert: size stable on overwrite | size == 1 after two inserts same key |
| remove: existing key | contains returns False after remove |
| remove: non-existing key | remove no-op on absent key |
| remove: empty | remove on new is no-op (size stays 0) |
| update: modify existing | `update("k", \|r\| match r { Ok(v) => Ok(v+1) \| Err(e) => Err(e) }, map)` increments |
| update: insert new | `update("k", \|r\| match r { Err(KeyNotFound) => Ok(1) \| ... }, new)` inserts |
| update: remove if exists | `update("k", \|r\| r->map_err(\|_\|) ...` — no, update uses Ok=keep/Err(KeyNotFound)=remove |
| update: remove existing | `update("k", \|_\| Err(KeyNotFound), singleton("k",1))` -> empty |

**Transformation:**
| Test | Scenario |
|------|----------|
| fold: sum values | `fold(m, 0, \|acc,_,v\| acc+v)` == sum |
| fold: count keys | `fold(m, 0, \|acc,_,_\| acc+1)` == size |
| fold: empty returns init | `fold(new, 42, \|acc,_,_\| acc)` == 42 |
| map: increment values | `map(m, \|v\| v+1)` doubles all values |
| map: identity | `map(m, \|v\| v)` == m (same key/value pairs) |
| map: empty | `map(new, \|v\| v+1)` == new |
| filter: keep all | `filter(m, \|_,_\| True)` == m |
| filter: drop all | `filter(m, \|_,_\| False)` == new |
| filter: keep only evens | `filter(from_list([("a",1),("b",2)]), \|_,v\| v % 2 == 0)` has only ("b",2) |

**Set-like operations:**
| Test | Scenario |
|------|----------|
| union: disjoint | `union(("a",1), ("b",2))` size == 2 |
| union: overlapping (left bias) | `union(("a",1), ("a",2))` get("a") == Ok(1) |
| union: empty left | `union(new, singleton("a",1))` == singleton("a",1) |
| union: empty right | `union(singleton("a",1), new)` == singleton("a",1) |
| intersection: overlapping | `intersection(("a",1,"b",2), ("b",3,"c",4))` has only "b" |
| intersection: disjoint | `intersection(("a",1), ("b",2))` size == 0 |
| difference: remove one | `difference(("a",1,"b",2), ("a",1))` has only "b" |
| difference: empty | `difference(m, new)` == m |
| difference: full | `difference(m, m)` == new |

**Conversion:**
| Test | Scenario |
|------|----------|
| to_list -> from_list roundtrip | converting identity through list |
| keys: iteration | `keys(m)` via fold contains all keys |
| values: iteration | `values(m)` via fold contains all values |
| to_iter roundtrip | `from_list -> to_iter -> fold` same as fold on map |

### 3.6 Set

**Current state:** Zero tests. Set mirrors Map pattern — intrinsic new,
singleton, contains, size, insert, remove, min, max, from_list; Camp-level
fold, map, filter, to_iter, union, intersection, difference,
symmetric_difference, is_subset, is_disjoint.

**Planned tests:**

**Construction:**
| Test | Scenario |
|------|----------|
| new: empty | `is_empty(new)` == True |
| new: size 0 | `size(new)` == 0 |
| singleton: size 1 | `size(singleton(42))` == 1 |
| singleton: contains | `contains(42, singleton(42))` == True |
| from_list: dedup | `from_list([1,1,2])` size == 2 |
| from_list: all unique | `from_list([1,2,3])` size == 3 |

**Queries:**
| Test | Scenario |
|------|----------|
| contains: present | `contains(42, insert(42, new))` == True |
| contains: absent | `contains(99, singleton(42))` == False |
| contains: empty | `contains(42, new)` == False |
| size: insert unique | size increments on insert of new element |
| size: insert duplicate | size stable on insert of existing element |
| is_empty: non-empty | `is_empty(singleton(42))` == False |
| min: non-empty | `min(from_list([3,1,2]))` == Ok(1) |
| min: empty | `min(new)` == Err(EmptySet) |
| max: non-empty | `max(from_list([1,5,3]))` == Ok(5) |
| max: empty | `max(new)` == Err(EmptySet) |

**Modification:**
| Test | Scenario |
|------|----------|
| insert: new element | contains == True after insert |
| insert: existing element | no-op |
| remove: present | contains == False after remove |
| remove: absent | no-op |
| remove: empty | no-op |

**Set operations:**
| Test | Scenario |
|------|----------|
| union: disjoint | `size(union(from_list([1,2]), from_list([3,4])))` == 4 |
| union: overlapping | `size(union(from_list([1,2]), from_list([2,3])))` == 3 |
| intersection: overlapping | `intersection([1,2,3], [2,3,4])` == from_list([2,3]) |
| intersection: disjoint | `size(intersection([1,2], [3,4]))` == 0 |
| difference: partial | `difference([1,2,3], [2])` == from_list([1,3]) |
| difference: full | `size(difference([1,2], [1,2]))` == 0 |
| symmetric_difference | `symmetric_difference([1,2], [2,3])` == from_list([1,3]) |
| symmetric_difference: disjoint | `size(symmetric_difference([1], [2]))` == 2 |
| is_subset: true | `is_subset(from_list([1,2]), from_list([1,2,3]))` == True |
| is_subset: false | `is_subset(from_list([1,2,3]), from_list([1,2]))` == False |
| is_subset: equal sets | `is_subset(from_list([1,2]), from_list([1,2]))` == True |
| is_subset: empty | `is_subset(new, from_list([1,2]))` == True |
| is_disjoint: true | `is_disjoint(from_list([1,2]), from_list([3,4]))` == True |
| is_disjoint: false | `is_disjoint(from_list([1,2]), from_list([2,3]))` == False |

**Transformation:**
| Test | Scenario |
|------|----------|
| fold: sum | sum over set matches sum over equivalent list |
| fold: empty | fold returns init |
| map: increment | `map(from_list([1,2,3]), \|x\| x + 1)` key semantics |
| map: to strings | `map(from_list([1,2]), \|x\| to_str(x))` |
| filter: keep even | `filter([1..5], \|x\| x % 2 == 0)` == from_list([2,4]) |
| filter: empty result | `filter([1,3,5], \|x\| x % 2 == 0)` == new |

**Conversion:**
| Test | Scenario |
|------|----------|
| to_list -> from_list roundtrip | round-trip identity |
| from_list -> to_iter -> fold | via Iter identity |
| from_list dedup | duplicate in input dedup'd in output |

### 3.7 Str

**Current state:** Zero tests. All functions intrinsic (delegated to host
runtime).

**Testing challenge:** Str intrinsics depend on the WASM runtime's UTF-8
implementation. Tests for intrinsics verify the Camp-level contract, not the
implementation. They are meaningful once intrinsics work.

**Planned tests (all intrinsic — contract tests):**

**Queries:**
| Test | Scenario |
|------|----------|
| length: ASCII | `length("hello")` == 5 |
| length: empty | `length("")` == 0 |
| length: multi-byte | `length("café")` == 4 (grapheme-wise) |
| length: emoji | `length("👍")` == 1 (or code-point count — depends on impl) |
| byte_size: ASCII | `byte_size("hello")` == 5 |
| byte_size: multi-byte | `byte_size("café")` == 5 (4 + 1 for é = 2 bytes... actually it's 5) |
| is_empty: true | `is_empty("")` == True |
| is_empty: false | `is_empty("a")` == False |
| starts_with: prefix present | `starts_with("hello", "he")` == True |
| starts_with: prefix absent | `starts_with("hello", "hi")` == False |
| starts_with: empty prefix | `starts_with("hello", "")` == True |
| ends_with: suffix present | `ends_with("hello", "lo")` == True |
| ends_with: suffix absent | `ends_with("hello", "no")` == False |
| contains: substring present | `contains("hello world", "world")` == True |
| contains: absent | `contains("hello", "xyz")` == False |
| contains: empty needle | `contains("hello", "")` == True |

**Slicing:**
| Test | Scenario |
|------|----------|
| take: n chars from start | `take("hello", 2)` == "he" |
| take: n == length | `take("hi", 2)` == "hi" |
| take: n > length | `take("hi", 5)` == "hi" (clamp) |
| take: zero | `take("hello", 0)` == "" |
| drop: n chars from start | `drop("hello", 2)` == "llo" |
| drop: n == length | `drop("hi", 2)` == "" |
| drop: n > length | `drop("hi", 5)` == "" (clamp) |
| drop: zero | `drop("hello", 0)` == "hello" |
| slice: valid range | `slice("hello", 1, 3)` == "ell" |
| slice: full string | `slice("hello", 0, 5)` == "hello" |
| slice: zero length | `slice("hello", 2, 0)` == "" |

**Splitting:**
| Test | Scenario |
|------|----------|
| split: basic | `split("a,b,c", ",")` == ["a","b","c"] |
| split: no separator | `split("hello", ",")` == ["hello"] |
| split: empty | `split("", ",")` == [""] |
| split_first: present | `split_first("a,b", ",")` == Ok(("a","b")) |
| split_first: absent | `split_first("hello", ",")` == Err(NotFound) |
| split_first: at start | `split_first(",hello", ",")` semantics — empty prefix? |
| split_last: present | `split_last("a,b", ",")` == Ok(("a","b")) |
| split_last: absent | `split_last("hello", ",")` == Err(NotFound) |

**Trimming:**
| Test | Scenario |
|------|----------|
| trim: both sides | `trim("  hi  ")` == "hi" |
| trim: nothing to trim | `trim("hi")` == "hi" |
| trim: empty | `trim("")` == "" |
| trim_start | `trim_start("  hi")` == "hi" |
| trim_end | `trim_end("hi  ")` == "hi" |

**Case:**
| Test | Scenario |
|------|----------|
| to_lower: already lower | `to_lower("hello")` == "hello" |
| to_lower: mixed | `to_lower("Hello World")` == "hello world" |
| to_upper: already upper | `to_upper("HELLO")` == "HELLO" |
| to_upper: mixed | `to_upper("Hello")` == "HELLO" |

**Concatenation:**
| Test | Scenario |
|------|----------|
| concat: two strings | `concat("hello", " world")` == "hello world" |
| concat: empty left | `concat("", "hi")` == "hi" |
| concat: both empty | `concat("", "")` == "" |
| join: three parts | `join(["a","b","c"], ",")` == "a,b,c" |
| join: single | `join(["hello"], ",")` == "hello" |
| join: empty list | `join([], ",")` == "" |
| repeat: three times | `repeat("ha", 3)` == "hahaha" |
| repeat: zero | `repeat("ha", 0)` == "" |

**Replacement:**
| Test | Scenario |
|------|----------|
| replace: single occurrence | `replace("hello", "l", "x")` — multiple vs first? |
| replace: no match | `replace("hello", "z", "x")` == "hello" |
| replace_first: one | `replace_first("hello", "l", "x")` == "hexlo" |
| drop_prefix: present | `drop_prefix("hello", "he")` == "llo" |
| drop_prefix: absent | `drop_prefix("hello", "xy")` == "hello" |
| drop_suffix: present | `drop_suffix("hello", "lo")` == "he" |
| drop_suffix: absent | `drop_suffix("hello", "xy")` == "hello" |

**Conversion:**
| Test | Scenario |
|------|----------|
| to_bytes: ASCII | to_bytes roundtrip |
| from_bytes: valid UTF-8 | `from_bytes(to_bytes("hello"))` == Ok("hello") |
| from_bytes: invalid | `from_bytes([0xFF, 0xFE, 0x00])` == Err(InvalidUtf8) |
| from_bytes_lossy: invalid input | replaces with U+FFFD |

**Parsing:**
| Test | Scenario |
|------|----------|
| to_i64: valid | `to_i64("42")` == Ok(42) |
| to_i64: negative | `to_i64("-1")` == Ok(-1) |
| to_i64: invalid | `to_i64("abc")` == Err(InvalidFormat) |
| to_i64: overflow | `to_i64("99999999999999999999")` == Err(InvalidFormat) |
| to_f64: valid | `to_f64("3.14")` == Ok(3.14) |
| to_f64: invalid | `to_f64("abc")` == Err(InvalidFormat) |

**Iteration:**
| Test | Scenario |
|------|----------|
| to_iter: graphemes | iterating over "abc" yields ["a","b","c"] |
| to_iter: empty | yields empty iter |
| to_iter: multi-byte | `"café" to_iter -> count` == 4 |

### 3.8 Bytes

**Current state:** Zero tests. All intrinsic.

**Planned tests:**

| Test | Scenario |
|------|----------|
| new: empty, length 0 | `length(new)` == 0 |
| new: is_empty | `is_empty(new)` == True |
| singleton: length 1 | `length(singleton(0xFF))` == 1 |
| singleton: get | `get(0, singleton(0x42))` == 0x42 |
| from_list: three bytes | `length(from_list([0x00, 0x01, 0x02]))` == 3 |
| get: valid index | value matches inserted byte |
| get: out of bounds | (runtime error — not expressible in return type) |
| take: n bytes | `take(bytes, 2)` has length 2 |
| take: all | `take(bytes, len)` == bytes |
| drop: n bytes | `drop(bytes, 2)` drops first 2 |
| slice: middle | `slice(bytes, 1, 2)` extracts the middle two |
| concat: two byte buffers | length of concat = sum of lengths |
| concat: empty left | `concat(new, bytes)` == bytes |
| to_iter: yields all bytes in order | (via fold/count) |
| to_list: roundtrip | `to_list(from_list([1,2,3]))` == [1,2,3] |
| to_str: valid UTF-8 | `to_str(from_list([0x48,0x69]))` == Ok("Hi") |
| to_str: invalid UTF-8 | `to_str(from_list([0xFF]))` == Err(InvalidUtf8) |

### 3.9 Num Submodules

**Current state:** Zero tests. I64 has pure Camp implementations for abs,
clamp, max, min, neg. All other operations are intrinsic.

**I64 (model for all integer types):**

*Pure Camp functions:*
| Test | Scenario |
|------|----------|
| abs: positive | `abs(42)` == 42 |
| abs: negative | `abs(-42)` == 42 |
| abs: zero | `abs(0)` == 0 |
| clamp: within range | `clamp(0, 100, 50)` == 50 |
| clamp: below min | `clamp(0, 100, -10)` == 0 |
| clamp: above max | `clamp(0, 100, 200)` == 100 |
| clamp: equal to min | `clamp(5, 10, 5)` == 5 |
| max: a > b | `max(10, 5)` == 10 |
| max: a < b | `max(5, 10)` == 10 |
| max: equal | `max(7, 7)` == 7 |
| min: a < b | `min(5, 10)` == 5 |
| min: a > b | `min(10, 5)` == 5 |
| min: equal | `min(7, 7)` == 7 |
| neg: positive | `neg(42)` == -42 |
| neg: negative | `neg(-10)` == 10 |
| neg: zero | `neg(0)` == 0 |

*Intrinsic functions (contract tests):*
| Test | Scenario |
|------|----------|
| checked_add: normal | `checked_add(2, 2)` == 4 |
| checked_add: overflow | (silent wrapping, panic, or error — depends on design) |
| wrapping_add: wraps | wrapping semantics verified |
| saturating_add: saturates | `saturating_add(I64.max, 1)` == I64.max |
| count_ones: value | `count_ones(0b1011)` == 3 |
| count_zeros | complement of count_ones |
| leading_zeros: power of 2 | single leading zero pattern |
| range: [0, 10) | yields [0,1,...,9] |
| range: empty (start == end) | yields empty iter |
| range: reversed | yields empty or different behavior? |

**F64:**
| Test | Scenario |
|------|----------|
| abs: positive | `abs(3.14)` == 3.14 |
| abs: negative | `abs(-3.14)` == 3.14 |
| abs: zero | `abs(0.0)` == 0.0 |
| abs: NaN | preserves NaN (abs(-NaN) == NaN in IEEE 754) |
| ceil/floor/round | standard numeric rounding |
| sqrt: positive | `sqrt(4.0)` == 2.0 |
| sqrt: zero | `sqrt(0.0)` == 0.0 |
| sqrt: negative | NaN (IEEE 754 behavior) |
| pow: integer | `pow(2.0, 3.0)` == 8.0 |

**F32:**
Same pattern as F64 with F32 values. At minimum: abs, ceil, floor, round, sqrt
for a representative subset of the F64 tests.

**U64, U32, U16, U8:**
Same operations as I64 minus sign-related ones (abs, neg). Key addition:
checked overflow on max value.

| Test | Scenario |
|------|----------|
| wrapping_add: max + 1 | `wrapping_add(U8.max, 1)` == 0 |
| from_str / to_str | round-trip |

### 3.10 Eq / Ord / Order

**Current state:** Eq and Ord are trait declarations only (no functions to
test). Order is a structural tag union `[Less | Equal | Greater]`.

**Planned tests:**

**Order type:**
| Test | Scenario |
|------|----------|
| Order: Less < Equal < Greater | Pattern matching distinguishes all three |
| Order: structural equality | `Less` == `Less`, `Equal` /= `Greater` |

**Trait implementations (in Camp code, not in stdlib):**
These live with the implementing module, not in Eq.camp or Ord.camp. For
example, `Num.I64 is Eq` and `Num.I64 is Ord` tests go in Num/I64.camp. The
stdlib trait files themselves are pure declarations.

But we should test **intrinsic derive behavior** once derives work:
| Test | Scenario |
|------|----------|
| Eq: nominal with derives | `@Color is Eq derives Eq: [Red \| Green]` — `Red.eq(Red)` == True |
| Ord: nominal with derives | `order(Red, Green)` == Less |

### 3.11 Hash / Hasher

**Current state:** Hash trait and opaque Hasher type. No functions to test
directly in pure Camp.

**Planned tests (once Hash derives work):**
| Test | Scenario |
|------|----------|
| Hash: same value -> same hash | `hash(val, Hasher.new)` == `hash(val, Hasher.new)` (determinism) |
| Hash: different values -> different hash likely | Not guaranteed but expected |
| Hash: nominal with derives | `@Uid is Hash derives Hash: U64` — derived hash works |

### 3.12 Debug / Display / Default / Fmt

**Current state:** Trait declarations (Debug, Display, Default). Fmt has
intrinsic functions.

**Display trait:**
Test implementations live with the implementing modules. Key types that SHOULD
implement Display:
| Type | Test |
|------|------|
| I64 | `to_str(42)` == "42" |
| F64 | `to_str(3.14)` == "3.14" |
| Bool | `to_str(True)` == "True" |
| Str | `to_str("hello")` == "hello" |
| List(a) | `to_str([1,2,3])` — format TBD |

**Debug trait:**
Same pattern as Display. Debug should produce more detailed output.

**Default trait:**
| Type | Test | Expectation |
|------|------|-------------|
| I64 | `default()` | 0 |
| F64 | `default()` | 0.0 |
| Bool | `default()` | False |
| Str | `default()` | "" |
| Bytes | `default()` | empty bytes |
| List(a) | `default()` | Nil |

**Fmt module:**
| Test | Scenario |
|------|----------|
| f64_with_precision: round | `f64_with_precision(3.14159, 2)` == "3.14" |
| f64_with_precision: zero precision | `f64_with_precision(3.14, 0)` == "3" |
| pad_left: under width | `pad_left("hi", 4, " ")` == "  hi" |
| pad_right: under width | `pad_right("hi", 4, " ")` == "hi  " |
| pad_left: at width | `pad_left("hello", 5, " ")` == "hello" |
| pad_right: over width | No truncation — returns original |

### 3.13 From / TryFrom

**Current state:** Trait declarations. Test implementations live with the
implementing modules.

**Planned From impl tests:**
| Conversion | Test |
|------------|------|
| Str -> Bytes | `from("hello")` == `Bytes.from_str("hello")` |
| I64 -> F64 | `from(42 : I64)` == 42.0 |
| U8 -> I64 | infallible widening |

**Planned TryFrom impl tests:**
| Conversion | Test |
|------------|------|
| Bytes -> Str (valid) | `try_from(bytes("hello"))` == Ok("hello") |
| Bytes -> Str (invalid) | `try_from([0xFF])` == Err(InvalidUtf8) |
| I64 -> U8 (in range) | `try_from(42)` == Ok(42) |
| I64 -> U8 (out of range) | `try_from(256)` == Err(...) |
| F64 -> I64 (in range) | `try_from(3.0)` == Ok(3) |
| F64 -> I64 (NaN) | `try_from(NaN)` == Err(...) |

### 3.14 IntoIter / FromIter

**Current state:** Trait declarations.

**Planned IntoIter impl tests:**
| Collection | Test |
|------------|------|
| List(a) -> Iter(a) | `to_iter([1,2,3])` via fold yields sum 6 |
| Map(k, v) -> Iter((k, v)) | `to_iter(singleton("a",1))` yields one pair |
| Set(a) -> Iter(a) | `to_iter(from_list([1,2,3]))` via fold yields sum 6 |
| Str -> Iter(Str) | `to_iter("abc")` yields ["a","b","c"] |
| Bytes -> Iter(U8) | `to_iter(singleton(0x42))` yields [0x42] |

**Planned FromIter impl tests:**
| Collection | Test |
|------------|------|
| Iter(a) -> List(a) | `from_iter(Iter.from_list([1,2,3]))` == [1,2,3] |
| Iter(a) -> Set(a) | `from_iter([1,1,2])` size == 2 (dedup) |
| Iter((k, v)) -> Map(k, v) | `from_iter([("a",1),("b",2)])` size == 2 |
| Iter(U8) -> Bytes | `from_iter([0x41, 0x42])` length == 2 |

---

## 4. Priority 1 Effect Modules

Effect module tests require an effect handler to provide a controlled testing
environment. Pure Camp cannot test effects directly — the test must run within
a `handle ... in ... with { ... }` block that provides a mock handler.

### 4.1 Console!

**Operations:** print!, println!, readln!

**Mock handler strategy:**
```
handle Console! in {
  -- test body that calls Console.println!("hello")
} with {
  .println!(resume, msg) => { called = true; resume({}) }
  .print!(resume, msg) => { called = true; resume({}) }
  .readln!(resume) => { resume("test input") }
}
```

**Planned tests:**
| Test | Scenario |
|------|----------|
| println!: invokes handler | Mock handler receives the message |
| print!: invokes handler | Mock handler receives the message |
| readln!: returns mock input | Handler provides "test input", operation returns it |
| println!: empty message | Handler receives "" |
| println!: Unicode message | Handler receives "café 👍" |

### 4.2 Throw!

**Operations:** raise!

**Behavior:** `Throw.raise!(e)` never returns — it has bottom type. Testing
this means catching it in a handler.

**Planned tests:**
| Test | Scenario |
|------|----------|
| raise!: caught in handler | `handle Throw! in { ... raise!(NotFound) } with { .raise!(_, err) => ... }` |
| raise!: handler can resume? | Single-shot semantics — resuming from raise! should return a value |
| raise!: value propagates through handler | Handler pattern-matches the error tag |

### 4.3 Result Bridge Functions

**unwrap! : Result(a, e) -> -[Throw!(e)]-> a**

| Test | Scenario |
|------|----------|
| unwrap!: Ok returns value | `handle Throw! in { unwrap!(Ok(42)) } with { ... }` == 42 |
| unwrap!: Err raises | `handle Throw! in { unwrap!(Err("e")) } with { .raise!(_, e) => matched }` == matched |
| unwrap!: raises the specific error | The error variant from Err is what gets raised |

**catch : (|| -[Throw!(e)]-> a) -> Result(a, e)**

| Test | Scenario |
|------|----------|
| catch: pure body returns Ok | `catch(\|\| 42)` == Ok(42) |
| catch: thrown body returns Err | `catch(\|\| { handle Throw! ... })` catches the raised error |
| catch: multiple raises | Only first raise is caught (single-shot) |

### 4.4 File!

**Operations:** 13 operations. Testing requires an in-memory mock filesystem in
the handler.

**Mock handler strategy:**
An in-memory Map(Path, { content: Bytes, is_dir: Bool }) in the handler state.

**Planned tests:**
| Test | Scenario |
|------|----------|
| read_all!: reads written content | write then read returns same content |
| write_all!: overwrites | second write replaces first |
| exists!: returns True for created | after write, exists! == True |
| exists!: returns False for absent | before write, exists! == False |
| is_dir!/is_file! | differentiate files from directories |
| list_dir!: root directory | after creating files, list returns them |
| create_dir!: creates directory | after create_dir!, is_dir! == True |
| remove!: removes file | after remove, exists! == False |
| copy!: copies content | copy then read from destination returns source content |
| not_found on missing file | `read_all!(Path.new("/missing"))` raises NotFound |
| permission errors | mock can simulate |

### 4.5 Env!

**Operations:** get!, try_get, vars!, args!

**Mock handler strategy:**
An in-memory Map(Str, Str) for variables + List(Str) for args.

**Planned tests:**
| Test | Scenario |
|------|----------|
| get!: existing var | returns value from mock |
| get!: missing var | raises VarNotFound |
| try_get: existing | returns Ok(value) |
| try_get: missing | returns Err(VarNotFound) |
| vars!: returns all | mock has 3 entries, vars! returns them all |
| args!: returns CLI args | mock provides ["prog", "--flag"] |

### 4.6 Time!

**Operations:** now!, monotonic!

**Mock handler strategy:**
Return a configurable Duration from the handler.

**Planned tests:**
| Test | Scenario |
|------|----------|
| now!: returns Duration | result is a Duration (type-checking) |
| monotonic!: returns Duration | type-check |
| now! advances | second call returns later time if configured |

### 4.7 Random!

**Operations:** int!, float!, bytes!, bool!

**Mock handler strategy:**
Return deterministic values from the handler (seeded PRNG in handler state).

**Planned tests:**
| Test | Scenario |
|------|----------|
| int!: in range | result is between lo and hi (inclusive?) |
| int!: lo == hi | returns that value |
| float!: in range | result is between lo and hi |
| bool!: returns Bool | type-check |
| bytes!: requested length | returned Bytes has correct length |
| determinism with same seed | same seed produces same sequence |

### 4.8 Log!

**Operations:** debug!, info!, warn!, error!

**Mock handler strategy:**
Accumulate messages in a List(Str) in the handler.

**Planned tests:**
| Test | Scenario |
|------|----------|
| debug!: message passed | handler receives the message |
| info!: message passed | handler receives the message |
| warn!: message passed | handler receives the message |
| error!: message passed | handler receives the message |
| all levels distinguishable | handler can identify which level was called |

---

## 5. Priority 2 Modules — Tests

### 5.1 Duration

**Current state:** All intrinsic. Opaque type wrapping `{ secs: I64, nanos: I64 }`.

**Planned tests:**
| Test | Scenario |
|------|----------|
| from_seconds -> as_seconds roundtrip | `as_seconds(from_seconds(42))` == 42 |
| from_millis -> as_millis roundtrip | `as_millis(from_millis(1000))` == 1000 |
| from_micros -> as_micros roundtrip |  |
| from_nanos -> as_nanos roundtrip |  |
| add: two durations | `add(from_seconds(1), from_seconds(2))` == from_seconds(3) |
| add: with nanos overflow | `add(from_nanos(1), from_nanos(999999999))` == 1 second 0 nanos |
| add: negative | `add(from_seconds(1), from_seconds(-1))` == zero |
| add: zero identity | `add(d, zero)` == d |
| sub: two durations | `sub(from_seconds(5), from_seconds(3))` == from_seconds(2) |
| sub: negative result | `sub(from_seconds(1), from_seconds(5))` == from_seconds(-4) |
| mul: integer factor | `mul(from_seconds(3), 2)` == from_seconds(6) |
| mul: zero | `mul(from_seconds(5), 0)` == zero |
| mul: negative | `mul(from_seconds(2), -1)` == neg(from_seconds(2)) |
| neg: positive | `neg(from_seconds(3))` == from_seconds(-3) |
| neg: zero | `neg(zero)` == zero |
| abs: positive | `abs(from_seconds(3))` == from_seconds(3) |
| abs: negative | `abs(from_seconds(-3))` == from_seconds(3) |
| is_zero: true | `is_zero(zero)` == True |
| is_zero: false | `is_zero(from_seconds(1))` == False |
| constants exist | `second`, `millisecond`, `microsecond`, `nanosecond`, `zero` are valid Durations |
| Ord: ordering | Duration implements Ord, negative < zero < positive |
| Eq: equality | same duration values compare equal |
| as_seconds: rounding | fractional seconds behavior (truncate? rounding?) |
| from_seconds_f64 | `from_seconds(1.5)` == 1 second 500,000,000 nanos |

### 5.2 Path

**Current state:** All intrinsic. Opaque type, normalized on construction.

**Note:** Path currently returns `Option` in some signatures (parent, filename,
stem, extension). Per D1 (Option dropped), these should return `Result`.
Tests should follow the final API, not the interim one.

**Planned tests:**
| Test | Scenario |
|------|----------|
| new: absolute path | `is_absolute(Path.new("/usr/bin"))` == True |
| new: relative path | `is_relative(Path.new("foo/bar"))` == True |
| new: normalization | redundant separators removed |
| join: two relative | `to_str(join(Path.new("a"), Path.new("b")))` == "a/b" |
| join: absolute overrides | `to_str(join(Path.new("a"), Path.new("/abs")))` == "/abs" |
| from_list: parts | `to_str(from_list(["a","b","c"]))` == "a/b/c" |
| parent: has parent | `parent(Path.new("a/b"))` == Ok(Path.new("a")) |
| parent: root | `parent(Path.new("/"))` == Err(HasNoParent) |
| parent: relative single | `parent(Path.new("a"))` == Err(HasNoParent) |
| filename: has filename | `filename(Path.new("/a/b.txt"))` == Ok("b.txt") |
| stem: with extension | `stem(Path.new("hello.txt"))` == "hello" |
| stem: no extension | `stem(Path.new("hello"))` == "hello" |
| extension: has | `extension(Path.new("file.txt"))` == "txt" |
| extension: none | `extension(Path.new("file"))` == ""? |
| with_extension: replace | `to_str(with_extension(Path.new("f.md"), "txt"))` == "f.txt" |
| with_extension: no existing | `to_str(with_extension(Path.new("f"), "txt"))` == "f.txt" |
| to_str -> Path.new roundtrip | `to_str(Path.new(s))` == s (normalized) |
| to_iter: components | iterating Path.new("a/b/c") yields ["a","b","c"] |
| is_absolute: Unix root | `is_absolute(Path.new("/"))` == True |
| is_relative: current dir | `is_relative(Path.new("."))` == True |

### 5.3 Json

**Current state:** Mixed — pure Camp accessors (is_int, is_float, as_i64,
as_u64, as_f64) + intrinsic core (decode, encode, encode_pretty) + intrinsic
convenience (get, get_at, keys, values, length) + intrinsic streaming (parse_init,
parse_next, parse_all).

**Planned tests — pure Camp functions:**

| Test | Scenario |
|------|----------|
| is_int: PosInt | `is_int(PosInt(42))` == True |
| is_int: NegInt | `is_int(NegInt(-1))` == True |
| is_int: Float | `is_int(Float(3.14))` == False |
| is_float: Float | `is_float(Float(3.14))` == True |
| is_float: PosInt | `is_float(PosInt(42))` == False |
| as_i64: NegInt | `as_i64(NegInt(-42))` == Ok(-42) |
| as_i64: PosInt | `as_i64(PosInt(100))` == Err(Absent) |
| as_i64: Float | `as_i64(Float(3.14))` == Err(Absent) |
| as_u64: PosInt | `as_u64(PosInt(42))` == Ok(42) |
| as_u64: NegInt | `as_u64(NegInt(-1))` == Err(Absent) |
| as_f64: Float | `as_f64(Float(3.14))` == Ok(3.14) |
| as_f64: PosInt | `as_f64(PosInt(42))` == Err(Absent) (TODO: should be Ok) |

**Planned tests — intrinsic functions:**
| Test | Scenario |
|------|----------|
| decode: null | `decode("null")` == Ok(Null) |
| decode: bool true | `decode("true")` == Ok(Bool(True)) |
| decode: int | `decode("42")` == Ok(Num(PosInt(42))) |
| decode: string | `decode("\"hello\"")` == Ok(Str("hello")) |
| decode: array | `decode("[1,2,3]")` == Ok(Arr([Num(PosInt(1)),...])) |
| decode: object | `decode("{\"a\":1}")` == Ok(Obj(singleton("a", Num(PosInt(1))))) |
| decode: nested | deeply nested object/array |
| decode: invalid syntax | returns Err(JsonErr) |
| decode: empty | `decode("")` == Err |
| encode: null | `encode(Null)` == "null" |
| encode: bool | `encode(Bool(True))` == "true" |
| encode | encode then decode yields same value |
| encode_pretty | has newlines and indentation |
| streaming: parse basic | parse_init -> parse_next yields events |
| streaming: parse_all | matches decode output |

### 5.4 Regex

**Current state:** Almost all intrinsic. `escape` has TODO for pure Camp.

**Planned tests:**
| Test | Scenario |
|------|----------|
| compile: valid pattern | `compile("^hello")` == Ok(Regex) |
| compile: invalid pattern | `compile("[")` == Err(CompileError(...)) |
| is_match: matches | `is_match(compile("hello"), "hello world")` == True |
| is_match: no match | `is_match(compile("xyz"), "hello")` == False |
| is_match: empty pattern | `is_match(compile(""), "anything")` == True? |
| find: present | `find(compile("\\d+"), "abc123")` == Ok(Match) |
| find: absent | `find(compile("\\d+"), "abc")` == Err(Absent) |
| find_all: multiple matches | `find_all(compile("\\d"), "a1b2c3")` has 3 matches |
| replace: literal | `replace(compile("world"), "hello world", "there")` == "hello there" |
| replace_all: all occurrences | replaces all matches |
| split: on pattern | `split(compile("\\s+"), "a b  c")` == ["a","b","c"] |
| splitn: limit | `splitn(compile("\\s+"), "a b c d", 2)` == ["a","b c d"] |
| escape: metacharacters | `escape(".")` == "\\." |
| escape: normal text | `escape("hello")` == "hello" |

### 5.5 Uri

**Current state:** All intrinsic (TODO: marked for pure Camp implementation).

**Planned tests:**
| Test | Scenario |
|------|----------|
| parse: full HTTP URI | `parse("https://user@host:443/path?q=1#frag")` == Ok(Uri{...}) |
| parse: minimal | `parse("/path")` == Ok(Uri{scheme:"", authority:Err, path:"/path", ...}) |
| parse: with query only | `parse("?a=1")` |
| parse: invalid | returns Err(UriErr) |
| parse: empty | `parse("")` == Err |
| to_str: roundtrip | `to_str(parse("https://example.com/path"))` == "https://example.com/path" |
| encode_component: reserved chars | `encode_component("a b")` == "a%20b" |
| decode_component: valid | `decode_component("a%20b")` == "a b" |
| decode_component: invalid | `decode_component("%XX")` == Err or undefined? |
| parse_query: single pair | `parse_query("a=1")` == [("a","1")] |
| parse_query: multiple | `parse_query("a=1&b=2")` == [("a","1"),("b","2")] |
| parse_query: empty | `parse_query("")` == [] |
| format_query: roundtrip | roundtrip with parse_query |
| with_scheme: replace | `with_scheme("https", parse("http://ex.com"))` has scheme "https" |
| with_path: replace | `with_path("/new", parse("http://ex.com/old"))` has path "/new" |

### 5.6 Uuid

**Current state:** All intrinsic.

**Planned tests:**
| Test | Scenario |
|------|----------|
| parse: valid standard format | `parse("550e8400-e29b-41d4-a716-446655440000")` == Ok(Uuid) |
| parse: invalid format | `parse("not-a-uuid")` == Err(InvalidFormat(...)) |
| parse: wrong length | `parse("short")` == Err(InvalidLength(...)) |
| to_str: standard format | `to_str(u)` has hyphenated 36-char format |
| format: Compact | 32 hex chars, no hyphens |
| format: Urn | `"urn:uuid:..."` |
| format: Braced | `"{...}"` |
| format roundtrip | `parse(to_str(u))` == Ok(u) |
| format: all variants roundtrip | each format variant parses back |
| version: v4 | generated UUID has version field 4 |
| version: v7 | generated UUID has version field 7 |
| variant: v4 | `variant(u)` == V4 |
| from_bytes -> to_bytes roundtrip | identity |
| timestamp: v7 has timestamp | `timestamp(v7_uuid)` returns I64 |
| timestamp: v4 absent | `timestamp(v4_uuid)` == Err(Absent) |

**Effectful tests (need handler):**
| Test | Scenario |
|------|----------|
| v4!: generates Uuid | returns Uuid value |
| v4!: version is 4 | `version(v4!())` == 4 |
| v7!: generates Uuid | returns Uuid |
| v7!: timestamp matches input | timestamp matches the provided I64 |
| v7!: unique per call | consecutive calls produce different UUIDs |

### 5.7 Base64

**Current state:** All intrinsic (TODO: planned for pure Camp implementation
using lookup tables + bit shifting).

**Planned tests:**

**Core encode/decode:**
| Test | Scenario |
|------|----------|
| encode64: empty bytes | `encode64(Bytes.new)` == "" |
| encode64: single byte | `encode64(from_list([0x41]))` == "QQ==" |
| encode64: two bytes | `encode64(from_list([0x41, 0x42]))` == "QUI=" |
| encode64: three bytes | `encode64(from_list([0x41, 0x42, 0x43]))` == "QUJD" |
| encode64: padding | correct padding for non-divisible-by-3 inputs |
| decode64: valid | `decode64("QUJD")` == Ok(from_list([0x41,0x42,0x43])) |
| decode64: with padding | `decode64("QQ==")` == Ok(from_list([0x41])) |
| decode64: invalid char | `decode64("!!!")` == Err(InvalidChar(...)) |
| decode64: invalid length | `decode64("A")` == Err(InvalidLength) |
| decode64: invalid padding | `decode64("QQ=")` == Err(InvalidPadding) |
| encode -> decode roundtrip | for various byte sequences |
| encode64url: uses URL-safe alphabet | `encode64url(from_list([0x3E, 0x3E]))` replaces + and / |
| encode16: single byte | `encode16(from_list([0xFF]))` == "ff" |
| encode16: multiple bytes | `encode16(from_list([0x00, 0x01, 0xFE, 0xFF]))` == "0001feff" |
| decode16: valid | `decode16("ff")` == Ok(from_list([0xFF])) |
| decode16: mixed case | `decode16("FF")` == Ok(from_list([0xFF])) |
| decode16: invalid hex | `decode16("xyz")` == Err |
| encode_str / decode_str: roundtrip | `decode_str(Standard, encode_str(Standard, "hello"))` == Ok("hello") |

**Format-specific encodings:**
| Test | Scenario |
|------|----------|
| encode/decode Standard | all valid bytes roundtrip through Standard alphabet |
| encode/decode UrlSafe | all valid bytes roundtrip through URL-safe alphabet |
| encode/decode Base32 | valid roundtrip for Base32 |
| encode/decode Hex | valid roundtrip for Hex |

---

## 6. Integration Test Scenarios

Integration tests live in `tests/e2e/language/kitchen-sink/Main.camp` (the
existing e2e test) or a dedicated `stdlib/integration.camp`. These exercises
cross-module workflows that real programs perform.

### 6.1 List -> Iter -> fold pipeline
```
[1,2,3,4,5]
  -> List.to_iter        -- convert to iterator
  -> Iter.map(\|x\| x*2)  -- double each
  -> Iter.filter(\|x\| x > 5)  -- keep > 5
  -> Iter.fold(0, add)   -- sum
-- result: 6 + 8 + 10 = 24
```

### 6.2 Result -> List composition
- `Result.from_list` on multi-element list
- `Result.to_list` then filter
- Map with Result values chained through `and_then`

### 6.3 Map -> Iter -> List roundtrip
```
Map.from_list([("a",1), ("b",2), ("c",3)])
  -> Map.to_iter
  -> Iter.fold([], \|acc, (k,v)\| List.append(acc, [(k,v)]))
-- reconstructs original list
```

### 6.4 Set operations chain
```
Set.union(Set.intersection(a, b), Set.difference(c, d))
-- complex set expression
```

### 6.5 Str -> Bytes -> Str pipeline
```
str -> Str.to_bytes -> Bytes.concat -> Bytes.to_str
-- encoding roundtrip
```

### 6.6 Json interop with Map
```
Json.decode(json_str)
  -> match: Obj(m) => Map.get("key", m)
-- JSON -> Map -> access
```

### 6.7 Duration arithmetic chain
```
Duration.add(Duration.mul(Duration.from_seconds(1), 3), Duration.from_millis(500))
-- == 3.5 seconds
```

### 6.8 Encode/decode pipeline with Base64
```
Bytes.new -> Base64.encode64 -> Base64.decode64 -> roundtrip identity
```

### 6.9 Path + File pipeline
```
Path.join(Path.new("/base"), Path.new("sub/file.txt"))
  -> File.read_all!
-- full I/O chain (requires handler)
```

### 6.10 Catch -> re-wrap pattern
```
Result.catch(|| {
  x = unwrap!(Ok(42))
  y = unwrap!(Ok(58))
  x + y
}) == Ok(100)
-- error-free unwrap! inside catch yields Ok
```

---

## 7. Property-Based Test Recipes

These are concrete instances of algebraic properties that should hold for the
stdlib. Each property is instantiated with a specific small input (not
generative, per R8).

### 7.1 Functor laws (Result.map, Iter.map, Map.map, Set.map)

**Identity:** `map(id, x) == x`
```
test "Result.map identity" {
  match Result.map(Ok(42), |x| x) { Ok(42) => 0 | _ => 1 }
}
```

**Composition:** `map(f ∘ g, x) == map(f, map(g, x))`
```
test "Result.map composition" {
  add1 = |x| x + 1
  double = |x| x * 2
  combined = |x| double(add1(x))
  direct = Result.map(Ok(3), combined)
  chained = Result.map(Result.map(Ok(3), add1), double)
  match direct {
    Ok(v) => match chained { Ok(w) => if v == w { 0 } else { 1 } | _ => 1 }
    _ => 1
  }
}
```

### 7.2 Monad laws (Result.and_then)

**Left identity:** `and_then(Ok(x), f) == f(x)`
**Right identity:** `and_then(m, Ok) == m`
**Associativity:** `and_then(and_then(m, f), g) == and_then(m, |x| and_then(f(x), g))`

### 7.3 Fold properties (Map.fold, Set.fold, Iter.fold)

**Empty returns init:** `fold(empty, init, f) == init`
**Singleton applies f once:** `fold(singleton(x), init, f) == f(init, x)`

### 7.4 Filter properties

**Filter all:** `filter(xs, |_| True) == xs` (value equality for collections)
**Filter none:** `filter(xs, |_| False)` is empty
**Idempotent:** `filter(filter(xs, p), p) == filter(xs, p)`

### 7.5 Roundtrip properties

**List -> Iter -> List:** `from_iter(to_iter(xs)) == xs`
**Iter -> List -> Iter:** `to_list(iter) -> from_list -> to_list` not identity (order may differ)
**Map -> List -> Map:** `from_list(to_list(m)) == m`
**Set -> List -> Set:** `from_list(to_list(s)) == s`
**Byte encode/decode:** `decode(encode(x)) == Ok(x)` for each Base64 format
**Str -> Bytes -> Str:** `from_bytes(to_bytes(s)) == Ok(s)` for valid UTF-8

### 7.6 Boolean algebra (Bool)

**Identity:** `and_(True, x) == x`, `or_(False, x) == x`
**Complement:** `and_(x, not_(x)) == False`, `or_(x, not_(x)) == True`
**Double negation:** `not_(not_(x)) == x`

### 7.7 Set algebra

**Union with empty:** `union(s, new) == s`
**Intersection with empty:** `intersection(s, new) == new`
**Union idempotent:** `union(s, s) == s`
**Intersection idempotent:** `intersection(s, s) == s`
**De Morgan:** (concrete instance) `difference(s, union(a, b)) == intersection(difference(s, a), difference(s, b))`

### 7.8 Duration algebra

**Add identity:** `add(d, zero) == d`
**Add commutativity:** `add(a, b) == add(b, a)` (if sign alignment)
**Sub inverse:** `sub(add(a, b), b) == a`
**Mul distribution:** `mul(add(a, b), n) == add(mul(a, n), mul(b, n))`
**Neg involution:** `neg(neg(d)) == d`

---

## Appendix A: Test File Organization

```
stdlib/
  Bool.camp          # tests: bottom           (complete)
  Result.camp        # tests: bottom + gaps    (partial)
  List.camp          # tests: bottom + gaps    (partial)
  Iter.camp          # tests: bottom + new     (none)
  Map.camp           # tests: bottom + new     (none)
  Set.camp           # tests: bottom + new     (none)
  Str.camp           # tests: bottom + new     (none)
  Bytes.camp         # tests: bottom + new     (none)
  Eq.camp            # trait: no tests
  Ord.camp           # trait: Order type test  (none)
  Hash.camp          # trait: no tests
  Debug.camp         # trait: no tests
  Display.camp       # trait: no tests (file may not exist)
  Default.camp       # trait: no tests
  Fmt.camp           # tests: bottom + new     (none)
  From.camp          # trait: no tests
  TryFrom.camp       # trait: no tests
  IntoIter.camp      # trait: no tests
  FromIter.camp      # trait: no tests
  Clone.camp         # trait: no tests
  Throw.camp         # no tests (effect ops)
  Console.camp       # no tests (effect ops)
  File.camp          # no tests (effect ops)
  Env.camp           # no tests (effect ops)
  Time.camp          # no tests (effect ops)
  Random.camp        # no tests (effect ops)
  Log.camp           # no tests (effect ops)
  Duration.camp      # tests: bottom + new     (none)
  Path.camp          # tests: bottom + new     (none)
  Json.camp          # tests: bottom + new     (none)
  Regex.camp         # tests: bottom + new     (none)
  Uri.camp           # tests: bottom + new     (none)
  Uuid.camp          # tests: bottom + new     (none)
  Base64.camp        # tests: bottom + new     (none)
  Num/
    I64.camp         # tests: bottom + new     (none)
    U64.camp         # tests: bottom + new     (none)
    F64.camp         # tests: bottom + new     (none)
    F32.camp         # tests: bottom + new     (none)
    ...
  integration.camp   # cross-module tests       (none)
```

## Appendix B: Test Execution Priority

| Phase | Modules | Effort | Impact |
|-------|---------|--------|--------|
| 1 | Iter, Map, Set | High | Core collections, enable all downstream |
| 2 | List, Result (gaps), Bool | Low | Close existing gaps |
| 3 | Str, Bytes, Num/I64 | Medium | String/numeric processing |
| 4 | Json, Base64 | Medium | Parsing/serialization |
| 5 | Duration, Path | Medium | Domain types |
| 6 | Effect modules (Throw!, Console!, etc.) | High | Need handler infrastructure |
| 7 | Regex, Uri, Uuid | Low | P2 modules |
| 8 | Trait test impls (Eq, Ord, Hash, etc.) | Low | Derive-driven, test with implementing types |
| 9 | Integration tests | Medium | Cross-module workflows |

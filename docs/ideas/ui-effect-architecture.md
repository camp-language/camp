# UI Architecture with Algebraic Effects

How Camp could structure frontend UI development using algebraic effects, exploring alternatives to Elm's MVU pattern that eliminate its plumbing overhead while preserving its type safety and purity guarantees.

---

## 1. The Elm MVU Problem

Elm's Model-View-Update architecture is clean and correct, but scales poorly due to explicit plumbing:

- **Msg type explosion**: Every UI event becomes a variant in a growing union type
- **Giant update function**: A single pattern-match over all messages, growing linearly with features
- **Cmd vs Sub distinction**: Two separate abstractions for one-shot and ongoing effects, each with their own API
- **Nested TEA / component isolation**: Child components cannot have private state. All state lives in the parent. Adding a child component requires: a wrapper Msg variant, a child update delegation branch, `Cmd.map` for routing child commands, and manual state threading
- **No scoped context**: Passing ambient data (theme, locale, router) requires threading through every intermediate component's `Msg` and `Model` types

The fundamental issue: Elm achieves effect decoupling by routing everything through a central `update` function with explicit message types. This is safe and predictable but creates O(n) boilerplate for n interacting concerns.

---

## 2. Research: How Effect Languages Handle UI

### Unison: Abilities as Components

Unison calls algebraic effects "abilities." Its handler pattern is structurally identical to a stateful UI component:

```unison
-- A handler manages its own state, handles operations, resumes computation
runStore : Request (Store k v) a -> Map k v -> (Map k v, a)
runStore = cases
  { Store.get k -> resume } -> resume (Map.lookup k store)
  { Store.put k v -> resume } -> resume () with (Map.insert k v store)
  { a } -> (store, a)
```

Each handler instance carries its own state. Nested handlers = nested components with independent state. The handler IS the component — state, update logic, and lifecycle all co-located. Functions declare what abilities they need in their type signatures (`{Abort, Store a}`), but intermediate code doesn't thread anything.

The Wordle lab demonstrates a game loop using abilities for I/O, validation, and state, showing the pattern works for interactive programs.

URL: https://www.unison-lang.org/docs/fundamentals/abilities/

### OCaml 5: Effects in Production

OCaml 5 added algebraic effects (2022). Key ecosystem developments:

- **Eio** (effects-based I/O): Replaces Lwt/Async monadic threading with direct-style code using effect handlers for `Net`, `File`, `Clock`, `Process`. Proves effects are more ergonomic than monads for real programs. URL: https://github.com/ocaml-multicore/eio
- **Ocsigen/Eliom**: The most mature effect-aware web framework. Multi-tier programming (client + server as one program), continuation-based web services, scoped state references (session-level, tab-level, request-level). URL: https://ocsigen.org/eliom/latest/manual/intro
- **Leo White's talk** ("Effective Programming: Adding an Effect System to OCaml"): Demonstrates replacing monad transformer stacks with direct-style effectful code. URL: https://www.janestreet.com/tech-talks/effective-programming/

The OCaml effects tutorial shows patterns directly applicable to UI: state as a handler threading through continuations, generators from iterators (analogous to incremental rendering), cooperative concurrency (analogous to React's concurrent mode). URL: https://github.com/ocamllabs/ocaml-effects-tutorial

### Koka: Capability-Passing Style

Koka (Daan Leijen, Microsoft Research) is the closest existing system to Camp's design — effect rows + perceus reference counting + capability-passing compilation. Effects compile to functions that receive handler references as implicit parameters. This is statically resolved, zero-overhead when inlined.

Effect rows are polymorphic: `fun component() : <console, dom|e> html` works with any additional effects `e`. No `map` needed. Handlers can be swapped at composition boundaries.

No UI framework exists for Koka yet, but its WASM target makes browser deployment viable.

URL: https://koka-lang.github.io/koka/doc/book.html

### Effekt: Contextual Effects

Effekt has lexical effect handlers with contextual effect polymorphism. Its "naturalistic DSLs" case study shows effects modeling ambient context (analogous to Theme/Router/Locale in UI). Handlers perform non-local rewriting at the handler position — exactly the pattern for scoped context propagation. `map` just works with effectful functions without special variants. Compiles to JavaScript.

URL: https://effekt-lang.org/

### The React Connection

Dan Abramov confirmed React Hooks are a weak approximation of algebraic effects (URL: https://overreacted.io/algebraic-effects-for-the-rest-of-us/). `useState()` is conceptually `perform State()`, handled by React when executing your component. React Suspense uses `throw Promise` as a crude approximation of `perform Suspend`. The "Rules of Hooks" (no conditional calls) are a direct consequence of trace-based approximation rather than real delimited continuations.

### The Gap

No algebraic-effect language has a mature frontend UI framework. The closest is Ocsigen/Eliom (OCaml), which predates OCaml 5 effects. The field is wide open.

---

## 3. The Identity Problem

React hooks rely on call-order-based identity: the Nth `useState()` call always maps to the Nth slot in an untyped array. This requires the "Rules of Hooks" — no conditional calls, no calls in loops.

With algebraic effects, we have lexical handler scoping: every `handle E! in ...` creates a distinct handler instance. But we still need a way for a single component to have multiple pieces of state without the system confusing them.

### Why `State!(a)` With Type-Driven Identity Solves This

Use one generic effect `State!(a)` parameterized by a record type. The **type argument** is the identity:

```camp
State!(a) : {
  get!: || -[State!(a)]-> a
  set!: |a| -[State!(a)]-> {}
  update!: |(a -> a)| -[State!(a)]-> {}
}
```

`State!(CounterModel)` and `State!(TodoModel)` are **different effects** because the type argument differs. An inner handler for `State!(CounterModel)` does not shadow an outer handler for `State!(TodoModel)`. The type system disambiguates, not call order.

This means:
- No call-order dependency — effects are identified by type, not position
- No Rules of Hooks — effects can be called conditionally, in loops, wherever
- No effect-per-field explosion — one `State!(a)` effect, `a` is a record with all state fields
- Each handler scope is its own world — inner handlers shadow outer handlers of the **same** type only

---

## 4. Core Design: Components as Pure Functions Over Effects

### The Handler

```camp
with_state = |initial: a, body: || -[State!(a) | ..effs]-> r| -[..effs]-> r {
  $state: a = initial
  handle State!(a) in body() with {
    .get!(resume) => resume($state)
    .set!(resume, new_state) => { $state = new_state; resume({}) }
    .update!(resume, f) => { $state = f($state); resume({}) }
  }
}
```

`$state` is a mutable binding inside the handler scope. The handler owns the mutation. The component body is pure — it calls `State.get!()` and `State.set!()` but never mutates directly.

### The Component

```camp
CounterModel : { count: I64, label: Str }

counter_view = || -[State!(CounterModel) | Dom!]-> {} {
  model = State.get!()

  Dom.element!("div", { class: "counter" }, [
    Dom.text!("${model.label}: ${model.count}"),
    Dom.button!("-1", {
      on_click: || State.update!(|m| { ..m, count: m.count - 1 })
    }),
    Dom.button!("+1", {
      on_click: || State.update!(|m| { ..m, count: m.count + 1 })
    }),
  ])
}
```

No `Msg` type. No `update` function. No `Cmd`. The component is a pure function that performs `State!(CounterModel)` and `Dom!` effects. The handler is installed by the parent.

### The Composition

```camp
app = || -[Dom!]-> {} {
  with_state(CounterModel { count: 0, label: "Clicks" }, ||
    with_state(TodoModel { todos: [], next_id: 0, input: "" }, ||
      Dom.element!("div", { class: "app" }, [
        counter_view(),
        todo_view(),
      ])
    )
  )
}
```

Each `with_state` call creates a distinct handler scope. `counter_view()` performs `State!(CounterModel)` — handled by the inner handler. `todo_view()` performs `State!(TodoModel)` — handled by the outer handler. No routing, no `Msg`, no `Cmd.map`.

---

## 5. Approaches Explored

### Approach A: Component-as-Handler

Each component IS a handler for its own state. The handler is installed at the component boundary.

```camp
counter_view = |props: { label: Str }| -[State!(CounterModel) | Dom!]-> {} {
  model = State.get!()
  Dom.element!("div", {}, [
    Dom.text!("${props.label}: ${model.count}"),
    Dom.button!("+1", { on_click: || State.update!(|m| { ..m, count: m.count + 1 }) }),
  ])
}

// Parent installs the handler
mount_component = |initial, view_fn| -[Dom! | ..effs]-> {} {
  with_state(initial, view_fn)
}
```

**Strengths**: Simple, handler scoping = component scoping. **Weakness**: No lifecycle management.

### Approach B: Capability Hooks (React-Style)

Components receive capability records instead of performing effects directly. Like `useState()` returning `[value, setter]`, but typed and pure.

```camp
CounterCapabilities : {
  count: I64
  increment: || -> {}
  decrement: || -> {}
}

counter_view = |caps: CounterCapabilities| -[Dom!]-> {} {
  Dom.element!("div", {}, [
    Dom.text!("Count: ${caps.count}"),
    Dom.button!("-1", { on_click: || caps.decrement() }),
    Dom.button!("+1", { on_click: || caps.increment() }),
  ])
}

use_counter = |initial: I64| -[State!(CounterModel)]-> CounterCapabilities {
  model = State.get!()
  CounterCapabilities {
    count: model.count,
    increment: || State.update!(|m| { ..m, count: m.count + 1 }),
    decrement: || State.update!(|m| { ..m, count: m.count - 1 }),
  }
}
```

**Strengths**: Looks like React hooks. Component receives data as values, not effects. **Weakness**: Requires an extra record type per component.

### Approach C: Scoped Context Effects

Effects like `Theme!`, `Router!`, `Locale!` propagate automatically through the component tree via effect rows. No prop-drilling.

```camp
Theme! : {
  current!: || -[Theme!]-> Theme
  toggle!: || -[Theme!]-> {}
}

// Deeply nested component uses Theme! without knowing where it's handled
nav_link = |label: Str, path: Str| -[Theme! | Router! | Dom!]-> {} {
  theme = Theme.current!()
  current = Router.path!()
  is_active = current == path
  color = if is_active { theme.accent } else { theme.muted }

  Dom.element!("a", {
    style: "color: ${color}",
    on_click: || Router.navigate!(path),
  }, [Dom.text!(label)])
}

// Handlers at the boundary
app = || -[Dom!]-> {} {
  $theme = Theme.Dark
  $path = "/"

  handle Theme! in {
    handle Router! in {
      Dom.element!("div", {}, [
        nav_link("Home", "/"),
        nav_link("Settings", "/settings"),
      ])
    } with {
      .path!(resume) => resume($path)
      .navigate!(resume, url) => { $path = url; resume({}) }
    }
  } with {
    .current!(resume) => resume($theme)
    .toggle!(resume) => {
      $theme = match $theme { Dark => Light, Light => Dark }
      resume({})
    }
  }
}
```

**Strengths**: No prop-drilling. Adding a new ambient capability doesn't change intermediate components. Effect type signatures tell you exactly what a component needs. **Weakness**: Only for ambient context, not local state.

### Approach D: Resource Lifecycle Effects

Component mount/unmount as effect scope boundaries. When a handler is installed, that's "mount." When the handler scope exits, that's "unmount."

```camp
Resource! : {
  acquire!: |(|| -[e]-> a)| -[Resource! | e]-> a
  on_release!: |(|| -[e]-> {})| -[Resource! | e]-> {}
}

// Cleanup happens automatically when handler scope exits
websocket_feed = |url: Str| -[State!(FeedState) | Dom!]-> {} {
  handle Resource! in {
    messages = State.get!()
    Dom.element!("div", {},
      messages.items->List.map(|msg| {
        Dom.text!(msg.text)
      })
    )
  } with {
    .acquire!(resume, init_fn) => {
      resource = init_fn()
      resume(resource)
      // resource is cleaned up when handler scope exits
    }
    .on_release!(resume, cleanup_fn) => {
      // stored for scope exit
      resume({})
    }
  }
}
```

**Strengths**: No `useEffect` cleanup. No stale closures. Resource lifecycle = handler scope. **Weakness**: Needs careful handler-scope exit semantics.

### Approach E: Composable Gadgets

Small, reusable effect-based "gadgets" that encapsulate state + behavior. Compose like React hooks but they're pure effect operations returning capability records.

```camp
Toggle : {
  is_on: Bool
  toggle: || -> {}
  set: |Bool| -> {}
}

use_toggle = |initial: Bool| -[State!(Bool)]-> Toggle {
  current = State.get!()
  Toggle {
    is_on: current,
    toggle: || State.set!(not current),
    set: |v: Bool| State.set!(v),
  }
}

// Usage in a component — each gadget gets its own with_state scope
settings_page = || -[Dom!]-> {} {
  with_state(False, ||
    with_state(True, ||
      with_state("", || {
        // Need capability hooks to extract handles
        // See Approach B for the pattern
        todo
      })
    )
  )
}
```

**Strengths**: Small, testable, composable units. **Weakness**: Needs Approach B's capability pattern to extract handles from handler scopes.

### Approach F: Record Builder Pattern (Inspired by Weaver)

Roc's record builder syntax (`: <-`) composes applicative operations field-by-field. Each slot independently produces a value. The builder wires them into a record.

In Camp, the equivalent is: each "slot" is a handler that wraps the next. The nesting IS the builder.

```camp
// Factor handlers into reusable slot functions
counter_slot = |config: { initial: I64, label: Str },
               body: || -[State!(CounterModel) | ..effs]-> r|
               -[Dom! | ..effs]-> r {
  with_state(CounterModel { count: config.initial, label: config.label }, body)
}

todo_slot = |config: { placeholder: Str },
            body: || -[State!(TodoModel) | ..effs]-> r|
            -[Dom! | ..effs]-> r {
  with_state(TodoModel { todos: [], next_id: 0, input: "" }, body)
}

// THE BUILDER: each slot wraps the next.
// Each *_slot(|| ...) call IS the <- in Roc's builder syntax.
app = || -[Dom!]-> {} {
  counter_slot({ initial: 0, label: "Clicks" }, ||
    todo_slot({ placeholder: "New task" }, ||
      Dom.element!("div", { class: "app" }, [
        counter_view(),
        todo_view(),
      ])
    )
  )
}
```

A `weave_ui` function can take a record of initial states and a render function:

```camp
AppState : {
  counter: CounterModel
  todos: TodoModel
  theme: ThemeModel
}

weave_ui = |state: AppState,
            render: || -[State!(CounterModel) | State!(TodoModel) | State!(ThemeModel) | Dom!]-> {}|
            -[Dom!]-> {} {
  with_state(state.counter, ||
    with_state(state.todos, ||
      with_state(state.theme, ||
        render()
      )
    )
  )
}

app = || -[Dom!]-> {} {
  weave_ui(AppState {
    counter: CounterModel { count: 0, label: "Clicks" },
    todos: TodoModel { todos: [], next_id: 0, input: "" },
    theme: ThemeModel { current: Dark },
  }, ||
    Dom.element!("div", { class: "app" }, [
      counter_view(),
      todo_view(),
      theme_picker(),
    ])
  )
}
```

**Strengths**: Closest to Weaver's ergonomics. Initial state composed as a record. Handlers installed once. **Weakness**: Nesting depth equals number of state types. Could be flattened with a generic multi-handler if the language supported it.

---

## 6. The Separation of Concerns

The key insight from all this exploration: **not all component state needs to be an effect.**

| Concern | Mechanism | Why |
|---------|-----------|-----|
| Local component state | `State!(a)` with handler scoping | Identity is the type, not call order. No Rules of Hooks. |
| Scoped context (theme, router) | Named effects (`Theme!`, `Router!`) | Needs to propagate through tree. Handler provides value at boundary. |
| Side effects (HTTP, storage) | Named effects (`Http!`, `Storage!`) | Handler decides implementation (real, mock, SSR). |
| Lifecycle | `Resource!` effects or handler scope exit | Handler scope = component lifetime. |

React puts everything in the "hooks" bucket. Elm puts everything in the "message" bucket. The right design uses **`State!(a)` for local concerns and named effects for non-local concerns**.

---

## 7. Comparison

### Elm MVU vs Camp Effects

```camp
// Elm: 3 types + 1 update function + Cmd.map for children
type Msg = Increment | Decrement | AddTodo String | ...
type alias Model = { count : Int, todos : List Todo, ... }
update : Msg -> Model -> (Model, Cmd Msg)
-- Plus: child component Msg wrappers, Cmd.map, Sub.map

// Camp: 2 record types + pure view functions + with_state
CounterModel : { count: I64, label: Str }
TodoModel : { todos: List(Todo), next_id: I64, input: Str }
counter_view = || -[State!(CounterModel) | Dom!]-> { ... }
todo_view = || -[State!(TodoModel) | Dom!]-> { ... }
// Composition: with_state(CounterModel { ... }, || with_state(TodoModel { ... }, || ... ))
```

### Full Comparison Matrix

| Aspect | Elm MVU | React Hooks | Camp `State!(a)` |
|--------|---------|-------------|-------------------|
| State identity | Msg variant | Call order | Type argument |
| State location | Parent model | Hidden array | Handler scope |
| Component interface | Msg + Cmd | Props + hooks | Effect row |
| Composition | Msg union + `Cmd.map` | Nesting | Handler nesting |
| Reusability | Msg.map boilerplate | Custom hooks | Slot functions |
| Type safety | Full (verbose) | None (JS) | Full (inferred) |
| Conditional use | Yes (in update) | No (Rules of Hooks) | Yes |
| Testing | Test update fn | Mock hooks | Swap handler |
| Context/prop-drilling | Manual threading | Context.Provider | Effect row propagation |
| Lifecycle | Subscriptions | useEffect | Handler scope / Resource! |

---

## 8. Open Questions

1. **Handler nesting depth**: With N state types, you get N levels of `with_state` nesting. Can the compiler or a macro flatten this? A multi-handler syntax like `handle State!(a), State!(b) in ...` would need the runtime to dispatch by type argument.

2. **View rendering model**: The examples use `Dom.element!()` effects that produce VNodes. Should the view be an effect stream (incremental rendering) or return a VNode tree (virtual DOM diffing)? The effect-based approach (Approach F in the brainstorm) gives the handler freedom to choose.

3. **Re-rendering**: When `State.set!()` is called, how does the framework know to re-render? The handler could call `resume({})` and then trigger a re-render of its subtree. The deep handler semantics (reinstalls after resume) support this naturally.

4. **Interop with existing DOM**: Camp targets WASM/WASI. The `Dom!` effect would need a handler that bridges to the browser DOM API via WASI or a custom FFI boundary. The `Dom!` effect definition is the abstraction layer — the handler bridges to the platform.

5. **Event handler callbacks**: The examples pass lambdas to `on_click`, `on_input`, etc. These callbacks perform effects (`State.update!`). The runtime needs to install the appropriate handlers when invoking these callbacks. This is similar to how React's event system works — events are batched and processed within the component's fiber (handler scope).

6. **Type parameter matching in effect dispatch**: When multiple `State!(a)` handlers are in scope with different `a`, the compiler must route each `State.get!()` call to the handler whose `a` matches the inferred return type. This requires return-type-directed dispatch or explicit type annotations at call sites when types are ambiguous.

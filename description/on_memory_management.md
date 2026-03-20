# On Memory Management

This document collects the current reflection about memory management in Argi.
It is not a closed specification yet. The goal is to clarify:

- which problems the language wants to solve,
- which tradeoffs are acceptable,
- which ideas should be part of the semantic core,
- and which mechanisms should remain explicit, optional, or postponed.


## The Core Tension

Argi does not want its default behavior to be:

- so permissive that heap-owning values can be shallow-copied by accident,
- nor so analysis-heavy that everyday programming revolves around
  borrow-checker constraints.

The goal is to preserve freedom and explicit control, while making the default
semantics act as guardrails against the most common memory-management mistakes.

The intended direction is:

- strict value semantics,
- explicit references,
- automatic destruction,
- limited but meaningful aliasing checks,
- and no full borrow checker or user-visible lifetime annotations.


## The Main Problems

The language should try to make these problems hard to write by accident:

- shallow copies of owning values,
- double free,
- use after free,
- accidental shared mutation through aliasing,
- hidden ownership transfer,
- APIs whose safe use depends on knowing internal representation.

At the same time, it should avoid forcing the user into:

- pervasive lifetime annotations,
- a global borrow checker mental model,
- reference-counting overhead everywhere,
- or a GC-based runtime.


## Comparison: Rust, Zig, Argi

### Rust

Rust tries to solve:

- use after free,
- double free,
- aliasing with mutation,
- data races,
- invalid references.

It does so with:

- ownership by default,
- move semantics,
- `&` and `&mut`,
- compile-time borrow checking,
- lifetimes,
- automatic `Drop`.

Strengths:

- very strong guarantees for references and aliasing,
- excellent prevention of dangling references,
- good model for complex borrowing once understood.

Costs:

- significant mental overhead,
- difficult ergonomics in self-referential or graph-like structures,
- compiler model becomes a central part of everyday programming.


### Zig

Zig tries to solve:

- explicit control,
- predictable cost,
- simple semantics,
- allocator-based memory management.

It does so with:

- mostly pass-by-value semantics,
- explicit pointers,
- manual or semi-manual destruction patterns,
- explicit allocators,
- `defer` / `errdefer`.

Strengths:

- simple operational model,
- good fit for systems code and compilers,
- little semantic machinery.

Costs:

- shallow-copy bugs are easy to write,
- ownership is often a convention rather than a guaranteed property,
- aliasing and lifetime discipline is largely on the programmer.


### Argi

Argi should aim for:

- avoiding shallow-copy surprises,
- keeping references explicit,
- keeping destruction automatic at scope exit,
- enforcing a limited but useful notion of mutable exclusivity,
- and remaining simpler than Rust.

The working direction is:

- value position means independent value,
- `copy()` or compile error,
- `&T` means shared read access,
- `$&T` means exclusive mutable access,
- `deinit()` is inserted automatically,
- no full borrow checker,
- no user-written lifetimes.


## Core Proposed Rules

### 1. Value Position Means Independence

A value is in value position when it is:

- assigned to another variable,
- passed to a function argument declared as `Type`,
- stored by value inside another value,
- returned by value.

The semantic rule should be:

> Using a value in value position means requesting an independent value.

That means:

- if the expression is a temporary value, it can be moved directly,
- if the expression names an existing value and the type implements `copy()`,
  the compiler may insert it implicitly,
- otherwise the operation is a compile error,
- and the diagnostic should suggest `&`, `$&`, or implementing `copy()`.

For now, a useful working split is:

- temporary values move by default,
- existing named values copy by default,
- explicit move from an existing binding uses `~binding`.


### Temporary Values vs Existing Values

Not every value position should behave the same internally.

These cases should count as temporary values:

- literals,
- constructors,
- results of function calls,
- intermediate values created while composing calls.

Those values are already independent, so they can flow into value position
without requiring an extra copy.

By contrast, reusing an existing binding in value position means:

- implicit `copy()` if the type is copyable,
- or a compile error if it is not.

This is the key rule that keeps value semantics safe without making composed
expressions unnecessarily expensive.


### Explicit Move

Argi should also support an explicit move operation for existing bindings:

- `~x` means transfer the value out of `x`,
- after that, `x` cannot be used again until it is reinitialized,
- and `deinit()` should not run for that moved-out state.

This is especially useful when ownership transfer is intended and an implicit
copy would be either expensive or invalid.

The intended balance is:

- copy remains the default for named values used by value,
- move remains explicit for named values,
- but temporary composed values move naturally without extra syntax.

> [!NOTE]
> It may be tempting to optimize the last implicit copy of a binding into a
> move when the binding is not used again.
>
> For now, that should not be part of the model.
> Once references, views, `keep`, and aliasing are considered, that
> optimization becomes much more subtle.
> The language can stay correct and understandable without it, and it can
> always be reconsidered later as a conservative optimization.


### 2. References Are Explicit

The meaning should stay simple:

- `Type`: independent value semantics,
- `&Type`: shared read access,
- `$&Type`: exclusive mutable access.

This keeps the user-facing model direct and visible.


### 3. Automatic Destruction at Scope Exit

For now, the base rule should be:

- values are automatically deinitialized when they go out of scope.

This is much simpler than trying to move destruction to last use immediately.
Last-use destruction can remain an optimization for the future.

> [!NOTE]
> Moving `deinit()` from scope exit to last use may look attractive as an
> optimization, but it requires substantially more analysis:
> aliasing, control flow, partial initialization, retained views, early returns,
> and future mechanisms such as `keep`.
>
> Because of that, scope-exit destruction may remain the preferred semantic base
> for a long time, even if some local last-use optimizations become possible.


### 4. Mutable Exclusivity Should Be Local and Pragmatic

Argi should not try to reproduce Rust's full borrow checker.
But it should still reject obvious local misuse.

Minimum useful rule:

- in a single call, if a binding is passed as `$&`, the same binding should not
  also appear as:
  - another `$&`,
  - a `&`,
  - or a value argument.

This would already eliminate a meaningful class of confusing aliasing bugs
without introducing global lifetime reasoning.


## What Argi Should Not Try to Do

At least in the first stable model, Argi should probably avoid:

- full borrow checking,
- user-visible lifetime parameters,
- proving global aliasing properties,
- making every reference statically lifetime-safe the way Rust does,
- and making all view-like types automatically reference-counted.

Those would push the language into a much heavier model than the rest of the
design suggests.


## Views: The Real Difficult Problem

The deepest unresolved issue is not mutable aliasing in a single call.
It is non-owning views.

The problem is:

- an owner exists,
- a view references its data,
- the owner dies,
- the view becomes invalid.

Rust solves this with lifetimes.
Zig largely leaves this to discipline.
Argi should likely take a third path.


### Proposed Direction for Views

The recommended direction is:

- a normal view is non-owning and lightweight,
- it does not extend the lifetime of the owner,
- it should remain cheap and explicit,
- if the user wants the view to survive independently, that should be an
  explicit promotion step.

In other words:

- a plain view stays a plain view,
- retained/shared/kept views should be explicit,
- and that promotion may use a runtime strategy such as:
  - reference counting,
  - arena ownership,
  - or another explicit manager.

This should not necessarily imply a completely separate family of surface
types. It may be preferable to express retention through composition,
promotion, or an explicit wrapper mechanism rather than by proliferating many
distinct view names.

One candidate mechanism already present in the language design is `keep`.

The intended role of `keep` would be:

- a plain view remains non-owning,
- if the user wants the viewed data to outlive the original lexical scope,
  that retention must be requested explicitly,
- and `keep` becomes the point where lifetime responsibility is transferred to
  some explicit runtime or manager.

For example, conceptually:

```rg
my_view := my_array|view(...)
keep my_array with my_view
```

Or, in a future more explicit form:

```rg
keep my_view on rc_heap
keep my_object on gc_runtime
```

The exact syntax and return types are still open, but the semantic idea is
important:

- plain views do not keep anything alive,
- retained views do,
- and the transition must be explicit.

> [!IDEA]
> Igual en muchos casos no hace falta `keep`.
> Si el problema aparece al intentar devolver una view, quizá la mejor solución
> sea devolver el valor owner, o un struct que contenga el owner y los datos
> necesarios para reconstruir la view.
>
> Eso evitaría el problema de lifetime en vez de gestionarlo explícitamente.
> Además encaja bien con que al hacer `return` del owner no se le hace `deinit`,
> porque pasa a formar parte del resultado.

The important semantic point is:

> A plain view does not keep anything alive.


### Why Not Put RC in All Views?

Making every view implicitly reference-counted would blur the model:

- views would stop being cheap and predictable,
- costs would become less visible,
- and the language would mix two lifetime strategies without a clear boundary.

That seems worse than requiring an explicit promotion when shared retention is
needed.


## Ownership-Centralized Data Structures

For certain structures, trying to model ownership directly in each node tends
to become awkward in every language.

This includes:

- linked lists,
- trees with parent references,
- graphs,
- ECS-like storages,
- AST arenas,
- symbol tables with cross-links,
- self-referential structures.

In Argi, the recommended pattern should be:

- a central owner holds the memory,
- inner elements are non-owning,
- relationships are expressed using:
  - IDs,
  - handles,
  - indices,
  - or non-owning references/views.

Examples:

- `Graph` owns all nodes and edges,
- `Arena#(Node)` owns all nodes, while edges store `NodeId`,
- compiler structures own AST/type/symbol storage centrally.

This avoids distributed ownership, reduces lifetime complexity, and fits well
with allocator-based design.


## Important Optimization Principle

Even if value semantics mean "copy or error", the implementation should still
be allowed to optimize.

Important example:

- returning by value may semantically mean "independent value",
- but if the compiler can prove no surviving observable alias or owner needs to
  coexist, it may elide the actual copy.

So the rule should be:

- semantic model: copy,
- implementation freedom: copy elision when behavior stays identical.

This is important because otherwise the model could become too expensive in
practice.


## Tricky Example Areas

### 1. Heap-owning value types

Examples:

- `String`,
- `DynamicArray`,
- `HashMap`.

Rust:

- good guarantees,
- explicit `clone()`/move model,
- but sometimes ownership is heavier than desired.

Zig:

- easy to represent,
- easy to misuse by copying descriptor structs.

Argi:

- should be especially strong here,
- because `copy()` or error directly solves the shallow-copy trap.


### 2. Mutable + shared aliasing in one call

Conceptual example:

- mutate one argument,
- read another,
- both may refer to the same value.

Rust:

- borrow checker rejects invalid combinations.

Zig:

- usually allowed,
- correctness depends on programmer discipline.

Argi:

- should reject the obvious same-binding cases locally,
- without trying to prove all indirect aliases.


### 3. Returning a view into a local value

Rust:

- lifetimes usually reject it.

Zig:

- easy to write accidentally,
- often dangerous.

Argi:

- this remains a hard problem,
- and plain views should probably stay restricted/non-owning,
- with explicit promotion mechanisms for retained views.


### 4. Partial initialization with failure

Example:

- a type allocates multiple resources in `init`,
- then one step fails.

Rust:

- ownership + `Drop` help,
- though this is still non-trivial.

Zig:

- `errdefer` handles this pattern very well.

Argi:

- this should become one of its stronger areas,
- especially if `init` can return something like `Errable#(...)`,
- but only if `init`, initialization state, and auto-`deinit` are modeled more
  explicitly than they are today.
- in particular, the language needs a believable story for:
  - fully initialized values,
  - partially initialized values,
  - and failed initialization paths where cleanup may or may not already have
    happened.


### 5. Graphs and self-referential structures

Rust:

- safe but often awkward,
- frequently requires `Rc`, `RefCell`, arenas, or `unsafe`.

Zig:

- direct and flexible,
- but easy to misuse.

Argi:

- should prefer ownership-centralized patterns rather than trying to make
  distributed ownership feel magical.


## Current Design Direction

If Argi wants to keep its identity, the likely stable direction is:

- no shallow-copy surprises,
- no borrow checker everywhere,
- explicit references,
- automatic destruction,
- explicit retention/promotion for non-owning views when needed,
- centralized ownership for complex graph-like memory shapes.

That would make Argi:

- stricter and safer than Zig in value semantics,
- much lighter than Rust in lifetime machinery,
- and still compatible with allocator-oriented systems programming.


## Open Questions

- Which types are trivially copyable by default?
- Should `deinit()` be optional for trivially droppable types?
- How exactly should retained/shared views be expressed?
- Should `keep` be the main promotion mechanism, or only one of several?
- How much local exclusivity checking should `$&` perform?
- What minimal static checks should exist for plain views before they become
  too restrictive?
- How should `init(...)->Errable#(...)` interact with initialization state and
  partial cleanup?


## Working Recommendation

For now, the best path seems to be:

1. keep the semantic core small and strict,
2. implement `copy()` or error before trying advanced moves,
3. keep `deinit` at scope exit first,
4. introduce only local mutable exclusivity checks,
5. treat plain views as non-owning and cheap,
6. make retained/shared views explicit,
7. recommend centralized ownership for hard graph-like structures.

This gives Argi a real memory-management identity without committing too early
to either Zig's permissiveness or Rust's full lifetime machinery.

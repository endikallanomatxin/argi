# Memory Management Precedents and Design Lessons

This page complements `37_memory_management.md`. It is not part of the language
specification; it records relevant precedents and the lessons that motivate the
current Argi design.

The important point is not that any existing language already implements the
same model. Different systems validate different pieces of it, and also expose
where the difficult parts are likely to be.


## Mojo: inferred provenance, but origins become type parameters

Mojo has a lifetime checker based on **origins**. An origin tracks where a
reference comes from, whether it is mutable, and how long the referenced value
must remain valid. Origins are mostly inferred by the compiler, but they also
appear as `comptime` parameters in reference-bearing types and APIs.

Examples include pointer/span-like types parameterized by an origin and
reference-returning functions whose result origin is tied to an input.

This is close to Argi's intended internal model:

```text
source
    &T

compiler
    &T @ alpha
```

The major difference is where that provenance is carried. Mojo commonly carries
it in the parametric type; Argi wants to carry it as hidden temporal state on
values and through compiler-generated function summaries.

Mojo also provides an important warning about coarse provenance. A reference to
an element of a collection cannot simply depend on the lifetime of the
collection object: operations such as `append`, `pop`, replacement, or
reallocation may invalidate the element while the collection itself remains
alive. Mojo's work on interior origins reflects the same problem that motivates
Argi's distinction between an invalidation root and a logical subobject/epoch.

**Lesson for Argi:** provenance inference is practical, but provenance must
travel compositionally through structs, views, closures, containers, returns,
and destruction. If Argi keeps it out of nominal source types, hidden value
state and summaries must provide an equally reliable carrier.

References:
- https://mojolang.org/docs/manual/values/lifetimes/


## Vale: single ownership with freely mutable aliases

Vale's Linear-Aliasing Model combines a single owner for each object with an
arbitrary number of mutable non-owning references. This is very close to the
motivation for separating Argi's `$&` from exclusivity.

Vale demonstrates that mutable aliasing is especially useful for:

- graphs and intrusive data structures,
- parent/back references,
- observers and callbacks,
- objects that need to mutate other objects without transferring ownership.

Vale pays for this freedom differently from Argi. Its generational references
can perform runtime liveness checks, with opportunities to eliminate checks
statically.

Argi instead aims for:

```text
single resource responsibility
+ mutable aliasing
+ static invalidation analysis
+ zero normal runtime lifetime checks
```

**Lesson for Argi:** mutable aliasing is a useful design point, not merely a
relaxation of Rust. The difficult part is temporal safety. Vale pays for it with
generations; Argi is deliberately attempting the more ambitious static route.

Reference:
- https://vale.dev/linear-aliasing-model


## Cyclone: safe manual memory through regions

Cyclone combined C-like low-level control with region-based memory management.
Objects belong to regions, and references are checked so that they do not
outlive the regions containing their referents.

This strongly supports Argi's use of allocation/region boundaries as coarse
invalidation domains:

```text
node A --\
node B ----> Rregion
node C --/
```

Cyclone also shows why region information needs a compositional representation.
Its design was built to support separate compilation, using type/effect
information rather than whole-program analysis.

**Lesson for Argi:** regions are a proven way to make large object graphs
temporally homogeneous. They are not only allocation optimizations. Also, if
Argi refuses to put region/lifetime information in normal source types, its
temporal summaries must still preserve the information needed across module
boundaries.

References:
- https://www.cs.cornell.edu/projects/cyclone/
- https://www.cs.cornell.edu/projects/cyclone/online-manual/main-screen008.html


## Spegion: implicit non-lexical regions through effects

Spegion (ECOOP 2025) is particularly close to the philosophy behind Argi. It
explores **implicit, non-lexical regions** while avoiding a substructural type
system, relying instead on an effect system to control region allocation and
deallocation. It also supports splitting regions into finer subregions.

This is evidence that static lifetime safety does not require exposing a
Rust-like ownership/lifetime surface syntax. Temporal constraints can instead
be represented as compiler effects.

**Lesson for Argi:** the idea of keeping temporal machinery mostly out of the
source type surface has serious precedent. Argi's temporal summaries can be
viewed as a practical effect/provenance layer specialized for references,
storage and invalidation.

Reference:
- https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2025.15


## Pony: read-only access does not imply global immutability

Pony's reference capabilities separate the permissions held by one reference
from what aliases may do. In particular, `ref` permits mutable aliasing inside
an actor, while `box` is read-only through that reference even though another
local alias may still mutate the object.

This is an important precedent for Argi's intended meaning of `&`:

```text
&T
    this reference can read
    does not imply the referent is globally immutable

$&T
    this reference can mutate
    aliases may coexist
```

Pony uses a richer capability matrix, largely because it also integrates
concurrency safety. Argi deliberately wants a smaller ordinary reference model
and to treat thread sharing as a separate dimension.

**Lesson for Argi:** `&` without global immutability and safe mutable aliases are
coherent concepts. Avoid letting the reference model grow into a large
capability lattice unless concurrency later proves that necessary.

References:
- https://tutorial.ponylang.io/reference-capabilities/reference-capabilities.html
- https://tutorial.ponylang.io/reference-capabilities/guarantees.html


## Project Verona: regions as the unit of ownership reasoning

Project Verona explores ownership and memory management at region granularity
instead of requiring per-object linearity everywhere. One of its explicit
research questions is whether linear regions can remove restrictions imposed by
per-object linearity without losing safety.

This is very close to why arenas are important in Argi. A graph whose nodes all
share one region can contain rich internal aliasing while the important temporal
transition is the lifetime of the region as a whole.

Verona also provides a useful warning: some ownership patterns are easy to
check dynamically but difficult to express statically. Its ongoing research has
revisited the balance between static and dynamic checking.

**Lesson for Argi:** region granularity can greatly simplify real object graphs,
but the compiler should not promise arbitrary precise per-object deletion in a
structure whose architecture naturally exposes only a regional lifetime.

References:
- https://microsoft.github.io/verona/faq.html
- https://microsoft.github.io/verona/publications.html


## Rust: the baseline Argi is deliberately decomposing

Rust proves that strong static temporal safety, deterministic destruction and
separate compilation can coexist in a production systems language. Its main
tradeoff for Argi is that reference validity, mutation and exclusivity are
closely connected through borrowing and lifetimes.

Argi is not trying to weaken Rust's safety target. It is testing a different
decomposition:

```text
Rust
    shared borrow
    exclusive mutable borrow
    lifetime relations in the type/borrow system

Argi
    &      read permission
    $&     aliasable mutation
    $$&    exclusive temporal/invariant transition
    hidden provenance + invalidation analysis
```

Internally Argi may still need symbolic lifetime variables, outlives-like
relations, liveness, and quantified provenance. The intended difference is that
these are normally compiler semantics rather than nominal source type
parameters.

**Lesson for Argi:** do not make the checker artificially weaker merely to be
simpler than Rust. The target is to move temporal complexity out of ordinary
source types while retaining enough internal precision for sound modular
checking.


## Zig: the control and simplicity baseline

Zig is the opposite useful baseline. Allocators and pointer operations are
explicit and operationally simple, but pointer lifetime correctness is largely
the programmer's responsibility.

Argi wants to preserve much of that allocator-oriented, pointer-friendly feel
while statically preventing dangling safe references.

**Lesson for Argi:** Argi will inevitably have a more sophisticated compiler
than Zig in this area. The value proposition only holds if most of that
complexity remains invisible in ordinary code and does not destroy the direct
operational model.


## What appears distinctive in Argi

The individual ingredients all have precedents. The combination is less common:

```text
manual deterministic resource management
+ first-class safe references
+ aliasable mutation
+ exclusivity only for temporal/invariant transitions
+ static provenance/invalidation checking
+ region-aware storage
+ temporal dependencies outside nominal source type identity
+ compiler-generated interprocedural summaries
+ conservative provenance at erasure boundaries
+ transfer separated from physical relocation
```

The central experiment is therefore not whether lifetimes can be eliminated.
They cannot: the compiler still needs temporal information.

The experiment is whether this information can remain a **hidden temporal
refinement of values and functions**, rather than a routine parameter of source
types, while staying compositional enough for containers, generics, closures,
separate compilation and incremental compilation.

The implementation should be judged against that criterion. If temporal
annotations begin leaking routinely into ordinary source types, Argi is moving
toward the Mojo/Rust solution. If hidden dependencies and summaries remain
small and predictable, the design provides a genuinely different ergonomic
point in the systems-language design space.

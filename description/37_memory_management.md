# Memory Management

This page is the canonical description of Argi's memory-management direction.
Older design notes remain useful for value/copy/allocation details, but any
conflicting reference-safety rules are superseded by this document.

The objective is deterministic, allocator-oriented memory management with
static protection against dangling references, while avoiding user-visible
lifetime parameters in ordinary source types.


## 1. Separate resource semantics from reference safety

Argi treats these as different concerns:

```text
resource/value semantics
    copy()
    ~
    deinit()

reference permissions
    &T
    $&T
    $$&T

temporal safety
    provenance
    invalidation domains
    liveness
```

`copy()` creates an independent value according to the type's semantics.
`~x` transfers responsibility for the same logical value out of `x`.
`deinit()` ends that responsibility and releases the resources owned by the
value.

Temporal validity is tracked separately by the compiler. Moving responsibility
does not by itself mean moving the storage to which references point.


## 2. Reference permissions

Argi separates reading, mutation, and exclusivity:

```text
&T
    shared read access

$&T
    mutable, aliasable access

$$&T
    temporary exclusive access
```

The important difference from Rust is that mutation does not imply exclusivity.
A shared `&T` does not globally freeze the referent: another `$&T` may mutate it
while both references are valid.

For example, this is allowed when `modify` preserves the temporal contract of
`value`:

```rg
reader := &value
writer := $&value

writer | modify()
reader | inspect()
```

Consequently, the compiler must not generally treat `&T` as immutable or
`$&T` as `noalias`.


## 3. `$&` preserves the temporal contract; `$$&` may change it

Ordinary aliased mutation is safe only while it preserves the validity
structure seen by existing references.

The working rule is:

```text
$&
    may mutate data
    must preserve the object's temporal/provenance contract

$$&
    may perform an exclusive temporal or invariant transition
```

`$$&` is an exclusive-access capability, not a statement that no other
reference value to the same storage exists. Other aliases may remain dormant
while the exclusive access is active. What is forbidden is any overlapping
access through those aliases during the exclusive window.

Conceptually:

```text
shared alias exists ------------------------------->

                 $$& exclusive window
                 |-----------------|
                 no overlapping access

                                      shared alias may resume
```

After the exclusive window ends, a dormant alias may be used again only if its
temporal provenance is still valid. The exclusive access itself does not make
old aliases dangling; an invalidating operation performed through that access
may do so.

Typical operations that require `$$&` include operations that may:

- destroy or free a referent,
- remove or replace a logical subobject,
- clear or truncate storage,
- reallocate or relocate referenced storage,
- replace an enum/optional state that owns a referenced subobject,
- reset an arena/region,
- change stored reference dependencies to a different temporal domain,
- or temporarily break an invariant that must not be observable through an
  alias.

Examples include `free`, `deinit`, `clear`, `remove`, `pop`, `truncate`, and a
`push` that may reallocate.

This distinction is central to the design: temporal dependencies may live as
hidden state of values because ordinary `$&` mutation cannot arbitrarily change
that state. A change to it happens through an exclusive `$$&` transition.


## 4. References carry hidden provenance

The source language should normally expose only:

```rg
&T
$&T
$$&T
```

The compiler may reason internally as if a reference also carried a temporal
refinement:

```text
&T @ alpha
```

`alpha` identifies the temporal provenance on which the reference depends.
Provenance and validity are distinct concepts: the provenance of a reference
normally remains the same even after it becomes invalid. Validity is a
point-in-program check that the logical identity/epoch captured by that
provenance is still current.

Conceptually:

```text
p captures R @ epoch 7

before invalidation:
    current(R) == 7
    valid(p) = true

after invalidation:
    current(R) != 7
    valid(p) = false

origin(p) is still R
```

Reference permission is separate again: `&`, `$&`, and `$$&` say what access is
allowed, not whether the referenced logical identity is still alive.

These temporal variables are compiler semantics, not ordinary nominal type
parameters. The goal is to avoid source types such as:

```text
&'a T
Holder<'a>
Graph<'arena>
Iterator<'a, T>
```

while retaining the information needed to prove safety.


## 5. Invalidation roots and logical epochs

An invalidation root is the coarse storage/ownership domain whose termination
can invalidate references into it.

Conceptually:

```text
p -> R
```

means that `p` cannot be used after the captured identity of `R` is invalidated.

Invalidation is the central temporal operation. `deinit()` is one important way
to invalidate storage, but the same model covers `remove`, `clear`, `reset`,
subobject replacement, variant changes, pool-slot reuse, and relocation when it
changes the storage identity observed by references.

The checker can therefore be understood in terms of a small core rule:

```text
reference creation
    captures a logical temporal identity

invalidation
    ends or advances that identity

reference use
    requires the captured identity to still be current
```

Automatic `deinit()` insertion is then one consumer of the same analysis: the
compiler may end a resource's identity once doing so cannot invalidate any
future safe use.

A root alone is not always precise enough. Logical objects can die while their
underlying allocation remains alive:

```rg
p := &vector[3]
vector | remove($$&_, 3)
use(p) -- invalid
```

The vector buffer may still exist, but the old element does not. The checker
therefore also needs identities/epochs for logical referents or subobjects:

```text
p -> buffer root / element epoch
```

Replacing an enum variant, clearing an optional, reusing a pool slot, deleting
a node, or replacing an inline subobject are the same class of problem.

The exact internal representation is an implementation detail; the semantic
requirement is that references are tied to the lifetime of the logical object,
not merely to the lifetime of its bytes.


## 6. Allocation defines invalidation granularity

`Allocation` is the natural bridge between allocator semantics and temporal
safety.

Conceptually, an allocation/storage abstraction must tell the compiler whether
it introduces its own invalidation domain or follows another one:

```text
self
other(storage)
```

Meaning:

```text
self
    this storage owns a distinct temporal domain

other(x)
    this storage follows the temporal domain of x
```

This relationship may be resolved transitively. It should be compiler metadata,
not a first-class `LifetimeRoot` value that users manipulate directly.

This gives two useful extremes.

Independent allocations:

```text
A -> RA
B -> RB
C -> RC
```

allow independent destruction.

Arenas/regions:

```text
node A --\
node B ----> Rarena
node C --/
```

intentionally share one coarse invalidation domain. This is especially useful
for ASTs, graphs, request storage, frames, worlds, and other object families
that naturally die together.

Coarser roots trade temporal precision for a simpler and cheaper safety model.
Programs that need independent destruction can choose more granular allocation
or handle/generation based designs.


## 7. Spatial aliasing is separate from temporal provenance

Two references can depend on the same arena while pointing to unrelated nodes.
Sharing a temporal root does not mean they alias spatially.

The checker therefore needs separate notions of:

```text
temporal provenance
    what can invalidate this reference?

spatial provenance / overlap
    what storage can this reference designate?
```

An exclusive transition on `nodeA` must not invalidate references to unrelated
`nodeB` merely because both live in `Rarena`.

Invalidating operations therefore have an invalidation footprint over logical
places/storage, not simply over a whole root in every case.

The same spatial model defines exclusive-access conflicts. While a `$$&`
capability is active, no other execution path may access a place whose spatial
footprint may overlap its exclusive footprint. Disjoint fields or objects need
not conflict merely because they share a temporal root.


## 8. Liveness is based on future uses

Reference validity should be use-based rather than tied to the lexical end of a
scope.

```rg
p := &array[0]
use(p)

array | push($$&_, value) -- allowed if p has no future use
```

but:

```rg
p := &array[0]
array | push($$&_, value)
use(p)                    -- error if push can invalidate p
```

The core condition is approximately:

```text
Uses(reference) subset-of Validity(provenance(reference))
```

This is separate from when owned values are automatically `deinit`-ialized.
Scope-exit automatic destruction can remain the base resource rule even while
reference liveness is last-use based.


## 9. Temporal dependencies belong to values, not nominal type identity

A type that stores references remains one nominal source type:

```rg
Holder#(.t: Type) : Type = (
    .ptr: &t
)
```

Two values may nevertheless carry different hidden dependencies:

```text
h1: Holder    dependencies = {Rstack}
h2: Holder    dependencies = {Rarena}
```

Argi should not require `Holder<'a>` in source merely to transport that
information.

The compiler treats the dependency information as a temporal refinement/state
attached to the value. Composite values aggregate the dependencies of the
reference-bearing state they contain.

For dynamic containers the compiler cannot enumerate an unbounded runtime set
of concrete roots. In those cases it may use a symbolic/common dependency
envelope internally. This is effectively hidden lifetime polymorphism, but it
still need not become part of the nominal source type.


## 10. Function temporal summaries

Functions must be checkable and reusable without repeatedly re-analyzing every
callee body. Each function therefore has a compiler-generated temporal summary
in addition to its ordinary source signature.

Examples:

```rg
identity(x: &T) -> &T
```

may have:

```text
return <- x
```

and:

```rg
first(v: &Vector#(.t: T)) -> &T
```

may have:

```text
return <- v.buffer
```

Mutating functions may describe post-state dependencies and invalidation:

```text
self.target.after <- target
invalidates self.buffer
```

A summary may contain, as needed:

- return provenance,
- stored/escaping dependencies,
- invalidation effects,
- storage/root effects,
- post-state temporal dependencies,
- symbolic provenance variables and relations.

Most summaries are inferred. Functions whose implementation is unavailable or
whose storage behavior crosses through raw addresses may state the small part
that cannot be recovered from the body:

```rg
release(.self: $$&Arena) -> () #invalidates(self) := { ... }
allocate(.self: $&CAllocator, .size: UIntNative)
    -> (.data: $&UInt8) #returns_fresh(data) := { ... }
allocate(.self: $&Arena, .size: UIntNative)
    -> (.data: $&UInt8) #returns_follow(data, self) := { ... }
```

`#trusted_temporal` authorizes an implementation to establish or replace hidden
dependencies through `$&`, principally during initialization. `#raw_boundary`
marks code whose pointer-to-integer operations prevent the checker from
reconstructing a store's provenance. Both are auditable unsafe boundaries, not
general permission shortcuts: ordinary code should use inferred summaries and
`$$&` for temporal transitions.

An extern function without a precise contract is handled conservatively. An
exclusive input may have its whole referent envelope invalidated, and a result
capable of carrying provenance is assumed to depend on every input capable of
carrying provenance. A contract can replace those defaults with a fresh or
followed storage root.

Internally the compiler is free to use constructs equivalent to `alpha`,
`beta`, unions, outlives constraints, or quantified provenance when necessary.
The design goal is not to remove lifetime mathematics from the compiler; it is
to keep it out of ordinary nominal source types and signatures when inference
is sufficient.


## 11. Summaries are also the incremental-compilation boundary

Callers consume temporal summaries instead of callee bodies:

```text
first:
    return <- self.buffer

foo(v):
    return first(v)

=> foo:
    return <- v.buffer
```

The compiler should be able to cache independently:

```text
ordinary/API signature
temporal summary
body/codegen
```

If a function body changes but its temporal summary does not, dependent code
need not repeat memory-safety analysis solely because of that implementation
change.

Generic/abstract summaries can remain symbolic and be instantiated/composed
when concrete implementations become known.


## 12. Abstract types keep precise provenance through monomorphization

Abstract types monomorphize by default in Argi. When a concrete implementation
is known, temporal analysis should use the precise summary of that concrete
implementation.

```text
Abstract call
    + concrete Self
    -> concrete implementation
    -> precise temporal summary
```

The abstract contract does not need to force every statically dispatched call
through a conservative lifetime envelope.

This is one reason Argi can aim to infer temporal behavior aggressively without
putting lifetime parameters in ordinary abstract source types.


## 13. Virtual types use a conservative temporal envelope

`Virtual#(Abstract)` deliberately erases concrete implementation information.
Temporal precision may be erased at the same boundary.

A safe default for a virtual method returning a reference derived from its
receiver is:

```text
return <- temporal_envelope(self)
```

The temporal envelope means everything that must remain valid for the virtual
object, including transitive hidden dependencies of its erased state. It is not
merely the storage occupied by the small virtual handle.

Concrete implementations are checked to ensure their precise temporal behavior
fits the public virtual contract.

The implemented baseline attaches the erased data reference and all of its
hidden dependencies to the Virtual value. A reference returned by an indirect
method follows that entire envelope. A `$&Self` virtual call preserves it;
`$$&Self` conservatively invalidates it. Thus dispatch cannot recover concrete
precision accidentally, but neither pointer erasure nor the vtable boundary can
hide an invalidation.

Therefore virtual safety becomes:

```text
virtual-safe
    = type-erasure-safe
    + provenance-erasure-safe
```

This intentionally makes dynamic dispatch potentially more conservative than
monomorphized dispatch. More precise explicit virtual temporal contracts may be
added only where the default envelope proves too restrictive.

The same principle applies to other erasure boundaries such as erased
callbacks, plugins, and some FFI/ABI surfaces.


## 14. Transfer preserves logical identity

`~x` transfers responsibility for the same logical value. It does not
semantically mean "copy these bytes to a new address".

For example:

```rg
x := Foo(...)
p := &x.field

y := ~x
use(p)
```

The transfer itself should not invalidate `p`.

Conceptually:

```text
before:
    x owns O
    p -> O.field

after:
    y owns O
    p -> O.field
```

Physical relocation is a separate implementation operation.


## 15. Relocation is allowed only when provenance proves it safe

The compiler may relocate a value when that relocation is not observable
through any live/internal safe reference.

```text
~x
    preserves logical identity

physical relocation
    allowed only if all relevant provenance remains valid
```

A value with no address-dependent references can move normally. A value with a
live reference to inline storage, or with a self-reference, may require stable
storage.

Internal calls pass the addresses of their input storage. A consuming
`~value` argument can therefore reuse the caller's backing storage instead of
being copied through an LLVM aggregate. Outputs are also passed as destination
addresses. Direct binding initialization, assignment, field storage, array
storage and pointer storage can therefore construct a returned value in its
final location.

Function summaries record when an output contains references into its own
destination. Such a result may use the direct destination forms above, but is
rejected when embedded in a larger value expression that would first materialize
and then relocate it. The recorded dependency paths are remapped to the caller's
destination so later subobject invalidations remain visible to the checker.

This means address stability can often emerge from provenance instead of
requiring a general source-level `Pin<T>` property.

For returns, container insertion, and self-referential construction, the
compiler may need in-place construction / destination passing so that the
object is created directly in storage that will remain stable.

Containers that store elements inline must respect the same rule: they may not
silently relocate an element while live provenance depends on that element's
address. Indirection should be used only where the chosen data structure needs
it, not imposed universally.


## 16. Copying and automatic destruction remain orthogonal

Named values used in value position follow Argi's existing value semantics:

- if the type provides `copy()`, an independent value may be produced,
- otherwise the programmer must borrow it or transfer it explicitly with `~`.

Automatic `deinit()` remains the normal resource cleanup rule for values that
still own their resources. A moved-out binding is consumed and is not
`deinit`-ialized as if it still owned the transferred value.

References/dependencies required by a value must remain valid through any
`deinit()` implementation that may use them.


## 17. Concurrency is a separate safety dimension

Multiple `$&T` aliases can be temporally memory-safe in one thread and still
race when used concurrently from multiple threads. `$&` therefore does not by
itself authorize unsynchronized cross-thread mutation.

`$$&T`, however, is intended to be usable as an exclusive capability across
execution contexts. It may be transferred to another thread/task when the type
is otherwise safe to transfer, provided the language can enforce that no
overlapping access occurs anywhere while that exclusive window is active.
Existing aliases may remain stored but are suspended from access during that
window.

For structured concurrency this can look conceptually like:

```text
parent aliases dormant
        |
        | transfer $$& capability
        v
worker has exclusive access
        |
        | worker/join ends exclusive window
        v
parent aliases may resume if still temporally valid
```

If the worker invalidates storage, old aliases remain invalid after the window
ends; if it performs only non-invalidating exclusive mutation, they may resume.
Thus concurrency reuses the same separation between exclusive access and
temporal validity.

Argi still needs separate rules/capabilities for cross-thread sharing,
synchronization, atomics, and type-level transfer/share safety. The lifetime
system alone does not make arbitrary `$&T` aliases race-free.


## 18. Design target

Argi is not trying to implement a weaker Rust lifetime checker.

The intended decomposition is:

```text
read access             -> &
aliasable mutation      -> $&
exclusive transition    -> $$&
resource transfer       -> ~
temporal validity       -> provenance + invalidation analysis
```

The compiler may internally need sophisticated temporal reasoning, including
symbolic lifetimes and effects. The user-facing target is nevertheless small:

```rg
&T
$&T
$$&T
Holder
Graph
Iterator#(.t: T)
```

rather than lifetime parameters as a normal dimension of nominal types.

The success criterion is not that the checker is theoretically simpler than
Rust's. It is that ordinary safe code remains direct and pointer-friendly while
most temporal complexity is inferred, summarized, and exposed only through
useful diagnostics when it matters.


## 19. Implementation requirements to validate in 0.2.0

The 0.2.0 implementation should validate this model against representative
cases rather than attempting every advanced corner case immediately. At
minimum, it should establish:

- `&`, `$&`, and `$$&` permissions,
- `$$&` exclusivity over accesses rather than mere alias existence,
- use-based reference liveness,
- explicit separation of provenance from current validity,
- roots plus logical/subobject invalidation,
- invalidation as the common model behind `deinit`, replacement, removal,
  reset, and relocation,
- allocation/arena invalidation domains,
- value dependency propagation,
- temporal summaries across function boundaries,
- transfer without accidental reference invalidation,
- invalidating container mutations,
- precise monomorphized abstract calls,
- a conservative virtual-reference baseline,
- and a path for transferring `$$&` exclusive access across structured
  concurrency boundaries.

If these mechanisms require temporal information to become routinely explicit
in source types, the design should be reconsidered rather than silently growing
a second Rust-like surface syntax.

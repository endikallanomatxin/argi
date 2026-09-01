# Argi safety model

This document describes the language model of temporal safety. It is
independent of the checker’s representation and deliberately uses the terms
that programmers see: places, validity roots, generations, ownership and
provenance.

## Purpose

Argi checks temporal memory validity, single ownership and destruction,
provenance of safe references, use-after-move, use-after-deinit, stale
storage generations, local-reference escape, invalid raw-to-safe reference
construction, and dependencies hidden inside opaque storage. This layer does
not by itself promise Rust-style `&mut` exclusivity, absence of mutable
aliasing, data-race freedom, or concurrency safety.

## Fundamental entities

### Place

A Place is the structural identity of storage, independent of the value held
there. Examples include `x`, `x.field`, `array[3]`, `array[i]`, and the place
reached through `pointer&`.

### Validity Root and validity domain

A Validity Root is a temporal identity. Ending it invalidates every value that
depends on it. A validity domain is the conceptual set of values governed by
one root.

Heap allocation, for example, has the following relationships:

```text
Allocation owns R
Allocation.data depends on R
```

An arena may instead own one root shared by many allocations:

```text
Arena owns Rarena
allocation1.data depends on Rarena
allocation2.data depends on Rarena
```

Ownership and validity dependency are different relations. A value may own a
root, depend on a root without owning it, or do both.

### Storage Generation

A Storage Generation is one temporal incarnation of a Place:

```text
x @ G0
deinit(x)
x = new_value
x @ G1
```

A reference made against `G0` is not revived when the same Place is reused as
`G1`; it is stale.

## The central use rule

Using a value requires that it is initialized and that every validity
dependency it carries is alive. Ending a root is not blocked merely by visible
references that depend on it:

```text
p depends on R
end R             // allowed
use(p)            // error: stale reference
```

This is intentionally different from a Rust borrow checker that prevents
many invalidations while borrows remain in scope.

## Copy, move and deinit

Copying a reference copies its validity dependencies, never its ownership.
Copying an owning value must create an independent ownership arrangement; it
must not duplicate a single destruction obligation.

```text
b = copy(a)
```

Move transfers the value facts and leaves the source moved:

```text
b = ~a
```

Move is not relocation. It does not retarget references into the old Place.
`deinit` performs the logical termination of an owning value: physical
cleanup, termination of roots it owns, and deinitialization of its Place.
Physical cleanup and temporal validity are separate concerns.

## Heap, arena and relocation

Heap allocation establishes a fresh root. Arena allocation borrows the arena’s
root, and resetting an arena ends the old generation and establishes a new
one, making references into the old generation stale.

`relocate(source, destination)` moves a representation between Places. It
does not retarget aliases already made to either Place. Owning a value is not
proof that changing its address is harmless; self-references and internal
aliases retain their original provenance.

## Opaque storage

Containers such as `DynamicArray<T>` may contain runtime slots whose individual
ownership cannot be represented precisely. An Opaque Storage Domain is then
identified by a storage Place and conservatively retains hidden dependencies.

Visible and hidden dependencies have intentionally different rules:

```text
visible reference depends on R
end R                         // allowed; later use is stale

opaque storage may contain a value depending on R
end R                         // rejected while the dependency is hidden
```

Trusted primitives form the explicit boundary for these transitions:

```text
precise ownership -> opaque storage       trusted_opaque_move_in
opaque storage -> precise ownership       trusted_opaque_move_out
opaque storage -> opaque storage           trusted_opaque_relocate
opaque slot -> destroyed slot             trusted_opaque_drop
opaque domain -> known empty domain        trusted_opaque_mark_empty
```

`trusted_opaque_mark_empty` is an assertion about occupancy. It does not free
memory, destroy slots, or terminate the storage; it only permits the checker
to forget hidden dependencies after the trusted implementation has emptied
the domain.

## Raw storage and capabilities

An integer or raw address cannot manufacture a safe reference by itself. A
Storage Capability is a consumable authorization to incorporate an acquired
physical storage region into the safe temporal model. These are distinct:

```text
physical address       where bytes happen to be
provenance              why a safe reference is valid
validity root           until when it is valid
ownership               who must end it
storage capability      who may establish that relationship
```

## Control flow and calls

The checker tracks whether Places are initialized, maybe initialized, moved or
deinitialized. Branch joins and loops conservatively combine possible states;
new storage generations remain distinct from old ones. Choices track their
active variants, and narrowing does not erase the validity facts of the
selected payload.

Each function has an inferred Safety Summary. It records required live input
dependencies, value effects, Place post-states and opaque-storage effects.
Callers instantiate these symbolic effects at their own Places and roots.
Virtual dispatch combines the effects of possible implementations
conservatively; incompatible temporal post-states therefore cannot form one
safe virtual abstraction.

`$&T` does not imply `noalias`. Calls such as `f($&x, $&x)` and
`f($&x, &x)` may be temporally safe under the current model. Exclusivity and
data-race guarantees are separate language concerns.

## Trusted boundary

An operation is trusted only when the compiler recognizes it as a Trusted
Primitive. Its name, location in `core`, or resemblance to a primitive is not
enough:

```text
safe code -> Trusted Primitive -> raw / opaque / runtime mechanism
```

## Glossary

| Concept | Question answered |
|---|---|
| Place | Where? |
| Storage Generation | Which incarnation of that Place? |
| Validity Root | Until when is it valid? |
| Ownership | Who is responsible for ending it? |
| Validity Dependency | What must remain alive? |
| Provenance | Why is this reference valid? |
| Storage Capability | Who may incorporate raw storage safely? |

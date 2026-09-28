# Argi safety model

## Purpose

Argi checks temporal memory validity, double destruction of tracked resources,
provenance of safe references, use-after-move, use-after-deinit, stale
storage generations, local-reference escape, invalid raw-to-safe reference
construction, and dependencies hidden inside opaque storage. These rules do
not promise exclusive mutable references, absence of mutable aliasing,
data-race freedom, or concurrency safety.

## Fundamental entities

### Place

A Place is the structural identity of storage, independent of the value held
there. Examples include `x`, `x.field`, `array[3]`, `array[i]`, and the place
reached through `pointer&`.

### Validity Root and validity domain

A Validity Root is a temporal identity. Ending it invalidates every value that
depends on it. A validity domain is the conceptual set of values governed by
one root.

An owning value and a reference to its resource have different relationships
to the same root:

```text
owner ends R
reference depends on R
```

Root-ending responsibility and validity dependency are different relations. A
value may be responsible for ending a root, depend on a root without ending
it, or do both. Dependency edges may alias or form cycles. Each root has at
most one ending responsibility, and those responsibilities are acyclic. This
is checker bookkeeping for resource cleanup, not an exclusivity rule for
references to the value or its Place.

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

The use check does not require all references to leave scope before a root
can end.

For a value whose validity relation is not visible in its representation,
`depend_on#(.t: T)(.value = value, .on = &owner).result` attaches the
owner's storage generation to the returned value. Its existing cleanup
responsibilities are unchanged. Using it after the owner is deinitialized is
an error, even if the value is a scalar or has passed through another function.
Ending the owner after the value's last use remains valid. This annotation does not
silently suppress cleanup or extend the owner's runtime validity.

## Value state and root-ending responsibility

A value may carry several root-ending responsibilities, dependencies on
roots it does not end, or both. Moving with `~` carries those facts to the
destination and leaves the source moved. Copying a reference carries its
dependencies but no root-ending responsibility; copying a value that ends a
root must establish an independent root for the copy.

Move is not relocation. It does not retarget references into the old Place.
An internal reference that still names a moved field cannot be dereferenced
through the destination, even while the old storage remains allocated.
`deinit` is a recognized cleanup operation. It cleans the current value,
ends roots the value is responsible for, and leaves its Place deinitialized.
Its particular resource effects also follow its body and calls. It does not
inherently end that Place's storage generation. Physical cleanup and
temporal validity are separate concerns.

## Relocation

`relocate(source, destination)` moves a representation between Places. It
does not retarget aliases already made to either Place. Cleanup responsibility
does not prove that changing an address is harmless; self-references and internal
aliases retain their original provenance.

## Opaque storage

Containers such as `DynamicArray<T>` may contain runtime slots whose individual
cleanup responsibilities cannot be represented precisely. An Opaque Storage
Domain, identified by a storage Place, conservatively retains hidden
dependencies.

Visible and hidden dependencies have intentionally different rules:

```text
visible reference depends on R
end R                         // allowed; later use is stale

opaque storage may contain a value depending on R
end R                         // rejected while the dependency is hidden
```

Trusted primitives form the explicit boundary for these transitions:

```text
tracked value -> opaque storage           trusted_opaque_move_in
opaque storage -> tracked value           trusted_opaque_move_out
opaque storage -> opaque storage           trusted_opaque_relocate
opaque slot -> destroyed slot             trusted_opaque_drop
opaque domain -> known empty domain        trusted_opaque_mark_empty
```

`trusted_opaque_mark_empty` is an assertion about occupancy. It does not free
memory, destroy slots, or terminate the storage; it only permits the checker
to forget hidden dependencies after the trusted implementation has emptied
the domain.

The storage-aware move records dependencies hidden in an opaque domain. While
a dependency remains hidden, ending its root is rejected. This set is
conservative across writes and control-flow joins; it is cleared only after
the domain is known empty. A slot must contain exactly one live value before
`trusted_opaque_drop`; dropping it twice or dropping an empty slot violates
the primitive's manual precondition.

Opaque pointers carry the structural domain Place and the storage generation
at which they were established. Reusing that Place establishes a new
generation; it never refreshes an older pointer. Relocating an opaque value
cannot retarget self-references or references into its old slot. A hidden
dependency on the storage being relocated therefore prevents that operation,
while an unrelated external dependency does not.

## Raw storage and capabilities

An integer or raw address cannot manufacture a safe reference by itself. This
includes erased references such as `&Any`; integer arithmetic cannot launder an
address back into the safe model. A Storage Capability is a consumable
authorization to incorporate an acquired physical storage region into the safe
temporal model. Fresh establishment creates a new root; inherited
establishment attaches the reference to an existing root without taking
responsibility for ending it. Establishment happens before safe aliases
escape; finding another alias does not re-root existing references. These are
distinct:

```text
physical address       where bytes happen to be
provenance              why a safe reference is valid
validity root           until when it is valid
root-ending responsibility   which value ends the root
storage capability      who may establish that relationship
```

## Control flow and calls

The checker tracks whether Places are initialized, maybe initialized, moved or
deinitialized. Branch joins and loops conservatively combine possible states;
new storage generations remain distinct from old ones. Choices track their
active variants, and narrowing does not erase the validity facts of the
selected payload.

Each function has an inferred Safety Summary. It records required live input
dependencies, value effects, Place post-states, and opaque-storage effects.
Callers instantiate these symbolic effects at their own Places and roots.
Virtual dispatch combines the effects of possible implementations
conservatively; incompatible temporal post-states therefore cannot form one
safe virtual abstraction.

`$&T` does not imply `noalias`. Calls such as `f($&x, $&x)` and
`f($&x, &x)` may be temporally safe under the current model. Exclusivity and
data-race guarantees are separate language concerns.

## Trusted boundary

An operation is trusted only when the compiler recognizes its bundled `core`
path, name, and full signature as a Trusted Primitive:

```text
safe code -> Trusted Primitive -> raw / opaque / runtime mechanism
```

Core helpers that call these primitives and maintain collection invariants
are private to bundled core modules. Their `_trusted_*` names do not grant
compiler privileges; user modules cannot call them to claim an arbitrary
view extent or initialized slot.

Temporal validity does not prove that an index or offset is inside an object.
Native array indexing checks bounds and traps on failure. Core collections
use named, fallible access functions that check their logical length. The
low-level reference-offset operations remain trusted and require a valid
range. Bounds also do not establish element identity after mutation.

Live storage is not enough to construct a safe `&T` / `$&T`: it must also have
sufficient size and alignment and contain an initialized, valid `T`.

> [!IMPLEMENTATION]
> Extraction from opaque storage does not yet reconstruct the exact
> dependencies of a reference held in an opaque value; the checker retains
> conservative storage-level dependencies instead.

## Glossary

| Concept | Question answered |
|---|---|
| Place | Where? |
| Storage Generation | Which incarnation of that Place? |
| Validity Root | Until when is it valid? |
| Root-ending responsibility | Which value ends this root? |
| Validity Dependency | What must remain alive? |
| Provenance | Why is this reference valid? |
| Storage Capability | Who may incorporate raw storage safely? |

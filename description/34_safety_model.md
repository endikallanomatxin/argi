# Argi safety model

## Purpose

Argi checks temporal memory validity, double destruction of tracked resources,
provenance of safe references, use-after-move, use-after-deinit, stale
storage generations, local-reference escape, invalid raw-to-safe reference
construction, and dependencies hidden inside opaque storage. These rules do
not promise exclusive mutable references, absence of mutable aliasing,
data-race freedom, or concurrency safety.

Runtime failures report their cause to standard error before stopping the
program. Array bounds failures, null C callback invocation, and explicit
`abort` include the source file, line, and column of the failing operation.
Reporting does not require a writer capability and does not run ordinary
cleanup after the failure.

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

A vacant record or fixed-length array becomes readable when all its fields or
statically identified elements are initialized, including nested fields.
Individual initialized fields and elements can be read before their siblings
are ready. Empty aggregates require an explicit initialization; an empty shape
alone is not evidence of an available value. Structural completeness proves
initialization without reviving ended storage generations or stale references.

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

Containers such as `DynamicArray#(T)` may contain runtime slots whose individual
cleanup responsibilities cannot be represented precisely. An Opaque Storage
Domain, identified by a storage Place, conservatively retains hidden
dependencies.

Reading a reference from an opaque slot retains the lifetime dependencies
of the stored references, including roots that have already ended. The same
check applies through function summaries. Live storage for the slot does not
prove that the referenced values remain live.

Using or destroying stored elements requires their hidden external dependencies
to remain live. This obligation follows concrete and static calls, wrappers,
and automatic cleanup, as well as virtual receiver calls. Accessing allocation
metadata or releasing backing storage alone does not use the stored elements;
its own storage and capability dependencies must still remain valid.

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

## Physical validity of references

A safe reference to `T` requires a live physical region that contains every
byte of the referenced `T`, an address aligned for `T`, and initialized
contents before a read. Lifetime, physical extent, and initializedness are
separate proofs. Establishing a temporal root does not supply the other two.

Physical provenance identifies the acquired region and the permitted subrange.
It comes from an acquisition boundary or an existing valid object, rather
than from an integer address or an editable length. In particular, changing
`Allocation.data`, `.size`, or `.alignment` cannot enlarge the physical region
that was acquired. Suballocation and reference offsets must remain inside
that region; arithmetic must not wrap while computing offsets or addresses.
Reinterpreting an address does not enlarge its permitted region or initialize
the target representation.

An ordinary `&T` certifies one live initialized object, not adjacent elements.
Ordinary element selection uses an array or initialized view carrying a bound.
Selecting a byte range or uninitialized slot does not publish a legible `T`.
Unbounded offset, raw-address establishment, and representation reinterpretation
are explicitly trusted operations. Their `trusted_*` names identify caller
obligations; the naming convention does not add an unsafe-block mechanism or
make the compiler prove those obligations.

A storage capability authorizes establishment for the storage actually
acquired. It is consumed when that storage enters a temporal domain; copying
its address does not create a second authorization. Both native page mapping
and C heap allocation are acquisition boundaries. Acquisition failure is not
a region that may be established.

Acquisition receipts carry that physical proof independently of editable
allocation metadata. `AcquiredStorage` has private address, extent, and
alignment fields; successful heap and native page acquisition create receipts.
Normal allocation or inherited-storage establishment requires such a receipt.
Allocation establishment checks its requested prefix and alignment before
publishing the temporal root. Padding outside the requested acquisition range
does not become readable storage. A receipt is move-only: establishment
consumes it, forwarding moves it, and metadata inspection borrows it.

Integer-address integration uses the explicitly trusted establishment
operations. Their caller proves acquisition, containment, and the matching
cleanup contract. Supplying a live temporal root or an integer does not
discharge those obligations.

Authorization follows address aliases across calls. A function that may consume
a known capability requires it to be available on entry; conditional consumption
makes it unavailable for a later establishment unless non-consumption is proved.
Returning an address, copying it into several outputs, or publishing it through
an input reference does not create a new authorization or revive a consumed one.
Aliases of one acquisition share its state. Separate successful acquisitions
create separate authorizations, including acquisitions performed by repeated
calls to the same function.

Uses on mutually exclusive branches are alternatives, even when the caller
supplies aliases for their inputs. Loops and recursive forwarding must not allow
one authorization to be consumed repeatedly.

An `ArrayView#(T)` or `MutableArrayView#(T)` length must describe initialized elements inside its
physical region. Checking an index against length is necessary but cannot
validate a forged region. A zero-length region contains no readable element,
and constructing a view must not require dereferencing a nonexistent first
element. `MaybeUninit#(T)` provides storage for `T`; occupancy must be proved
separately before reading or destroying a `T`.

At a trusted boundary, the caller must discharge the physical obligations
that are not proved by the compiler or checked at runtime. That obligation
includes alignment, extent, initialization for reads, and preservation of
the backing region's validity. An unrelated live root cannot make an
arbitrary address physically valid.

> [!IMPLEMENTATION]
> Temporal roots and consumption of known storage capabilities are tracked,
> but authoritative physical extents are not yet propagated through all
> reference operations. Normal establishment requires an acquisition receipt;
> native page mappings and C heap acquisition carry tracked capabilities.
> The explicitly trusted establishment operations accept integer addresses,
> including suballocator-selected ranges without tracked capabilities.
> Public low-level reference helpers therefore still rely on
> trusted caller obligations for physical validity. Reference offsets reject
> multiplication and address-addition wrap at runtime, but do not yet check
> membership in an authoritative physical range. Allocation slots check the
> target type's alignment and containment in both the public receipt and the
> private bounds certified by the allocator. Editing public fields cannot
> enlarge that range. The trusted allocator still proves that establishment
> describes acquired storage; these guards do not provide a general
> spatial-safety guarantee for arbitrary raw-pointer operations.

> [!QUESTION]
> How should external integrations import certified ranges without using the
> integer-address trusted boundary? The acquisition-receipt protocol provides
> the bundled heap and page path. An external range needs a certified owner or
> bounded region before ordinary element selection can use it; an ordinary
> `&T` alone does not supply an adjacent range.

## Control flow and calls

The checker tracks whether Places are initialized, maybe initialized, moved or
deinitialized. Branch joins and loops conservatively combine possible states;
new storage generations remain distinct from old ones. Choices track their
active variants, and narrowing does not erase the validity facts of the
selected payload.

Each function has an inferred Safety Summary. It records required live input
dependencies, value effects, Place post-states, and opaque-storage effects.
Callers instantiate these symbolic effects at their own Places and roots.
Safety contracts bound the effects allowed through virtual dispatch.
Concrete implementations must satisfy their contract independently, and virtual
calls use that contract. See `134_virtual_types.md` for dependency declarations
and the remaining implementation gaps during migration from combined summaries.

`$&T` does not imply `noalias`. Calls such as `f($&x, $&x)` and
`f($&x, &x)` may be temporally safe under the current model. Exclusivity and
data-race guarantees are separate language concerns.

Summaries preserve ordered storage observations: consuming a value and later
reading through another input requires those destinations not to overlap.
The caller checks this requirement using its actual storage identities. Two
independent inputs remain usable; an alias of the consumed incarnation stays
invalid even when the destination is reinitialized. Reading before consumption
is permitted, except when a later loop iteration can observe the ended value.
References stored in one by-value argument retain separate referent identities
and the same caller-side checks. Statically selected implementations retain these
inferred obligations at every concrete call, including forwarding calls. Their
outputs and storage effects must still satisfy the contract. Virtual safety
contracts currently reject implementations that require an unrepresented alias
obligation.
An erased `Any` anchor retains its storage-validity requirements but exposes no
stored representation; checking that anchor is not a value observation.

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

## Precision of safety effects

Safety facts retain structural fields, choice payloads, input paths and named
storage domains. Effects may be guarded by conjunctions of variants from several
inputs and outputs, including choice fields and nested payloads. A guard can
control effects on any input, output or domain. Each selected variant is a
structural condition; the model does not require a symbolic formula for every
branch in a function or an enumeration of all combinations of result tags.

Input selectors describe variants at call entry. They refer to the value or
referent before the function's effects, including for mutable-reference inputs.
Inspecting a changed input after the call does not prove its entry variant.
Output selectors describe the returned values. A mixed guard requires evidence
for every input and output selector of the same call. Partial evidence cannot
establish the conjunction, and unrelated calls cannot contribute missing terms.

Predicates over ordinary numeric values and disjointness of dynamically indexed
elements are outside this precision boundary. Source code may contain those
branches; its summaries conservatively join effects whose conditions cannot be
represented or proved. An explicit signature requiring an unsupported relation
receives a diagnostic; its promise is never silently weakened. This boundary
is structural, not a limit on the number of branches, selectors, outputs or
facts a program may contain.

Conservative joins union possible dependencies, invalidations and consumption.
They intersect guarantees of identity, preservation and initialization. They
retain ownership and cleanup obligations and never invent storage acquisition,
prolong local generations or make possibly consumed capabilities available.

An outcome proof identifies a call and the storage generation it affected.
Discrimination can establish that generation's survival through that call. It
cannot undo later writes, consumption, cleanup or invalidation. Independent
unresolved calls affecting the same generation lose their correlation
conservatively rather than gaining a guarantee that needs both results.

> [!IMPLEMENTATION]
> General summary guards represent conjunctions of entry-input and output
> selectors, with shared records for every effect dimension. Compact single-output
> partitions retain their effect records alongside the conservative fallback and
> are matched directly during contract checks. General conditional contracts can
> be checked against complete guarded summaries; proving only a stricter subset
> of the declared condition
> is insufficient. Existing output contracts use this proof path after concrete
> domain resolution; unreachable output partitions have vacuous guarantees.
> Stable terminal matches and branches can infer joint structural entry/input
> and output conditions for dependency provenance. Contract `on` clauses accept
> named inputs and outputs, including nested conjunctions and permissions on a
> different output. Reference-input tags are captured before call effects;
> later reads or mutations cannot establish the entry condition.
> The caller selects entry-only effects before execution and refines returned
> dependencies once all output terms from the same call are known. Copies retain
> correlation; overwritten values and independent calls do not. Straight-line
> wrappers can forward the exact outputs of one call while preserving their
> input/output coordinates. Reassignment, unknown control flow, additional
> effects and nontrivial cleanup keep the unconditional summary.
> General guards carry complete effect records. Payload refinement changes
> dependencies only; it never creates ownership, acquisition receipts or a new
> storage generation. Generation and opaque-state refinement retain the existing
> single-output/payload-path proof rules. Effects requiring several independent
> result correlations remain conservative, and joint conditional consumption or
> relocation is rejected because cleanup also requires exact caller identities.
> Conditional hidden retention and selectors through arbitrary output fields
> require further implementation. These restrictions are structural proof
> boundaries, not configurable complexity budgets.

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

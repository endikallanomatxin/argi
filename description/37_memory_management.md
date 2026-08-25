# Memory management and temporal safety

Argi combines deterministic value cleanup with static checks against dangling
safe references. The model has four orthogonal parts:

```text
values       copy, move, deinit, replacement
places       validity and initializedness
temporal     roots and dependencies
resources    cleanup responsibilities
```

The compiler tracks these facts structurally. Ordinary programs do not name
lifetime parameters or write temporal contracts.

## References

Argi has two safe reference permissions:

```rg
&T       -- read
$&T      -- read and write
```

`$&T` is aliasable. It does not imply ownership, exclusivity, `noalias`, the
right to end a lifetime, or special provenance authority. In sequential code,
several `$&T` values may refer to the same object and may be passed together.
Likewise, an `&T` and a `$&T` may coexist.

If an ABI, optimizer or concurrency feature needs exclusivity, that is a
separate capability at that feature's boundary, not a third reference kind.
References are copyable views: copying one duplicates its permission and
dependency, never cleanup responsibility.

## Places and initializedness

A place is stable storage such as a binding, struct field, array element or
dereferenced location. The checker distinguishes:

- whether the place is valid;
- whether it is initialized, moved, or deinitialized;
- which cleanup responsibilities its current value contains.

A field place may remain valid after its old value is deinitialized. A
reference to that place and a reference into the old value's backing storage
therefore have different dependencies. Struct fields are distinct places, so
writing `s.b` does not invalidate `&s.a`. Dynamic indexing and containers may
be handled conservatively when stability is not cheap to establish.

## Roots and dependencies

A root is only a temporal validity domain:

```text
reference -> R
use(reference) requires alive(R)
```

`fresh` establishes a new independent root. `inherit R` uses exactly root R;
it means equality of validity domains, not merely a shorter lifetime. An arena
can therefore establish all allocations in one root without per-object IDs,
epochs or generations.

Dependencies do not keep roots alive. A reference binding may remain in scope
after its root ends; a later use is rejected. Aggregates carry dependencies
structurally and different fields may depend on different roots. Provenance is
carried by typed references, not hidden in ordinary integers.

## Cleanup responsibility

A fresh resource has one responsibility for ending its root and performing its
cleanup. Root identity and cleanup responsibility are distinct: a root says
when references are valid; a responsibility says which value performs
teardown. A value may contain zero, one or several responsibilities. The same
nominal type may contain one when independently allocated and none when backed
by an arena.

The reference graph may alias and contain cycles. The cleanup-responsibility
structure must be deterministic and acyclic. Cyclic objects with a grouped
lifetime naturally depend on one arena root; teardown follows the arena's
cleanup structure, not the reference cycle.

## Move and copy

`~source` moves a value: the source becomes moved/uninitialized and the
destination receives its fields, references, dependencies and contained
cleanup responsibilities. Roots keep their identity. References into a
resource still depend on the same root after the responsible value moves.
Using the source again is an error.

Function results may be built directly in destination storage. This preserves
stable storage for address-dependent results without changing move semantics.

Copy creates a semantically independent value. It never duplicates the
responsibility for the same fresh root, but may allocate resources and create
new roots. Copying an owning String backed by `R1` may create `R2`; copying a
view duplicates only its dependency.

Allocator needs of `copy` are normal inputs. Resolution uses:

1. an explicit argument;
2. a compatible value found by `#reach`;
3. a compile-time error.

There is no automatic fallback to the source's allocator. Structural copies
compose field copies and their normal arguments.

## Deinit and replacement

`deinit(value)` tears down responsibilities contained by the current value and
may leave its place deinitialized. Effects are inferred from its body and
callees; its name has no special invalidation meaning. Deinitializing an
independently allocated String can end its buffer root. Deinitializing an
arena-backed value does not end the arena root when it contains no such
responsibility.

Replacement is cleanup followed by a move into the same stable place:

```text
place = ~new_value
    clean old responsibilities
    move new value into place
    keep place initialized
```

A reference to the place may remain valid while a reference into ended backing
storage becomes invalid.

Auto-deinit locates responsibilities statically in bindings and fields. It
does not invent an enumeration of dynamic objects. Regions can clean arena
storage as a group; external fresh resources require an owner or runtime
structure that can enumerate them.

## Raw pointers

`RawPointer<T>` represents an address outside Argi's normal temporal
guarantees. Allocators, FFI, OS APIs, runtimes, intrinsics, MMIO and assembly
use this boundary. A foreign `T*` is raw unless its importer establishes a
specific safe contract.

```text
RawPointer<T> -> establish fresh       -> safe reference + responsibility
RawPointer<T> -> establish inherit(R)  -> safe reference depending on R
```

The destination type determines `&T` or `$&T`. Establishing `inherit` creates
no right to end R. These operations form a small privileged boundary. An
ordinary pointer-to-integer-to-pointer round trip does not preserve safe
provenance.

## Allocation and grouped lifetime

Physical allocation and lifetime policy are separate:

```text
backing allocator -> raw storage -> choose fresh or inherit -> safe reference
```

`ArenaAllocator(backing)` gets chunks from a caller-selected allocator and
establishes its allocations in one common arena root. Reset or deinit ends that
root and releases backing storage. Individual arena-backed values do not.

Logical detach may remove an object while arena storage and aliases remain
valid. Immediate individual deletion with persistent aliases needs a separate
runtime abstraction such as a generational handle; handles are not the normal
reference representation.

## Interprocedural facts

The compiler infers and composes summaries for returned dependencies, fresh
outputs, ended roots, dependency changes, moves, deinitialization, replacement
and destination construction. Loops, recursion, dynamic containers and opaque
dispatch are conservative.

Only raw, intrinsic and foreign boundaries may state facts that cannot be
derived. Trust belongs in establishment/runtime primitives, not ordinary safe
functions. Argi favors structural precision and a simple acceptance rule over
universal runtime tracking or Rust-style borrowing.

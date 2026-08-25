# Memory management

Argi combines ordinary value semantics with explicit references and structural
temporal checking. Storage, validity, dependencies, and cleanup are separate
concepts; no reference qualifier encodes all four.

## Values, copy, and move

A value contains its fields, references, temporal dependencies, and cleanup
responsibilities. Named values used by value request a semantically independent
value. Trivial values copy directly. Resource types provide `copy` when
independence requires work. Its allocators are ordinary arguments: explicit
arguments have priority and omitted defaults may resolve through `#reach`.

Copying a reference or non-owning view copies its dependency, never a cleanup
responsibility. An owning copy creates independent resources and roots rather
than duplicating responsibility for an existing root.

`~value` moves the complete value out of its place. The source becomes moved;
the destination receives its dependencies and responsibilities. Roots keep
their identity. A moved source cannot be used or cleaned a second time.

## References

- `&T` grants read permission.
- `$&T` grants read and write permission.

Both may have aliases. Multiple `$&T` references and mixed `&T`/`$&T` aliases
may coexist in sequential code. Mutability does not imply ownership,
exclusivity, `noalias`, cleanup authority, or authority to end a lifetime.
Concurrency and noalias features establish additional rules at explicit
boundaries.

## Places and initializedness

A place identifies stable storage. Struct fields and statically known array
elements are distinct projections. Initializedness is one of initialized,
moved, or deinitialized, independently of whether the place remains valid.

Replacement cleans the old value and moves a new value into the same place.
The place survives. A reference to the place therefore remains valid, while a
view of an old contained resource requires that resource's root to remain live.

Dynamic containers use conservative spatial rules. Mutation that may move
inline elements can invalidate references to their slots. A reference value
copied out of a slot keeps the referenced object's root, not the container's
backing root.

## Roots and dependencies

A root is a temporal validity domain. Using a reference requires its root to be
alive. A dependency does not keep a root alive, so a reference binding may stay
in scope after root end; its later use is the error.

- `fresh` creates an independent domain.
- `inherit R` uses exactly domain `R`.

Inheritance is common identity, not merely a shorter lifetime. Arena objects
can share one root without universal object IDs, epochs, or generations.

Dependencies are structural: aggregate fields may depend on different roots.
The reference graph permits aliases, cycles, and cross-root cycles. Ending one
root invalidates only uses that depend on it; independent fields and objects in
other live roots remain usable.

## Cleanup responsibilities

A cleanup responsibility is the unique obligation or capability that cleans an
independent resource and, where appropriate, ends its fresh root. It is not the
root. A value may carry zero, one, or several responsibilities while any number
of aliases merely depend on the roots.

Move transfers responsibilities. Reference copy does not. The responsibility
structure is deterministic and acyclic, independently of the arbitrary
reference graph. Argi does not infer destruction order from reference cycles or
provide implicit tracing, reference counting, or SCC destruction.

## Deinitialization and replacement

`deinit` tears down resources carried by the current value and may leave its
place deinitialized. It does not inherently end the place's root. Effects come
from the body and summaries of called operations, not from the function name.

An independently backed String carries responsibility for its buffer. An
arena-backed String does not carry responsibility for the arena, so cleaning
that String cannot end the arena.

`AutoDeinitBinding` and `AutoDeinitField` enumerate statically located
responsibilities on normal and error exits. They do not claim to enumerate
arbitrary runtime allocations. Arena-inherited storage can be cleaned in bulk;
external fresh resources need an enumerable owner or individual cleanup.

## Raw memory and safe views

`RawPointer<T>` is a typed address outside normal temporal guarantees, used at
allocator, FFI, OS, syscall, assembly, MMIO, runtime, and intrinsic boundaries.
Foreign pointers enter as raw memory rather than gaining a safe lifetime
implicitly.

A small privileged boundary establishes `&T` or `$&T`:

- fresh establishment creates a root and its responsibility;
- inherited establishment attaches to an existing root without acquiring its
  responsibility.

Rooting is decided before safe aliases escape. Storage is not dynamically
re-rooted by discovering every alias.

`UIntNative` is only an integer and has no hidden provenance. StringView,
ArrayView, and iterators store typed references. Typed offset and reinterpret
operations explicitly preserve dependencies; integer arithmetic is not the
normal safe traversal mechanism.

## Allocation and grouped lifetime

Physical allocation and temporal policy are separate:

```text
allocator -> raw storage -> establish fresh / inherit R -> safe reference
```

An allocator determines how bytes are obtained and returned. Root
establishment determines their validity domain.

`ArenaAllocator(backing_allocator)` composes a caller-selected physical
allocator with grouped lifetime. Its safe allocations inherit one arena root;
reset or deinitialization ends that root and releases backing blocks. Cleaning
an individual arena-backed child does not end the arena. Logical detach need
not free storage, so aliases can remain valid until grouped cleanup.

Immediate individual deletion with persistent aliases belongs in an explicit
runtime abstraction such as a generated handle, not universal reference
machinery.

## Interprocedural checking

After semantizing, the compiler infers summaries from function bodies. They can
describe output dependencies, fresh outputs, responsibility transfer,
root-ending operations, deinitialized inputs, replacement, and conservative
dynamic-slot invalidation. Calls compose these facts; branches and loops use
conservative joins and fixed points.

Ordinary safe code writes no temporal contracts. Trust is confined to a small
set of opaque raw, foreign, and intrinsic primitives. The checker prefers
simple conservative rejection over complex proofs: using a reference requires
every structurally recorded dependency to name a live root.

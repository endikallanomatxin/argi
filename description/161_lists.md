# Lists

## Native fixed arrays

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
```

A positional literal initializing an unannotated binding infers a fixed array
from its length and homogeneous element types. Integer and floating-point literals
use their normal defaults, `Int32` and `Float32`:

```rg
values := (1, 2, 3)           // [3]Int32
matrix := ((1, 2), (3, 4))   // [2][2]Int32
```

An explicit type or a function parameter supplies the expected type before
literal defaults are considered. For example, `[2][2]Int64` gives each numeric
element an `Int64` context. Inference does not widen heterogeneous elements
or turn rows of different lengths into a common array type. Empty literals,
including empty rows in nested literals, require an expected element type.

Array initializers must match every declared dimension exactly. An annotation
does not pad missing elements or reshape nested literals. References preserve
the source array's shape: `&[3][3]Int32` cannot be used as `&[2][2]Int32`.

`[N]T` is the native fixed array type. Native bracket types represent fixed
arrays only; slices and views are library abstractions, not native array types.
Library collection access uses named operations rather than overload sets.

Native fixed-array indexing follows the language-wide place model:

```rg
arr[i]      -- value access
&arr[i]     -- borrowed read-only access
$&arr[i]    -- borrowed mutable access
arr[i] = x  -- assignment through the indexed place
```

## Array views

Views are library abstractions. The language has no native slice type.
`ArrayViewRO` and `ArrayView` provide non-owning views of proven
contiguous storage. A safe constructor derives the extent from its source;
pointer-and-length construction belongs to trusted code.

The pointer and length fields are private. `array_view#(.t: T)(.data = $&element)`
creates a one-element view; `array_view#(.n = N, .t: T)(.array = $&array)`
derives the length from a fixed `[N]T`. The read-only constructors use
`array_view_ro` and read-only references in the same way. Zero-length fixed
arrays produce empty views without establishing an element reference. An
empty view has length zero, rejects every index, and has no element pointer;
`data` requires a nonempty view and aborts otherwise. Zero-length bulk-copy
and stream operations do not require an element pointer.

A pointer to one element does not establish the extent of a larger region.
Private core helpers accept an explicit length only where the implementation
knows the backing region is live and large enough. User modules cannot call
these helpers. View indexing checks the recorded length; it does not discover
physical bounds from a raw pointer.

`slice(.self = &view, .start = start, .count = count)` derives a view of a
subrange, preserving its access mode and backing lifetime. It rejects
`start > length` or `count > length - start`, avoiding overflow in a sum of
indices. An empty subrange at the end is valid and carries no element
reference. A nested slice cannot enlarge its source's extent.

`array_view#(.t: T)(.array = $&collection)` and its read-only counterpart
borrow the initialized prefix of a `DynamicArray`. Spare capacity is excluded.
The private allocation receipt is maintained by the collection using the
allocator contract; the backing allocator must provide live storage of the
requested extent and alignment. These constructors do not turn a caller's
arbitrary pointer or edited allocation receipt into a proven range.

A nonempty dynamic-array view depends on both its backing storage and the
collection's shape generation. Successful append, pop, insert, remove, and
capacity growth invalidate existing views, including their derived subranges
and element references. The same rule applies to direct element loans from
`get_ro_ref`, `get_rw_ref`, and the public element-pointer operations, and to
elements borrowed through collection iterators. This conservative contract applies even when an append
does not reallocate. Replacing an element through `DynamicArray.set` also invalidates existing
content loans, views, and iterators, even though the length does not change. Owner cleanup and backing-arena reset invalidate its storage.
A fresh view, element reference, or iterator can be borrowed after a structural
change. Empty views contain no
element reference and have no backing-storage dependency.

The view remains non-owning regardless of how its backing region is stored.

> [!IDEA]
> Strided views could support indexing non-contiguous elements, such as a
> matrix column or an image channel. Multidimensional views over nested arrays
> could derive their extents and strides from the source and allow indexing by
> dimension without copying. For example:
>
> ```rg
> view ::= array | slice(_, 2, 5)
> column ::= array | slice(_, 2, 5, .stride = 2)
> plane ::= array | slice(_, ((0, 10), (0, 20)))
> ```
>
> A multidimensional slice might take one range per dimension, and indexing
> might take one index per dimension. Nested list literals could supply ranges.
> Sentinel-terminated views could serve C strings and similar protocols.
> Construction, bounds, and validity rules for these views remain open, as does
> whether a view stores a pointer to its first element or a borrowed window
> into its source. Retained views would need separate lifetime rules from
> today's non-owning views.

## Dynamic arrays

### `Allocation`

`Allocation` should be the low-level owning heap base used by dynamic list-like
types.

It owns raw bytes, not typed list semantics by itself.

List structures such as dynamic arrays should layer their own length, capacity,
element type, and indexing rules on top of an `Allocation`.

### `DynamicArray#(.t: Type)`

It uses `Allocation` internally, together with metadata such as length,
capacity, and element type.
Only slots below `length` contain initialized `T` values. Capacity-only slots
are addressed through `MaybeUninit<T>` handles inside trusted core operations;
the named safe access functions check `index < length` at runtime.
`l ::= DynamicArray#(.t: Int32)(.capacity = 3)`

The `_allocation`, `_length`, and `_capacity` fields are private to the lists
module. Code in other modules reads the logical length and capacity through
`length(.self = &l).count` and `capacity(.self = &l).count`. It cannot assign
those fields or fill them with a struct literal; `init` maintains their shared
invariant.

`DynamicArray` provides explicit `copy()` for infallibly copyable elements and
for elements implementing `FalliblyCopyable`. The latter obtains the element's
associated error reasons from its abstract implementation and combines them
with `..out_of_memory`. Each element is copied independently; a fallible copy
rolls back the completed prefix before releasing the new backing allocation.

`DynamicArray` access uses named core operations:

- `get(index)` for value access
- `get_ro_ref(index)` for borrowed read-only access
- `get_rw_ref(index)` for borrowed mutable access
- `set(index, value)` for assignment

All four operations are fallible because an index may be outside the
collection's logical length. Value access copies a named element implicitly
only when its type implements `ImplicitlyCopyable`; other duplication uses
`copy(...)`.

## Other core list families

The core collection library includes these families alongside `DynamicArray`:

- `PackedArray`: elements packed at widths such as 10 or 12 bits.
- Singly and doubly linked lists.
- `Rope`: a sequence assembled from smaller segments.

> [!IMPLEMENTATION]
> These core list families are not implemented yet.

> [!QUESTION]
> Define their constructors, allocator requirements, and which list abstracts
> each family implements.

## Iteration

Iteration follows the same access-mode split, but at the iterable layer rather
than the iterator layer:

- `Iterable#(.t: T)` for `for item in arr`
- `ROPointerIterable#(.t: T)` for `for & item in arr`
- `RWPointerIterable#(.t: T)` for `for $& item in arr`

The iterator contract itself stays unified:

```rg
Iterator#(.t: T)
```

That means borrowed iteration still uses `next(...)`, but on iterators whose
item type is `&T` or `$&T`. Dynamic-array iterators retain a private borrowed
view and cursor. Structural changes invalidate their element access, including
references previously returned by `next`; writing an element value preserves
iteration. Exhausted `next` aborts before constructing an element reference.
Length/cursor metadata alone does not read an element. User modules cannot
forge the private iterator state or use internal transfer-only pointer helpers.

> [!QUESTION]
> Define transfer-style iteration and the ownership of consumed iterators
> before specifying `for ~ item in arr`.

## List abstracts

- `Indexable<T>` requires `length` and fallible `get_ro_ref`.
- `IndexableMutable<T>` also requires fallible `get_rw_ref`.
- `IndexableValue<T>` adds fallible `get` for implicitly copyable elements.
- `Resizable<T>` specifies fallible `push`, `pop`, `insert`, and `remove`.

These named contracts are defined in `core/lists/List.rg`. Native `[N]T` uses
built-in `[]`; pass an initialized array view to capability-based algorithms.

## Collection capabilities

Collection algorithms can accept the named capabilities `Indexable<T>`,
`IndexableMutable<T>`, `IndexableValue<T>`, and `Resizable<T>`. Public indexed
operations return an `Errable` with `out_of_bounds`; value reads require
implicitly copyable elements. Borrowed reads support owning elements without
copying them.

`DynamicArray<T>` supplies read-only and mutable indexed borrowing and
resizing. `ArrayView<T>` supplies read-only and mutable indexed borrowing;
`ArrayViewRO<T>` supplies read-only borrowing. All three supply value reads
when `T` is implicitly copyable. Views are non-owning and do not resize.

## Equality search

`find(.self, .value)` and `contains(.self, .value)` accept a borrowed
`Indexable<T>`. Elements must be implicitly copyable and provide compatible
`==` comparison. Search allocates nothing and does not mutate the collection.
`find` returns the first matching logical index as `?UIntNative`, or `none`;
`contains` returns a `Bool`. Empty collections never access an element.
The returned index does not borrow storage, but a subsequent structural change
can make it stale. Search for owning elements needs a separate borrowed equality
contract; these helpers do not copy ownership or introduce predicate callbacks.

## Reversing collections

`reverse(.self)` accepts a mutable `IndexableMutable<T>` with implicitly
copyable elements. It reverses logical element order in place, using linear
time, constant auxiliary space, and no allocation. Empty and singleton
collections are unchanged. Native arrays participate through mutable views;
a subrange view reverses only that range.

The algorithm exchanges values through indexed mutable references. It neither
resizes storage nor calls structural collection operations. Existing element
references and views retain their storage lifetimes and still designate the
same positions, whose values can change. The collection must keep its length
and provide valid indexed references throughout the operation. Distinct
logical positions must be independently replaceable: writing through an
indexed reference replaces only that position, rather than changing other
logical elements through overlapping storage.

Owning elements need a separate exchange contract; copying their values to
implement reversal would duplicate ownership.

## Ordering policies

`OrderPolicy<T>` provides `less(.self, .left, .right) -> Bool` for implicitly
copyable elements. It defines a strict weak order: no value is less than
itself, less-than is transitive, and equivalence is transitive. Two elements
are equivalent when neither is less than the other; this need not coincide
with their `==` operator or complete record equality.

Algorithms borrow a policy instance explicitly as `.order`. Its answers must
remain consistent throughout an operation, and it must not mutate the
collection or the backing data used for comparison. Applications can supply
descending orders and comparisons by selected record fields.

Core supplies `Int32OrderPolicy`, `UIntNativeOrderPolicy`, and
`StringViewOrderPolicy`. String views use lexicographic unsigned-byte order,
including embedded NUL bytes; a shorter equal prefix precedes a longer one.
Comparison reads borrowed bytes and does not acquire ownership. This order
performs no locale, Unicode normalization, or case folding. Float ordering
requires an explicit policy that accounts for NaNs; there is no implicit
floating-point ordering policy.

## Binary search

`binary_search(.self, .value, .order)` reads an `Indexable<T>` of implicitly
copyable elements that is already sorted by the supplied policy. It returns
the first policy-equivalent element's index as `?UIntNative`, or `none`.
Equivalence means that neither element is less than the other. Empty
collections return `none` without accessing an element.

Search uses logarithmically many indexed reads and comparisons, constant
auxiliary space, and no allocation or mutation. The collection's indexed
access cost determines total runtime. The sorted precondition is not checked
by a linear scan; results are unspecified when it is violated. The returned
index has no storage lifetime and can become stale after mutation.

## Sorting collections

`sort(.self, .order)` accepts a mutable `IndexableMutable<T>` of implicitly
copyable elements. It orders values in place according to the explicit policy,
using iterative heapsort. Worst-case indexed operations and comparisons are
O(n log n), auxiliary space is constant, and the algorithm does not allocate
or recurse. Indexed access and policy comparison costs determine total runtime.
Empty and singleton collections require no element exchange.

Sorting preserves every element and the collection's length. It is not stable:
policy-equivalent elements can change relative order. The collection and policy
must satisfy the same indexed-access and comparison contracts throughout the
operation; the algorithm does not validate a policy's ordering laws.

Like `reverse`, sorting exchanges copied values through mutable references and
does not replace or resize backing storage. Existing references and views
remain live and designate their original positions, whose values can change.
A native array or a subrange participates through its mutable view. Read-only
views cannot be sorted. Owning elements require a separate exchange contract.

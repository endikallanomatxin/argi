# Lists

## Native fixed arrays

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
```

> [!IDEA]
> A collection literal such as `(1, 2, 3)` could infer a library list type
> from its elements or an expected type, instead of requiring an explicit
> `List#(.t = Int32)(1, 2, 3)` constructor. Its distinction from struct and
> native array literals needs a rule.

`[N]T` is the native fixed array type. Native bracket types represent fixed
arrays only; slices and views are library abstractions, not native array types.
Library collection access uses named operations rather than overload sets.

> [!QUESTION] Find a way to define the length automatically.
> Perhaps `[?]T` could let the compiler calculate it.

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
item type is `&T` or `$&T`.

> [!QUESTION]
> Define transfer-style iteration and the ownership of consumed iterators
> before specifying `for ~ item in arr`.

## List abstracts

- `Indexable<T>` requires `length` and fallible `get_ro_ref`.
- `IndexableMutable<T>` also requires fallible `get_rw_ref`.
- `IndexableValue<T>` adds fallible `get` for implicitly copyable elements.
- `Resizable<T>` specifies fallible `push`, `pop`, `insert`, and `remove`.

These named contracts are defined in `core/lists/List.rg`. `DynamicArray` and
`ArrayView` expose corresponding operations, but `core` does not yet declare
that they implement these abstracts. Native `[N]T` uses built-in `[]` and does
not acquire an `Indexable` implementation through operator overloading.

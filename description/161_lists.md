## Lists

### Owning constructs

#### Native fixed array `[N]T`

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
```

`[N]T` is the native fixed array type. Native bracket types represent fixed
arrays only; slices and views are library abstractions, not native array types.
Collection access uses named operations rather than overload sets.

> [!TODO] Pensar una forma de definir longitud de forma automática.
> Igual `[?]T` para que el compilador lo calcule.


#### `Allocation`

`Allocation` should be the low-level owning heap base used by dynamic list-like
types.

It owns raw bytes, not typed list semantics by itself.

List structures such as dynamic arrays should layer their own length, capacity,
element type, and indexing rules on top of an `Allocation`.



#### `DynamicArray#(.t: Type)`

It uses `Allocation` internally, together with metadata such as length,
capacity, and element type.
Only slots below `length` contain initialized `T` values. Capacity-only slots
are addressed through `MaybeUninit<T>` handles inside trusted core operations;
the named safe access functions check `index < length` at runtime.
`l ::= DynamicArray#(.t: Int32)(.capacity = 3)`

`DynamicArray` provides explicit `copy()` for infallibly copyable elements and
for elements implementing `FalliblyCopyable`. The latter obtains the element's
associated error reasons from its abstract implementation and combines them
with `..out_of_memory`. Each element is copied independently; a fallible copy
rolls back the completed prefix before releasing the new backing allocation.

Native fixed-array indexing follows the language-wide place model:

```rg
arr[i]      -- value access
&arr[i]     -- borrowed read-only access
$&arr[i]    -- borrowed mutable access
arr[i] = x  -- assignment through the indexed place
```

`DynamicArray` access uses named core operations:

- `get(index)` for value access
- `get_ro_ref(index)` for borrowed read-only access
- `get_rw_ref(index)` for borrowed mutable access
- `set(index, value)` for assignment

All four operations are fallible because an index may be outside the
collection's logical length. Value access copies a named element implicitly
only when its type implements `ImplicitlyCopyable`; other duplication uses
`copy(...)`.

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

Transfer-style iteration and `for ~ item in arr` remain deferred beyond the
0.1 cut.


#### LengthedArray (capacidad fija en stack, len runtime)

`StaticVec#(.t, .n) = (.data:[n]t, .len:Int)`


#### PackedArray (enteros de b bits)

Empaqueta, p.ej. u10, u12.

`PackedArray#(.bits:Int) = (...)`


#### LinkedList

#### Rope


### Reference constructs

#### Library views

Views are library abstractions. The language has no native slice type.

```
ListViewRO#(.list_type: Type, .list_value_type: Type) : Type = (
    .list: &list_type,
    .start: UIntNative,
    .length: UIntNative,
)

ListViewRW#(.list_type: Type, .list_value_type: Type) : Type = (
    .list: $&list_type,
    .start: UIntNative,
    .length: UIntNative,
)
```

Views should stay:

- lightweight,
- non-owning,
- explicit,
- and cheap to copy as descriptors.

Copying a view copies only the descriptor. It never turns the view into an
owner of the underlying data.

The view may still be modeled as a borrowed window into a collection, not
necessarily as a raw pointer to the first element. The important point is the
same either way: the view stays non-owning.

That should stay true even if later there are explicit retained-view mechanisms
such as `keep`.


##### View indexing

`my_array | slice(2, 5)`
`my_array | slice(2, 5, .stride=2)`

#### Sentinel slice

`[null-terminated]T` o `SentinelSlice#(.t: Type, .sentinel: t)`

Slice con sentinela (terminado)
Ideal C-strings u otros protocolos.

#### Strided slices

Para vistas de columnas, canales de imagen, etc.
`StridedSlice#(.t) = (.ptr:$&t, .len:Int, .stride:Int)`


#### ND Slices

> [!TODO]

Idea:

```
l | slice (0, 10)  -- 1D slice
l | slice (((0, 10), (0, 20)))  -- 2D slice
```

> [!CHECK]
> La list abstract type podría darse cuenta de que list literals anidados la
> cumplen?


### List Abstracts

- `Indexable<T>` requires `length` and fallible `get_ro_ref`.
- `IndexableMutable<T>` also requires fallible `get_rw_ref`.
- `IndexableValue<T>` adds fallible `get` for implicitly copyable elements.
- `Resizable<T>` specifies fallible `push`, `pop`, `insert`, and `remove`.

These named contracts are defined in `core/lists/List.rg`. `DynamicArray` and
`ArrayView` expose corresponding operations, but `core` does not yet declare
that they implement these abstracts. Native `[N]T` uses built-in `[]` and does
not acquire an `Indexable` implementation through operator overloading.

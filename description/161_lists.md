## Lists

### Owning constructs

#### Array `[N]T`

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
-- is the same as
l : Array#(.n = 3, .t: Int32) = (1, 2, 3)
```

`Array#(.n = ..., .t: ...)` is the explicit canonical form. `[N]T` is the
idiomatic sugar. Positional generic arguments may be allowed later, but the
current documentation uses named arguments.

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
`l ::= DynamicArray#(.t: Int32)(.capacity = 3)`


#### LengthedArray (capacidad fija en stack, len runtime)

`StaticVec#(.t, .n) = (.data:[n]t, .len:Int)`


#### PackedArray (enteros de b bits)

Empaqueta, p.ej. u10, u12.

`PackedArray#(.bits:Int) = (...)`


#### LinkedList

#### Rope


### Reference constructs

#### Views / slices

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

- Indexable#(T) → lectura indexada: len() y get[].
- IndexableMutable#(T) → añade set[].
- Resizable#(T) → añade push, pop, insert, … (solo para los dinámicos).

`[N]T`, `Array#(.n = N, .t: T)`, `ListViewRO#(.list_type = X, .list_value_type = T)` y
`ListViewRW#(.list_type = X, .list_value_type = T)` cumplen `Indexable`;
los que tengan memoria mutable cumplen `IndexableMutable`; y solo `DynamicArray#(.t: T)`
(dinámico) cumple `Resizable`.

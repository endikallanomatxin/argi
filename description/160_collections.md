# Collection types

The only non-library collection types are Arrays. The rest are structs defined
in the core library.

> [!NOTE] Why cannot arrays be defined in the core library? I've tried, but it
> seems that implementing them always requires some kind of `[]Byte` buffer.
> LLVM already has a `[N x %T]` type, that has some checks and information for
> optimizations. It is best to use it directly.

Available literals:

- List literals

```
l := (1, 2, 3)
```

- Map literals

```
m := ("a"=1, "b"=2)
```


## Lists

### Owning constructs

#### Array `[N]T`

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
-- is the same as
l : Array#(Int32, 3)((1, 2, 3))
```

> [!TODO] Pensar una forma de definir longitud de forma automática.
> Igual `[?]T` para que el compilador lo calcule.


#### `Allocation#(.t = [N]T)`

Similar to basic Array, but using an allocator, still static size.

It implements the `List` interface.
una instanciación concreta `Allocation#(.u = [N]T)` puede cumplir tu interfaz de
listas, aunque el genérico `Allocation#(.u: Type)` (sin fijar) no lo haga.



#### `DynamicArray#(.t: Type)`

It uses `Allocation#(.u = [N]T)` internally, and grows as needed.

`l := DynamicArray#(Int32)((1, 2, 3), my_allocator)`


#### LengthedArray (capacidad fija en stack, len runtime)

`StaticVec#(.t, .n) = (.data:[n]t, .len:Int)`


#### PackedArray (enteros de b bits)

Empaqueta, p.ej. u10, u12.

`PackedArray#(.bits:Int) = (...)`


#### LinkedList

#### Rope


### Reference constructs

#### Slices `R[]T` or `Slice#(.t: Type)`

```
RSlice#(.t: Type) : Type = (
    .data: &t,
    .length: Int32,
)

RWSlice#(.t: Type) : Type = (
    .data: $&t,
    .length: Int32,
)
```

> [!TODO] Maybe we can define them as only created from an already existing array?

> [!IDEA] Igual slice podría ser Slice#(.t: Type, .m: Mutability = ..R)?
> Donde Mutability puede ser R, RW, o ERW (exclusive)


##### Slice indexing

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

`[N]T`, `RSlice#(T)`, `RWSlice#(T)` y `Allocation#([N]T)` cumplen `Indexable`;
los que tengan memoria mutable cumplen `IndexableMutable`; y solo `DynamicArray#(T)`
(dinámico) cumple `Resizable`.


## Maps

## Sets

## Graphs

## Queues

### RingBuffer (circular, fijo o dinámico)
Para colas, audio, telemetría.
RingBuffer#(.t) = (.ptr:&t, .cap:Int, .head:Int, .tail:Int)

### Deque (doble extremo, dinámico)
Generaliza ring buffer con crecimiento.
Deque#(.t) = (.ptr:&t, .len:Int, .cap:Int, .front:Int, .alloc:&Allocator)


---

More info on collection types in `../library/collections/`

---

### SoA / AoS

> [!TODO]

---

### Iterators

- basic iterator
- zipping iterator
- enumerating iterator
- sliding window iterator


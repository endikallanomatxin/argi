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

#### StackArray `[N]T`

Fixed-size arrays:

```
a : [3]Int32 = (1, 2, 3)
-- is the same as
l : StackArray#(Int32, 3)((1, 2, 3))
```

> [!TODO] Pensar una forma de definir longitud de forma automática.
> Igual `[?]T` para que el compilador lo calcule.


#### AllocatedArray

TODO before this: Allocators

similar to basic Array, but using an allocator, still static size

> Esto se parecerá bastante a un slice en realidad.

> Igual podríamos hacer que Stack fuera un allocator que se puede usar siempre
> y decir que es el valor por defecto, así podríamos unificar StackArray y
> AllocatedArray bajo un mismo tipo.

```
init#(.t: Type) (.a: $&AllocatedArray#(.t), .source: ListOfKnownLength#(.t, .n), .allocator: Allocator) -> () := {

    l : Int32 = length(source)
    data_ptr : &t = allocator | alloc(_, .count = l, .type = t)

    for i: Int32 = 0; i < l; i = i + 1 {
        element_ptr : $&t = data_ptr + i
        element_ptr& = src[i]
    }

    a& = (
        .data = data_ptr,
        .length = l,
        .allocator = allocator,
    )
}

deinit#(.t: Type) (.a: $&AllocatedArray#(.t)) -> () := {
    arr :: Slice#(.t) = a&
    ptr : &Any = arr.data
    free(.pointer = ptr)
}

operator get[]#(.t: Type)(.self: &AllocatedArray#(.t), .i: Int32) -> (.value: t) := {
    arr :: Slice#(.t) = self&
    element_ptr : &t = arr.data + i
    value = element_ptr&
}

operator set[]#(.t: Type)(.self: $&AllocatedArray#(.t), .i: Int32, .value: t) -> () := {
    arr :: Slice#(.t) = self&
    element_ptr : $&t = arr.data + i
    element_ptr& = value
}
```


#### Dynamic Arrays `[d]T` or `DynamicArray#(.t: Type)`

It uses allocated array internally

> [!FIX]
> `l : [d]Int32 = (1, 2, 3)`
> cannot turn into
> `l := DynamicArray#(Int32)((1, 2, 3), my_allocator)`
> Because it needs an allocator to work with!!

> [!TODO] Should [d]T be the default for list literals?


#### LengthedArray (capacidad fija en stack, len runtime)

`StaticVec#(.t, .n) = (.data:[n]t, .len:Int)`


#### PackedArray (enteros de b bits)

Empaqueta, p.ej. u10, u12.

PackedArray#(.bits:Int) = (...)


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

Index indication: `2..5` y `2.2.10`

> [!TODO] Pensar en otra sintaxis, que el punto se usa para otras cosas.

Igual `my_array | slice(2, 5)`

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

La list abstract type podría darse cuenta de que list literals anidados la
cumplen?


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


## Allocators

Similar to zig, they are are used to allocate and deallocate memory.

Ownership and copying are defined separately in `32_copying_behaviour.md`.
They are orthogonal concepts.
In particular, using an allocator and implementing `deinit()` does not make a
type automatically copyable.

```
Allocator : Abstract = (
	alloc (_, size: Int) -> Allocation
	dealloc (_, allocation: Allocation) -> ()
)
```

Allocators más típicos en zig:
- **PageAllocator**
  - Allocates memory from the OS, using `mmap` or `VirtualAlloc`.
  - Used for general-purpose allocations at runtime.
- **ArenaAllocator**
  - Allocates memory in chunks from the heap.
  - Useful for compilers, parsers, and loaders that need to allocate a lot of
  memory at once.
- **FixedBufferAllocator**
  - Allocates memory from a fixed-size buffer, which can be on the stack.
  - Used for temporary allocations without heap overhead.
- **GeneralPurposeAllocator**
  - A general-purpose allocator with additional safety features like redzones
  and leak detection.
  - Used for debugging applications.
- **ThreadLocalAllocator**
  - A bump-pointer allocator per thread with a fallback mechanism.
  - Used in multi-threaded applications to avoid contention.
- **CAllocator**
  - Uses `malloc` and `free` from the C standard library.
  - Useful for integrating with C libraries.


Para crear un nuevo allocator, tiene que tomar la capability `memory` de
`system` y usarla para crear un nuevo allocator.

```
init (.memory: &System.Memory) -> (.allocator: PageAllocator) := { ... }
```


## Allocation

Allocators return an `Allocation` struct, instead of a single pointer. This
allows us to keep track of the size and a pointer to the allocator used for the
allocation, which is necessary for deallocateing the memory later.

```
Allocation : Type = (
	.data      : &Byte
	.size      : Int  -- In bytes
	.allocator : &Allocator
)
```

`Allocation` should become the basic owning heap primitive in `core`.

That means higher-level owning types such as:

- strings,
- dynamic lists,
- maps,
- buffers,

should ideally compose an `Allocation` internally instead of each inventing a
different low-level ownership representation.

`Allocation` owns raw bytes only. It should not itself imply list semantics,
string semantics, or view semantics.

When initializing types, allocators are passed as arguments,

```
init (
    size     : Int,
    allocator: Allocator
) -> (.ha: Allocation) := {
	ha = Allocation (
		.data      = allocator|allocate(size)
		.size      = size
		.allocator = allocator
	)
}
```

```
my_buf : Allocation = init(1024, my_allocator)
```


In a type:

```
HashMap#(.key: Type, .value: Type) : Type = (
	.data      : Allocation
)


init#(.key: Type, .value: Type) (
    hm: $&HashMap#(.key: key, .value: value),
    allocator: &Allocator,
    content: MapLiteral,
) -> () :=  {
	hm& = (
        .data = allocation_init(.size = 1024)
    )
	...
}

-- When adding stuff check capacity and reallocate if necessary.

deinit#(.key: Type, .value: Type) (hm: $&HashMap#(.key: key, .value: value)) -> () := {
	allocation_deinit(.allocation = hm&.data)
}

copy#(.key: Type, .value: Type) (
    hm: HashMap#(.key: key, .value: value),
    allocator: &Allocator,
) -> (.out: HashMap#(.key: key, .value: value)) := {
	-- allocate new storage and duplicate the contents
}
```

```
my_map : HashMap#(.key: String, .value: Int32) = HashMap#(.key: String, .value: Int32)(
    my_allocator,
    ("a" = 1, "b" = 2),
)
```

If `HashMap` provides `copy()`, then passing it by value or assigning it means
creating an independent map. If it does not provide `copy()`, then it must be
passed by `&` or `$&`.

This separation is useful:

- allocator strategy is one concern,
- ownership and copying are another,
- borrowed views should remain a third, separate concern.

> [!FIX] Reflexionar sobre la sintaxis para incializar un mapa.
> Lo ideal sería:
> ```
> my_map := ("a"=1, "b"=2)
> ```
> El no tener un default allocator perjudica mucho la ergonomía del lenguaje.
> Pensar en hacer que no sea una capability

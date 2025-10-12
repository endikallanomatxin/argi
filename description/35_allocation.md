## Allocators

Similar to zig, they are are used to allocate and deallocate memory.

```
Allocator : Abstract = (
	alloc (_, size: Int) -> HeapAllocation
	dealloc (_, ha: HeapAllocation) -> ()
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
- **DirectAllocator**
  - Uses `malloc` and `free` from the C standard library.
  - Useful for integrating with C libraries.


Para crear un nuevo allocator, tiene que tomar la capability `memory` de
`system` y usarla para crear un nuevo allocator.

```
init (.memory: &System.Memory) -> (.allocator: PageAllocator) := { ... }
```


## HeapAllocation

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

When initializing types, allocators are passed as arguments,

```
init (
    size     : Int,
    allocator: Allocator
) -> (.ha: HeapAllocation) := {
	ha = HeapAllocation (
		.data      = allocator|allocate(size)
		.size      = size
		.allocator = allocator
	)
}
```

```
my_buf : HeapAllocation = init(1024, my_allocator)
```


In a type:

```
Hashmap#(.from: Type, .to: Type) : Type = (
	.data      : Allocation
)


init (.allocator: Allocator, content: MapLiteral) -> (.hm: HashMap#(f, t)) :=  {
	hm : Hashmap#(f, t)
	hm.data = allocator|alloc(1024)
	...
}

-- When adding stuff check capacity and reallocate if necessary.

deinit (.hm:$&Hashmap&) -> () := {
	hm.data|dealloc(_)
}
```

```
my_map : HashMap#(String,Int32) = init (my_allocator, ("a"=1, "b"=2))
```

> [!FIX] Reflexionar sobre la sintaxis para incializar un mapa.
> Lo ideal sería:
> ```
> my_map := ("a"=1, "b"=2)
> ```
> El no tener un default allocator perjudica mucho la ergonomía del lenguaje.
> Pensar en hacer que no sea una capability




ArenaAllocator : Type = struct [
    ---
    Se usa igual que un alocator normal, se hace keep cuando quieres poder usar la variable en el futuro.
    Se puede hacer:
        keep with otra_variable
    o
        keep with arena

    A diferencia de otros allocators:
    - dealloc no hace nada
    - Solo es libera la memoria cuando se llama a deinit del propio allocator
    ---

    ._child       : Allocator  -- de dónde obtiene páginas grandes
    ._allocations : StaticArray<&Byte>
    ._index       : Int

    ---
    EXAMPLE

    """rg
    arena := ArenaAllocator|init()

    data := ExampleType|init(allocator=arena)
    keep data with arena

    more_data := AnotherType|init(allocator=arena)
    keep more_data with arena
    """

    ---
]

init(#t:==ArenaAllocator, child: Allocator = default) : ArenaAllocator {
    return ArenaAllocator{ ._child=child, .allocations=[], .index=0 }
}

deinit(a: $&ArenaAllocator) {
    // Al salir del scope: liberar todos los allocations pendientes
    for allocation in a.allocations {
        a._child|dealloc(allocation.ptr)
    }
}

alloc(a: $&ArenaAllocator, size: Int, alignment: Alignment) : &Byte!HeapAllocationError {
    // 1) Si cabe en el último allocation, ajustar index y devolver ptr
    // 2) Si no, pedir un allocation nuevo via a._child|alloc(...)
    // 3) Guardar en a.allocations y resetear a.index
    …
}

resize(a: $&ArenaAllocator, ptr: &Byte, new_size: Int) : Bool {
    // Sólo si `ptr` es la última asignación, podemos ajustar `index`
    …
}

dealloc(a: $&ArenaAllocator, ptr: &Byte) !HeapAllocationError {
    // No op
}

Allocator canbe ArenaAllocator


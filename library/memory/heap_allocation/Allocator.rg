Allocator : Abstract = [
    ---
    Strategy for obtaining and releasing heap pages
    ---
    memory.initialization.Initializable
    alloc  (_, size: Int, alignment: Alignment = ..Default) : &Byte!HeapAllocationError
    dealloc  (_, ptr: &Byte) !HeapDeallocationError
    -- resize (_, ptr: &Byte, new_size: Int) : Bool
    -- Igual resize no lo cumplen muchos métodos y mejor dejarlo fuera
    -- y que se haga manualmente cuando se quiera.
]


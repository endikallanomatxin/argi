Allocator : Abstract = (
    -- Strategy for obtaining and releasing heap pages

    -- memory.initialization.Initializable

    -- alloc  (.self: Self, .size: UIntNative) -> (.allocation: Allocation)
    -- dealloc (.self: Self, .allocation: Allocation) -> ()

    -- resize (.self: Self, .allocation: $&Allocation, .new_size: UIntNative) -> (.did_resize: Bool)
    -- Igual resize no lo cumplen muchos métodos y mejor dejarlo fuera
    -- y que se haga manualmente cuando se quiera.
)

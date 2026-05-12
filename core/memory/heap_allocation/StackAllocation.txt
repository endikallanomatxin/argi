StackAllocation : Type = (
    -- TODO: Does it even make sense?
    ._data : &Any
    ._size : Int32  -- In bytes
)

new_stack_allocation (.size: Int32) -> (.sa: StackAllocation) = {
    -- Use libc's alloca to allocate on the stack
    pointer = alloca(.size=size)
    -- BUG: Se va a liberar al final de la funcion
    sa = StackAllocation{._data=pointer, ._size=size}
}


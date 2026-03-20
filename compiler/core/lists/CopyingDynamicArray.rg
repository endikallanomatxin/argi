CopyingDynamicArray#(.t: Type) : Type = (
    --
    -- A heap allocated dynamic array
    -- that copies data when length exceeds capacity
    -- Fast accessing
    --
    -- Intended long-term storage model:
    -- ._allocation : Allocation
    -- ._length     : UIntNative
    -- ._capacity   : UIntNative
    --
    -- Views into the array should use `ListViewRO#(.t=t)` or
    -- `ListViewRW#(.t=t)` and remain non-owning.
)

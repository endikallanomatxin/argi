CopyingDynamicArray#(.t: Type) : Type = (
    --
    -- A heap allocated dynamic array
    -- that copies data when length exceeds capacity
    -- Fast accessing
    --
    -- ._data      : &HeapAllocation
    -- ._data_type : Type        = t
    -- ._alignment : Alignment   = ..Default
    -- ._length    : Int64
    -- ._capacity  : Int64
)

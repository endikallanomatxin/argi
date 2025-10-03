HeapAllocation : Type = struct [
    ---
    This is useful to encapsulate an alocation with its allocator
    ---
    ._data : &Byte
    ._size : Int  -- In bytes
    ._allocator : Allocator
]

HeapAllocationError : Error
HeapDeallocationError : Error


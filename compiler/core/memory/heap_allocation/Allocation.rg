Allocation#(.type: Type) : Type = (
    -- Minimal placeholder for low level allocations.
    ._ptr    : ListView#(.list_type=Array#(.type=type), .list_value_type=type)
    ._length : UInt64
)

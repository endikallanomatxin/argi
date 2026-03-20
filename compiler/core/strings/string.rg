String : Type = (
    --
    -- Intended long-term representation:
    -- ._allocation : Allocation
    -- ._length     : UIntNative
    --
    -- `String` owns its bytes. Non-owning string slices/views should be
    -- modeled separately as plain borrowed descriptors.
)

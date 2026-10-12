Float: Contract = (
    -- operator +(_, _) : _
    -- operator -(_, _) : _
    -- operator *(_, _) : _
    -- operator /(_, _) : _
    -- operator ^(_, _) : _
    -- ...
)

Float16 satisfies Float
Float32 satisfies Float
Float64 satisfies Float

-- TODO: support Float128 and Float8

-- You cannot customize that layout from within standard LLVM IR
-- So it doesn't make sense to have a CustomLengthedFloat<N> type

Float defaultsto Float32

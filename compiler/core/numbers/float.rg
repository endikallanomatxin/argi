Float : Abstract = (
	-- operator +(_, _) : _
	-- operator -(_, _) : _
	-- operator *(_, _) : _
	-- operator /(_, _) : _
	-- operator ^(_, _) : _
	-- ...
)

Float canbe Float16
Float canbe Float32
Float canbe Float64

-- TODO: support Float128 and Float8

-- You cannot customize that layout from within standard LLVM IR
-- So it doesn't make sense to have a CustomLengthedFloat<N> type


Float defaultsto Float32


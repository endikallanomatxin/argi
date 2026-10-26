Float<.Value: Type>: Contract = ()

implement Float<Float16> ()

implement Float<Float32> ()

implement Float<Float64> ()

-- TODO: support Float128 and Float8

-- You cannot customize that layout from within standard LLVM IR
-- So it doesn't make sense to have a CustomLengthedFloat#(N) type

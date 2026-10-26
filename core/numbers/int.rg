-- Numeric classification does not declare arithmetic operations.
-- Operators are separate from numeric classification.
Int<.Value: Type>: Contract = ()

-- Signed integers
implement Int<Int8> ()

implement Int<Int16> ()

implement Int<Int32> ()

implement Int<Int64> ()

-- Unsigned integers
implement Int<UInt8> ()

implement Int<UInt16> ()

implement Int<UInt32> ()

implement Int<UInt64> ()

implement Int<UIntNative> ()

UInt<.Value: Type>: Contract = ()

implement UInt<UInt8> ()

implement UInt<UInt16> ()

implement UInt<UInt32> ()

implement UInt<UInt64> ()

implement UInt<UIntNative> ()

-- TODO: More types
--
--    - DynamicInt
--         Automatically changes size according to the value. Never overflows.
--         No need to cast when operating with it.
--         (Maybe it should be the default?)
--
--    - Int128, UInt128
--
--    - CustomLengthedInt#(n), CustomLengthedUInt#(n)

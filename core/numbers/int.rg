Int: contract = (
    -- float(_) : Float
    -- operator +(_, _) : Int
    -- operator -(_, _) : Int
    -- operator *(_, _) : Int
    -- operator /(_, _) : Int
    -- operator %(_, _) : Int
    -- operator ^(_, _) : Int
    -- ...
)

-- Signed integers
Int8 satisfies Int
Int16 satisfies Int
Int32 satisfies Int
Int64 satisfies Int

-- Unsigned integers
UInt8 satisfies Int
UInt16 satisfies Int
UInt32 satisfies Int
UInt64 satisfies Int
UIntNative satisfies Int

UInt: contract = ()

UInt8 satisfies UInt
UInt16 satisfies UInt
UInt32 satisfies UInt
UInt64 satisfies UInt
UIntNative satisfies UInt

-- TODO: Think if having SignedInteger and UnsignedInteger as abstracts is a
-- good idea. I think it is not very useful. But consider.

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

Int : Abstract = (
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
Int canbe Int8
Int canbe Int16
Int canbe Int32
Int canbe Int64

-- Unsigned integers
Int canbe UInt8
Int canbe UInt16
Int canbe UInt32
Int canbe UInt64


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


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
Int8 implements Int
Int16 implements Int
Int32 implements Int
Int64 implements Int

-- Unsigned integers
UInt8 implements Int
UInt16 implements Int
UInt32 implements Int
UInt64 implements Int


UInt : Abstract = ()
UInt8 implements UInt
UInt16 implements UInt
UInt32 implements UInt
UInt64 implements UInt



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

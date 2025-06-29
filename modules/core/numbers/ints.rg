-- Signed integers
builtin Int8
builtin Int16
builtin Int32
builtin Int64
builtin Int128

-- Unsigned integers
builtin UInt8
builtin UInt16
builtin UInt32
builtin UInt64
builtin UInt128

Int : Abstract = [
	float(_) : Float
	operator +(_, _) : Int
	operator -(_, _) : Int
	operator *(_, _) : Int
	operator /(_, _) : Int
	operator %(_, _) : Int
	operator ^(_, _) : Int
	...
]

-- TODO: Think about having SignedInteger and UnsignedInteger as abstracts

Int canbe [
	-- Automatically changes size according to the value. Never overflows.
	DynamicInt

	-- Fixed size integers. They overflow. No undefined behavior.
	CustomInt(N)
	Int8, Int16, Int32, Int64, Int128
	UInt8, UInt16, UInt32, UInt64, UInt128
]

Int defaultsto DynamicInt


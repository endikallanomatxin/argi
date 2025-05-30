-- Floats
builtin Float8
builtin Float16
builtin Float32
builtin Float64
builtin Float128

Float : Type : abstract [
	operator +(_, _) : _
	operator -(_, _) : _
	operator *(_, _) : _
	operator /(_, _) : _
	operator ^(_, _) : _
	...
]

Float canbe [Float8, Float16, Float32, Float64, Float128]
Float defaultsto Float32

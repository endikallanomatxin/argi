Real : Abstract = [
	operator +(_, _) : Int
	operator -(_, _) : Int
	operator *(_, _) : Int
	operator /(_, _) : Int
	operator %(_, _) : Int
	operator ^(_, _) : Int
	...
]

Int implements Real
Float implements Real

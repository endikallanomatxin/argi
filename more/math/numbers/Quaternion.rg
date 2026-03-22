Quaternion : Abstract = (
	operator + (.left: Self, .right: Self) -> (.result: Self)
	operator - (.left: Self, .right: Self) -> (.result: Self)
	operator * (.left: Self, .right: Self) -> (.result: Self)
	operator / (.left: Self, .right: Self) -> (.result: Self)
	...
)

Quaternion8 implements Quaternion
Quaternion16 implements Quaternion
Quaternion32 implements Quaternion
Quaternion64 implements Quaternion
Quaternion128 implements Quaternion
Quaternion defaultsto Quaternion32

Quaternion implements Number

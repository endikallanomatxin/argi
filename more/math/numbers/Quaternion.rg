Quaternion :: Abstract = [
	operator +(_, _) :: _
	operator -(_, _) :: _
	operator *(_, _) :: _
	operator /(_, _) :: _
	...
]

Quaternion canbe [Quaternion8, Quaternion16, Quaternion32, Quaternion64, Quaternion128]
Quaternion defaultsto Quaternion32

Number canbe Quaternion

Quaternion: contract = (
    operator + (.left: Self, .right: Self) -> (.result: Self)
    operator - (.left: Self, .right: Self) -> (.result: Self)
    operator * (.left: Self, .right: Self) -> (.result: Self)
    operator / (.left: Self, .right: Self) -> (.result: Self)
    ...
)

Quaternion8 satisfies Quaternion
Quaternion16 satisfies Quaternion
Quaternion32 satisfies Quaternion
Quaternion64 satisfies Quaternion
Quaternion128 satisfies Quaternion
Quaternion defaultsto Quaternion32

Quaternion satisfies Number

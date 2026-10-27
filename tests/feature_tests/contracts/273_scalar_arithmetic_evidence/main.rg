baseline :: Int32 = [2 + 3] * 4 - 5

compute := #(.T: Type) (.left: T, .right: T) -> (.result: T) {
    result = [left + right] * right - left / right + left % right
}

main := () -> (.status_code: Int32 = 0) {
    byte :: UInt8 = 9
    narrow :: UInt8 = 1 + byte
    difference :: UInt8 = byte - 2
    product :: UInt8 = byte * 3
    quotient :: UInt8 = byte / 2
    remainder :: UInt8 = byte % 2
    generic ::= compute(byte, 2)
    small :: Float32 = 2.5
    real :: Float32 = [1.0 + small] * 2.0 - small / 2.0
    if [
        baseline != 15
        or narrow != 10
        or difference != 7
        or product != 27
        or quotient != 4
        or remainder != 1
        or generic != 19
        or real != 5.75
    ] { status_code = 1 }
    qualified ::= Multiply#(UInt8, UInt8).multiply(.left = byte, .right = 3)
    if qualified != 27 { status_code = 2 }
}

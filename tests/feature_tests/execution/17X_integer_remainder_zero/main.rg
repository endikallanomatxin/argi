main := () -> (.status_code: Int32 = 0) {
    divisor :: UInt64 = 0
    value ::= 7 % divisor
    if value == 0 { status_code = 42 }
}

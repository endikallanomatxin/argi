signed_minimum: Int64 = -9223372036854775808
signed_divisor: Int64 = -1
maximum: UInt64 = 18446744073709551615
small_minimum: Int8 = -128
small_divisor: Int8 = -1
minimum: Int64 = signed_minimum / signed_divisor
remainder: Int64 = signed_minimum % signed_divisor
unsigned_product: UInt64 = maximum * maximum
small: Int8 = small_minimum / small_divisor

main := () -> (.status_code: Int32 = 0) {
    if minimum != -9223372036854775808 or remainder != 0 { abort }
    if unsigned_product != 1 or small != -128 { abort }
    status_code = 42
}

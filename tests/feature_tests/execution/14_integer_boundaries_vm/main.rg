main := () -> (.status_code: Int32 = 0) {
    maximum :: UInt64 = 18446744073709551615
    if maximum + 1 != 0 { abort }
    if maximum * maximum != 1 { abort }
    zero :: UInt64 = 0
    if zero - 1 != maximum { abort }
    minimum :: Int64 = -9223372036854775808
    negative_one :: Int64 = -1
    if minimum / negative_one != minimum { abort }
    if minimum % negative_one != 0 { abort }
    byte :: Int8 = 127
    if byte + 1 != -128 { abort }
    small_minimum :: Int8 = -128
    small_divisor :: Int8 = -1
    if small_minimum / small_divisor != small_minimum { abort }
    if small_minimum % small_divisor != 0 { abort }
    signed :: Int32 = -7
    if signed / 3 != -2 or signed % 3 != -1 { abort }
    status_code = 42
}

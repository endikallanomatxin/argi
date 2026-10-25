main() -> (.status_code: Int32 = 0) := {
    value :: Int32 = 2147483647
    wrapped ::= value + 1
    if wrapped != -2147483648 { abort }
    narrow :: Int8 = 127
    if narrow + 1 != -128 { abort }
    unsigned :: UInt64 = 18446744073709551615
    if unsigned * unsigned != 1 { abort }
    minimum :: Int64 = -9223372036854775808
    if minimum / -1 != minimum { abort }
    if minimum % -1 != 0 { abort }
    status_code = 42
}

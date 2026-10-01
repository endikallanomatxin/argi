main() -> (.status_code: Int32 = 0) := {
    native ::= UIntNativeHashPolicy()
    integer ::= Int32HashPolicy()
    text ::= StringViewHashPolicy()
    if hash(.self = &integer, .key = -2147483648).hash != 2147483648 { abort }
    if hash(.self = &integer, .key = -1).hash != 4294967295 { abort }
    if hash(.self = &integer, .key = 0).hash != 0 { abort }
    if hash(.self = &integer, .key = 2147483647).hash != 2147483647 { abort }
    value :: UIntNative = 12345
    if hash(.self = &native, .key = value).hash != value { abort }
    bytes : [3]UInt8 = (97, 0, 98)
    same : [3]UInt8 = (97, 0, 98)
    left :: StringView = (.data = &bytes[0], .length = 3)
    right :: StringView = (.data = &same[0], .length = 3)
    if eql(.self = &text, .left = left, .right = right).ok == false { abort }
    if hash(.self = &text, .key = left).hash != hash(.self = &text, .key = right).hash { abort }
    if hash(.self = &text, .key = left).hash != string_hash_map_hash(.key = &left).hash { abort }
    if eql(.self = &text, .left = left, .right = "ab").ok { abort }
}

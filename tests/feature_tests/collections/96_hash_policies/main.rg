main(.system: System) -> (.status_code: Int32 = 0) := {
    native ::= UIntNativeHashPolicy()
    integer ::= Int32HashPolicy()
    text ::= StringViewHashPolicy()
    if [
        HashPolicy#(Int32HashPolicy, Int32).hash(.self = &integer, .key = -2147483648).hash
        != 2147483648
    ] { abort }
    if HashPolicy#(Int32HashPolicy, Int32).hash(.self = &integer, .key = -1).hash != 4294967295 {
        abort
    }
    if HashPolicy#(Int32HashPolicy, Int32).hash(.self = &integer, .key = 0).hash != 0 { abort }
    if [
        HashPolicy#(Int32HashPolicy, Int32).hash(.self = &integer, .key = 2147483647).hash
        != 2147483647
    ] { abort }
    value :: UIntNative = 12345
    if [
        HashPolicy#(UIntNativeHashPolicy, UIntNative).hash(.self = &native, .key = value).hash
        != value
    ] { abort }
    bytes: [3]UInt8 = (97, 0, 98)
    same: [3]UInt8 = (97, 0, 98)
    left_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    left ::= view(&left_storage)
    right_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&same), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    right ::= view(&right_storage)
    if [
        HashPolicy#(
            StringViewHashPolicy, StringView
        ).eql(.self = &text, .left = left, .right = right).ok
        == false
    ] { abort }
    if [
        HashPolicy#(StringViewHashPolicy, StringView).hash(.self = &text, .key = left).hash
        != HashPolicy#(StringViewHashPolicy, StringView).hash(.self = &text, .key = right).hash
    ] { abort }
    if [
        HashPolicy#(StringViewHashPolicy, StringView).hash(.self = &text, .key = left).hash
        != string_hash_map_hash(.key = &left).hash
    ] { abort }
    if HashPolicy#(
        StringViewHashPolicy, StringView
    ).eql(.self = &text, .left = left, .right = "ab").ok { abort }
}

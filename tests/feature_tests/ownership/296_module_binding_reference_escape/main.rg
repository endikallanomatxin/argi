marker :: UInt8 = 7

get_marker() -> (.reference: &UInt8) := {
    reference = &marker
}

get_erased_marker() -> (.reference: &Any) := {
    reference = erase_reference#(.t: UInt8)(.base = &marker).reference
}

main() -> (.status_code: Int32 = 0) := {
    direct ::= get_marker()
    erased ::= get_erased_marker()
    if direct& != 7 or UIntNative(.value = erased) != UIntNative(.value = direct) {
        status_code = 1
    }
}

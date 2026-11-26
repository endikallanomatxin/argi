consume_on_exit := (.address: UIntNative, .root: &Any) -> () {
    index :: UIntNative = 0
    while index < 2 {
        index = index + 1
        if index < 2 {
            continue
        } else {
            raw ::= trusted_establish_inherited_storage(.address = address, .root = root).raw
            break
        }
    }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    if address == 0 { abort }
    consume_on_exit(.address = address, .root = root)
    free(.address = address, .ffi = system.ffi)
}

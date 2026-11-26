consume := (.address: UIntNative, .root: &Any) -> () {
    raw ::= trusted_establish_inherited_storage(.address = address, .root = root).raw
}

condition := (.address: UIntNative, .root: &Any, .index: UIntNative) -> (.again: Bool) {
    consume(.address = address, .root = root)
    again = index < 1
}

loop := (.address: UIntNative, .root: &Any, .ffi: $&ForeignFunctionInterface) -> () {
    initial ::= malloc(.size = 8, .ffi = ffi).address
    if initial == 0 { abort }
    current :: UIntNative = initial
    index :: UIntNative = 0
    while condition(.address = current, .root = root, .index = index).again {
        current = address
        index = index + 1
    }
    free(.address = initial, .ffi = ffi)
}

main := (.system: System) -> () {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    if address == 0 { abort }
    loop(.address = address, .root = root, .ffi = system.ffi)
    consume(.address = address, .root = root)
    free(.address = address, .ffi = system.ffi)
}

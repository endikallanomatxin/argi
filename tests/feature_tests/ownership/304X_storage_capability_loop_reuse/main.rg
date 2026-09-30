consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = trusted_establish_inherited_storage(.address = address, .root = root).raw
}
repeat(.address: UIntNative, .root: &Any, .count: UIntNative) -> () := {
    i :: UIntNative = 0
    while i < count {
        raw ::= consume(.address = address, .root = root).raw
        i = i + 1
    }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    repeat(.address = address, .root = root, .count = 2)
}

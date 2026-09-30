consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = trusted_establish_inherited_storage(.address = address, .root = root).raw
}
consume_pointer(.address: &UIntNative, .root: &Any) -> () := {
    raw ::= consume(.address = address&, .root = root).raw
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    consume_pointer(.address = &address, .root = root)
    raw ::= consume(.address = address, .root = root).raw
}

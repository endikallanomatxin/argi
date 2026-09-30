consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = trusted_establish_inherited_storage(.address = address, .root = root).raw
}
twice(.address: UIntNative, .root: &Any) -> () := {
    alias ::= address
    raw ::= consume(.address = address, .root = root).raw
    other ::= consume(.address = alias, .root = root).raw
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    twice(.address = address, .root = root)
}

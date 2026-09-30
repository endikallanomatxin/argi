consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = establish_inherited_storage(.address = address, .root = root).raw
}
pair(.first: UIntNative, .second: UIntNative, .root: &Any) -> () := {
    a ::= consume(.address = first, .root = root).raw
    b ::= consume(.address = second, .root = root).raw
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    alias ::= address
    pair(.first = address, .second = alias, .root = root)
}

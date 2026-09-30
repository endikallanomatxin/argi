consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = establish_inherited_storage(.address = address, .root = root).raw
}
maybe_consume(.address: UIntNative, .root: &Any, .take: Bool) -> () := {
    if take { raw ::= consume(.address = address, .root = root).raw }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    maybe_consume(.address = address, .root = root, .take = true)
    raw ::= consume(.address = address, .root = root).raw
}

consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = establish_inherited_storage(.address = address, .root = root).raw
}
recursive(.address: UIntNative, .root: &Any, .depth: UIntNative) -> () := {
    raw ::= consume(.address = address, .root = root).raw
    if depth > 0 { recursive(.address = address, .root = root, .depth = depth - 1) }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    recursive(.address = address, .root = root, .depth = 1)
}

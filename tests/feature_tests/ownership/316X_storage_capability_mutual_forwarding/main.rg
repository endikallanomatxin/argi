consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = establish_inherited_storage(.address = address, .root = root).raw }
left(.address: UIntNative, .root: &Any, .depth: UIntNative) -> () := {
    if depth == 0 { raw ::= consume(.address = address, .root = root).raw } else { right(.address = address, .root = root, .depth = depth - 1) }
}
right(.address: UIntNative, .root: &Any, .depth: UIntNative) -> () := { left(.address = address, .root = root, .depth = depth) }
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    left(.address = address, .root = root, .depth = 2)
    raw ::= consume(.address = address, .root = root).raw
}

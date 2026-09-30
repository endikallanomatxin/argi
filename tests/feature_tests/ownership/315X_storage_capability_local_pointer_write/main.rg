consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = trusted_establish_inherited_storage(.address = address, .root = root).raw }
overwrite(.old: UIntNative, .current: UIntNative, .root: &Any) -> () := {
    local ::= old
    pointer ::= $&local
    pointer& = current
    raw ::= consume(.address = local, .root = root).raw
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    second ::= malloc(.size = 8, .ffi = system.ffi).address
    overwrite(.old = address, .current = second, .root = root)
    raw ::= consume(.address = second, .root = root).raw
}

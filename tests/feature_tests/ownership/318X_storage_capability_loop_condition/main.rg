consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = trusted_establish_inherited_storage(.address = address, .root = root).raw }
condition(.address: UIntNative, .root: &Any) -> (.again: Bool) := {
    raw ::= consume(.address = address, .root = root).raw
    again = true
}
loop(.address: UIntNative, .root: &Any) -> () := { while condition(.address = address, .root = root).again {} }
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    loop(.address = address, .root = root)
}

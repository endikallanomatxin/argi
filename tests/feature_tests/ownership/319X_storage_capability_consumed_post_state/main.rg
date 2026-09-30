consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = trusted_establish_inherited_storage(.address = address, .root = root).raw }
acquire_spent(.ffi: $&ForeignFunctionInterface, .destination: $&UIntNative, .root: &Any) -> () := {
    local ::= malloc(.size = 8, .ffi = ffi).address
    raw ::= consume(.address = local, .root = root).raw
    destination& = local
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    stored :: UIntNative = 0
    acquire_spent(.ffi = system.ffi, .destination = $&stored, .root = root)
    raw ::= consume(.address = stored, .root = root).raw
}

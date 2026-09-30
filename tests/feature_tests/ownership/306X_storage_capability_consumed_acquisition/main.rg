consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = trusted_establish_inherited_storage(.address = address, .root = root).raw
}
acquire_consumed(.ffi: $&ForeignFunctionInterface, .root: &Any) -> (.address: UIntNative) := {
    local ::= malloc(.size = 8, .ffi = ffi).address
    raw ::= consume(.address = local, .root = root).raw
    address = local
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    returned ::= acquire_consumed(.ffi = system.ffi, .root = root).address
    raw ::= consume(.address = returned, .root = root).raw
}

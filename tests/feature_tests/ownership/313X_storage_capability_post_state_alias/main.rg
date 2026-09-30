consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = establish_inherited_storage(.address = address, .root = root).raw }
acquire_into(.ffi: $&ForeignFunctionInterface, .destination: $&UIntNative) -> (.address: UIntNative) := {
    local ::= malloc(.size = 8, .ffi = ffi).address
    destination& = local
    address = local
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    stored :: UIntNative = 0
    returned ::= acquire_into(.ffi = system.ffi, .destination = $&stored).address
    a ::= consume(.address = returned, .root = root).raw
    b ::= consume(.address = stored, .root = root).raw
}

consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = establish_inherited_storage(.address = address, .root = root).raw }
acquire_pair(.ffi: $&ForeignFunctionInterface) -> (.first: UIntNative, .second: UIntNative) := {
    local ::= malloc(.size = 8, .ffi = ffi).address
    first = local
    second = local
}
forward_pair(.ffi: $&ForeignFunctionInterface) -> (.first: UIntNative, .second: UIntNative) := {
    local ::= acquire_pair(.ffi = ffi)
    first = local.first
    second = local.second
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    values ::= forward_pair(.ffi = system.ffi)
    a ::= consume(.address = values.first, .root = root).raw
    b ::= consume(.address = values.second, .root = root).raw
}

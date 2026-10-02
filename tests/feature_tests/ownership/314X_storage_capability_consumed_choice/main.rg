consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = trusted_establish_inherited_storage(.address = address, .root = root).raw }
acquire_choice(.ffi: $&ForeignFunctionInterface, .root: &Any, .enabled: Bool) -> (.result: ?UIntNative) := {
    if enabled {
        local ::= malloc(.size = 8, .ffi = ffi).address
        raw ::= consume(.address = local, .root = root).raw
        result = ..some(.value = local)
    } else { result = ..none }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    acquired ::= acquire_choice(.ffi = system.ffi, .root = root, .enabled = true).result
    match acquired {
        ..some payload { raw ::= consume(.address = payload.value, .root = root).raw }
        ..none {}
    }
}

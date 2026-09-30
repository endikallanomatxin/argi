consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = establish_inherited_storage(.address = address, .root = root).raw
}
acquire(.ffi: $&ForeignFunctionInterface) -> (.address: UIntNative) := { address = malloc(.size = 8, .ffi = ffi).address }
forward(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := {
    alias ::= address
    raw = consume(.address = alias, .root = root).raw
}
branch(.address: UIntNative, .root: &Any, .choose: Bool) -> () := {
    if choose { raw ::= forward(.address = address, .root = root).raw } else { raw ::= consume(.address = address, .root = root).raw }
}
early(.address: UIntNative, .root: &Any, .choose: Bool) -> () := {
    if choose { raw ::= consume(.address = address, .root = root).raw
        return }
    raw ::= consume(.address = address, .root = root).raw
}
recursive(.address: UIntNative, .root: &Any, .depth: UIntNative) -> () := {
    if depth == 0 { raw ::= consume(.address = address, .root = root).raw } else { recursive(.address = address, .root = root, .depth = depth - 1) }
}
choose_alias(.first: UIntNative, .second: UIntNative, .root: &Any, .choose: Bool) -> () := {
    if choose { raw ::= consume(.address = first, .root = root).raw } else { raw ::= consume(.address = second, .root = root).raw }
}
maybe_acquire(.ffi: $&ForeignFunctionInterface, .enabled: Bool) -> (.result: ?UIntNative) := {
    if enabled { result = ..some(.value = malloc(.size = 8, .ffi = ffi).address) } else { result = ..none }
}
forward_choice(.ffi: $&ForeignFunctionInterface) -> (.address: UIntNative) := {
    choice ::= maybe_acquire(.ffi = ffi, .enabled = true).result
    match choice {
        ..some payload { address = payload.value }
        ..none { abort }
    }
}
forward_alias(.address: UIntNative, .root: &Any) -> () := {
    choose_alias(.first = address, .second = address, .root = root, .choose = true)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    first ::= acquire(.ffi = system.ffi).address
    raw ::= forward(.address = first, .root = root).raw
    free(.address = first, .ffi = system.ffi)
    second ::= acquire(.ffi = system.ffi).address
    branch(.address = second, .root = root, .choose = false)
    free(.address = second, .ffi = system.ffi)
    third ::= acquire(.ffi = system.ffi).address
    early(.address = third, .root = root, .choose = true)
    free(.address = third, .ffi = system.ffi)
    fourth ::= acquire(.ffi = system.ffi).address
    recursive(.address = fourth, .root = root, .depth = 3)
    free(.address = fourth, .ffi = system.ffi)
    aliased ::= acquire(.ffi = system.ffi).address
    choose_alias(.first = aliased, .second = aliased, .root = root, .choose = true)
    free(.address = aliased, .ffi = system.ffi)
    chosen ::= forward_choice(.ffi = system.ffi).address
    raw_choice ::= consume(.address = chosen, .root = root).raw
    free(.address = chosen, .ffi = system.ffi)
    alias_forwarded ::= acquire(.ffi = system.ffi).address
    forward_alias(.address = alias_forwarded, .root = root)
    free(.address = alias_forwarded, .ffi = system.ffi)
    i :: UIntNative = 0
    while i < 3 {
        current ::= acquire(.ffi = system.ffi).address
        local ::= consume(.address = current, .root = root).raw
        free(.address = current, .ffi = system.ffi)
        i = i + 1
    }
}

-- The system source is a capability, independent of deterministic Pcg32 state.
RandomNumberGenerator: Type = (._ffi: $&ForeignFunctionInterface)

once RandomNumberGenerator init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: RandomNumberGenerator) := {
    result = (._ffi = ffi)
}

..entropy_unavailable

#if target_os("linux") or target_os("macos") {
    _system_entropy(.bytes: $&UInt8, .length: UIntNative) -> (.status: Int32): CFunction(.symbol = "getentropy")
}#else {
    #if target_os("windows") {
        _system_entropy(.bytes: $&UInt8, .length: UIntNative) -> (.status: Int32): CFunction(.symbol = "_argi_system_entropy")
    }
}

-- Fill only initialized storage. A failing source may have changed a prefix;
-- callers must discard all bytes after an error. Empty requests need no FFI.
fill_random_bytes(
    .self        : $&RandomNumberGenerator,
    .destination : ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: Void, .reasons: (..entropy_unavailable))) := {
    extent ::= length(.self = &destination).count
    if extent == 0 { result = ..ok Void() return }
    #if target_os("linux") or target_os("macos") or target_os("windows") {
        assume ffi ::= self&._ffi
        offset :: UIntNative = 0
        while offset < extent {
            chunk ::= extent - offset
            if chunk > 256 { chunk = 256 }
            pointer ::= unwrap_or_abort(.value = get_rw_ref(.self = $&destination, .index = offset)).result
            if _system_entropy(.bytes = pointer, .length = chunk).status != 0 {
                result = ..error(.reason = ..entropy_unavailable)
                return
            }
            offset = offset + chunk
        }
        result = ..ok Void()
    }#else {
        result = ..error(.reason = ..entropy_unavailable)
    }
}

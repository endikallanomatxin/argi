EnvironmentVariables: Type = (._ffi: $&ForeignFunctionInterface)

once _acquire_environment_variables := (
        .args : (.ffi: $&ForeignFunctionInterface = reach ffi)
    ) -> (
        .result : EnvironmentVariables
    ) {
    ffi ::= args.ffi

    result._ffi = ffi
}

implement Init#(EnvironmentVariables, (.ffi: $&ForeignFunctionInterface = reach ffi)) (
    .Result : Type                           = EnvironmentVariables
    .init   = _acquire_environment_variables
)

environment_variables_get_c_string(
        .key : &Char,
    ) -> (
        .value : ?StringView
    ) := {
    raw_ptr ::= getenv(.name = key).value
    raw_addr :: UIntNative = raw_ptr | convert#(.to: UIntNative)(_)

    if raw_addr == 0 {
        value = ..none
        return
    }

    value = ..some(
        .value = (
            .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = raw_ptr).reference
            .length = strlen(.string = raw_ptr).length
        )
    )
}

lookup_environment#(
        .Provider : Type: Allocator#(Provider)
    ) := (
        .self      : &EnvironmentVariables,
        .key       : StringView,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(?StringView, (..out_of_memory))
    ) {
    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(key, .allocator = allocator)

    match converted {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~c_key {
            result = ..ok environment_variables_get_c_string(.key = c_key.text)
        }
    }
}

has#(
        .AllocatorType : Type: Allocator#(AllocatorType)
    )(
        .self      : &EnvironmentVariables,
        .key       : StringView,
        .allocator : $&AllocatorType,
    ) -> (
        .result : Errable#(Bool, (..out_of_memory))
    ) := {
    assume ffi := self&._ffi
    assume allocator

    found ::= lookup_environment(self, .key = key, .allocator = allocator)

    match found {
        ..ok payload { result = ..ok payload ?}
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

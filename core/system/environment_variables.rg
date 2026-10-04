EnvironmentVariables: Type = (._ffi: $&ForeignFunctionInterface)

once EnvironmentVariables init(
        .ffi : $&ForeignFunctionInterface = reach ffi
    ) -> (
        .result : EnvironmentVariables
    ) := {
    result._ffi = ffi
}

environment_variables_get_c_string(
        .key : &Char,
    ) -> (
        .value : ?StringView
    ) := {
    raw_ptr ::= getenv(.name = key).value
    raw_addr :: UIntNative = UIntNative(.value = raw_ptr)

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

get(
        .self      : &EnvironmentVariables,
        .key       : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(.t: ?StringView, .reasons: (..out_of_memory))
    ) := {
    assume ffi := self&._ffi
    assume allocator

    converted ::= as_c_string(.self = key, .allocator = allocator)
    match converted {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~c_key {
            result = ..ok environment_variables_get_c_string(.key = c_key.text)
        }
    }
}

has(
        .self      : &EnvironmentVariables,
        .key       : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(.t: Bool, .reasons: (..out_of_memory))
    ) := {
    assume ffi := self&._ffi
    assume allocator

    found ::= get(.self = self, .key = key, .allocator = allocator)
    match found {
        ..ok payload { result = ..ok payload ?}
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

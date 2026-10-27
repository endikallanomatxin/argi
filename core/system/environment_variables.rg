_EnvironmentVariablesInitArgs := (.ffi: $&ForeignFunctionInterface = reach ffi)

EnvironmentVariables := (._ffi: $&ForeignFunctionInterface)

once _acquire_environment_variables := (.args: _EnvironmentVariablesInitArgs) -> (
    .result : EnvironmentVariables
) {
    ffi ::= args.ffi

    result._ffi = ffi
}

implement Init#(EnvironmentVariables, _EnvironmentVariablesInitArgs) (
    .Result : Type = EnvironmentVariables
    .init   = _acquire_environment_variables
)

environment_variables_get_c_string := (.key: &CChar) -> (
    .result : Errable#(?StringView, (..invalid_utf8))
) {
    raw_ptr ::= getenv(.name = key).value
    raw_addr :: UIntNative = raw_ptr | convert#(.to: UIntNative)(_)
    if raw_addr == 0 {
        result = ..ok ..none
        return
    }
    _ ::= validate_utf8_bytes(.bytes = _c_string_bytes(.text = raw_ptr))!
    result = ..ok ..some(.value = _trusted_c_string_view(.text = raw_ptr))
}

lookup_environment := #(.Provider: Type: Allocator#(Provider)) (
    .self: &EnvironmentVariables, .key: StringView, .allocator: $&Provider
) -> (.result: Errable#(?StringView, (..out_of_memory, ..invalid_utf8))) {
    assume ffi := self&._ffi
    assume allocator

    converted ::= copy_c_string(key, .allocator = allocator)

    match converted {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~c_key {
            result = ..ok environment_variables_get_c_string(.key = c_key.text)!
        }
    }
}

has := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: &EnvironmentVariables, .key: StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(Bool, (..out_of_memory, ..invalid_utf8))) {
    assume ffi := self&._ffi
    assume allocator

    found ::= lookup_environment(self, .key = key, .allocator = allocator)!
    result = ..ok found ?
}

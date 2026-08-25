EnvironmentVariables : Type = ()

once init(.p: $&EnvironmentVariables) -> () := {
}

environment_variables_get_c_string(
    .key: &Char,
) -> (.value: ?StringView) #raw_boundary := {
    raw_ptr ::= getenv(.name = key).value
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = raw_ptr)

    if raw_addr == 0 {
        value = ..none
        return
    }

    value = ..some(.value = (
        .data = cast#(.to: &UInt8)(.value = raw_addr),
        .length = strlen(.string = raw_ptr).length,
    ))
}

get(
    .self: &EnvironmentVariables,
    .key: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.value: ?StringView) := {
    c_key ::= as_c_string(.self = key, .allocator = allocator)
    found ::= environment_variables_get_c_string(.key = c_key.text)
    deinit(.self = $&c_key.storage, .allocator = allocator)
    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

has(
    .self: &EnvironmentVariables,
    .key: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    found ::= get(.self = self, .key = key, .allocator = allocator)
    ok = found?
}

operator get[](
    .self: &EnvironmentVariables,
    .index: StringView,
) -> (.value: ?StringView) := {
    allocator :: CAllocator = CAllocator()
    found ::= get(.self = self, .key = index, .allocator = $&allocator)
    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

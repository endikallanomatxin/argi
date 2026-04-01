EnvironmentVariables : Type = ()

once init(.p: $&EnvironmentVariables) -> () := {
}

get(
    .self: &EnvironmentVariables,
    .key: CString,
) -> (.value: ?StringView) := {
    key_ptr ::= pointer(.self = &key)
    raw_ptr ::= getenv(.name = key_ptr).value
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = raw_ptr)

    if raw_addr == 0 {
        value = ..none
        return
    }

    value = ..some(.value = (
        .data = raw_addr,
        .length = strlen(.string = raw_ptr).length,
    ))
}

get(
    .self: &EnvironmentVariables,
    .key: &String,
) -> (.value: ?StringView) := {
    c_key ::= as_c_string(.self = key)
    found ::= get(.self = self, .key = c_key)
    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

has(
    .self: &EnvironmentVariables,
    .key: CString,
) -> (.ok: Bool) := {
    found ::= get(.self = self, .key = key)
    ok = found?
}

has(
    .self: &EnvironmentVariables,
    .key: &String,
) -> (.ok: Bool) := {
    found ::= get(.self = self, .key = key)
    ok = found?
}

has(
    .self: &EnvironmentVariables,
    .key: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_key ::= as_c_string(.self = key, .allocator = allocator)
    found ::= get(.self = self, .key = c_key.text)
    ok = found?
}

operator get[](
    .self: &EnvironmentVariables,
    .index: CString,
) -> (.value: ?StringView) := {
    found ::= get(.self = self, .key = index)
    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

operator get[](
    .self: &EnvironmentVariables,
    .index: &String,
) -> (.value: ?StringView) := {
    found ::= get(.self = self, .key = index)
    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

operator get[](
    .self: &EnvironmentVariables,
    .index: StringView,
) -> (.value: ?StringView) := {
    allocator :: CAllocator = CAllocator()
    c_key ::= as_c_string(.self = index, .allocator = $&allocator)
    found ::= get(.self = self, .key = c_key.text)
    deinit(.self = $&c_key.storage, .allocator = $&allocator)

    if found? {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

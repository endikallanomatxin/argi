EnvironmentVariables : Type = ()

once init(.p: $&EnvironmentVariables) -> () := {
}

get(
    .self: &EnvironmentVariables,
    .key: CString,
) -> (.value: Nullable#(.t: StringView)) := {
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
) -> (.value: Nullable#(.t: StringView)) := {
    c_key ::= as_c_string(.self = key)
    found ::= get(.self = self, .key = c_key)
    if is(.value = found, .variant = ..some) {
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
    ok = is(.value = found, .variant = ..some)
}

has(
    .self: &EnvironmentVariables,
    .key: &String,
) -> (.ok: Bool) := {
    found ::= get(.self = self, .key = key)
    ok = is(.value = found, .variant = ..some)
}

has(
    .self: &EnvironmentVariables,
    .key: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    c_key ::= as_c_string(.self = key, .allocator = allocator)
    found ::= get(.self = self, .key = c_key.text)
    ok = is(.value = found, .variant = ..some)
}

operator get[](
    .self: &EnvironmentVariables,
    .index: CString,
) -> (.value: Nullable#(.t: StringView)) := {
    found ::= get(.self = self, .key = index)
    if is(.value = found, .variant = ..some) {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

operator get[](
    .self: &EnvironmentVariables,
    .index: &String,
) -> (.value: Nullable#(.t: StringView)) := {
    found ::= get(.self = self, .key = index)
    if is(.value = found, .variant = ..some) {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

operator get[](
    .self: &EnvironmentVariables,
    .index: StringView,
) -> (.value: Nullable#(.t: StringView)) := {
    allocator :: CAllocator = CAllocator()
    c_key ::= as_c_string(.self = index, .allocator = $&allocator)
    found ::= get(.self = self, .key = c_key.text)
    deinit(.self = $&c_key.storage, .allocator = $&allocator)

    if is(.value = found, .variant = ..some) {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

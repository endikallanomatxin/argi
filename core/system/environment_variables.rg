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
) -> (.ok: Bool) := {
    size :: UIntNative = key.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_key : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < key.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_key) + i)
        ptr& = bytes_get(.view = &key, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_key) + key.length)
    nul_ptr& = 0
    c_key : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_key)
    )
    found ::= get(.self = self, .key = c_key)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_key)))
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
    size :: UIntNative = index.length + 1
    raw_buffer : $&Any = malloc(.size = size)
    temp_key : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = raw_buffer))
    i :: UIntNative = 0
    while i < index.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_key) + i)
        ptr& = bytes_get(.view = &index, .index = i).byte
        i = i + 1
    }
    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = temp_key) + index.length)
    nul_ptr& = 0
    c_key : CString = (
        .data = cast#(.to: UIntNative)(.value = temp_key)
    )
    found ::= get(.self = self, .key = c_key)
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = temp_key)))

    if is(.value = found, .variant = ..some) {
        payload ::= found..some
        value = ..some(.value = payload.value)
        return
    }

    value = ..none
}

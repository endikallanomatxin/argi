EnvironmentVariables : Type = ()

init(.p: $&EnvironmentVariables) -> () := {
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

has(
    .self: &EnvironmentVariables,
    .key: CString,
) -> (.ok: Bool) := {
    found ::= get(.self = self, .key = key)
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

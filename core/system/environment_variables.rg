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

Source#(.Participant: Type): Contract = (
    .read : (.self: &Participant) -> (.result: Int32) where {}
)

Local := (.value: Int32)

implement Source#(Local) (.read = _impl_read_Local)

_impl_read_Local := (.self: &Local) -> (.result: Int32) {
    result = self&.value
}

make := (.local: &Local) -> (.result: Virtual#(Source)) {
    result = to_virtual#(Source)(local)
}

main := () -> (.status_code: Int32 = 0) {
    local ::= Local(29)
    source ::= make(&local)

    if read(&source) != 29 { status_code = 1 }
}

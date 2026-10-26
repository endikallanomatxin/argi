A<.Participant: Type>: Contract = (
    .read : (.self: &Participant, .other: &Virtual<.contract: A>) -> (.value: Int32) where {}
)

Box := (.value: Int32)

implement A<Box> (.read = _impl_read_Box)

_impl_read_Box := (.self: &Box, .other: &Virtual<.contract: A>) -> (.value: Int32) {
    value = self&.value
}

main := () -> (.status_code: Int32 = 0) {
    box :: Box = (.value = 7)
    handle ::= to_virtual<.contract: A>(.value = &box)
    value ::= read(.self = &handle, .other = &handle)
    if value != 7 { status_code = 1 }
}

A#(.Participant: Type): Contract = (
    .compare : (.self: &Participant, .other: &Participant) -> (.value: Int32) where {}
)

Box := (.value: Int32)

implement A#(Box) (.compare = _impl_compare_Box)

_impl_compare_Box := (.self: &Box, .other: &Box) -> (.value: Int32) { value = self&.value }

main := () -> (.status_code: Int32 = 0) {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: A)(.value = $&box)
}

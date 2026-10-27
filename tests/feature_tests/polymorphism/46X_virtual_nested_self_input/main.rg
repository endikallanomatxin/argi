Nested := #(.T: Type) (.value: &T)

A#(.Participant: Type): Contract = (
    .inspect : (.self: &Participant, .nested: Nested#(Participant)) -> () where {}
)

Box := (.value: Int32)

implement A#(Box) (.inspect = _impl_inspect_Box)

_impl_inspect_Box := (.self: &Box, .nested: Nested#(Box)) -> () {}

main := () -> (.status_code: Int32 = 0) {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: A)(.value = $&box)
}

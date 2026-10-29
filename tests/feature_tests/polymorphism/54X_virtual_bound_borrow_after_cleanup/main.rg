Readable#(.Participant: Type): Contract = (
    .item : Type

    .read : (.self: &Participant) -> (.value: &item) where depends_on(value, self)
)

Box := (.value: Int32)

implement Deinit#(Box) (
    .deinit = (.self: $&Box) -> () {

    }
)

implement Readable#(Box) (.item: Type = Int32, .read = _impl_read_Box)

_impl_read_Box := (.self: &Box) -> (.value: &Int32) { value = &self&.value }

consume := (.input: &Virtual#(Readable#(.item: Int32))) -> (.value: &Int32) {
    value = read(.self = input)
}

main := () -> () {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: Readable#(.item: Int32))(.value = &box)
    reference ::= consume(.input = &handle).value
    deinit(.self = $&box)
    observed ::= reference&
}

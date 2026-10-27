Forwarder#(.Participant: Type): Contract = (
    .forward : (.self: &Participant, .input: $&Int32) -> (.value: &UInt8)
    where refers_to(value, input)
)

Cell := (.unused: Int32)

implement Forwarder#(Cell) (.forward = _impl_forward_Cell)

global :: UInt8 = 0

_impl_forward_Cell := (.self: &Cell, .input: $&Int32) -> (.value: &UInt8) {
    value = &global
}

main := () -> () {
    cell ::= Cell(0)
    handle ::= to_virtual#(Forwarder)(&cell)
}

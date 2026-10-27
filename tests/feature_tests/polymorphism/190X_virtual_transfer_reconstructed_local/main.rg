Forwarder#(.Participant: Type): Contract = (
    .forward : (.self: &Participant, .input: Owned) -> (.value: Owned) where transfers(
        value, input
    )
)

Cell := (.unused: Int32)

implement Forwarder#(Cell) (.forward = _impl_forward_Cell)

Owned := (.value: Int32)

implement Deinit#(Owned) (
    .deinit = (.self: $&Owned) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_forward_Cell := (.self: &Cell, .input: Owned) -> (.value: Owned) {
    fresh ::= Owned(input.value)
    value = ~fresh
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    forwarder ::= to_virtual#(Forwarder)(&cell)
    value ::= forward(&forwarder, Owned(42))
    if value.value != 42 { status_code = 1 }
    deinit($&value)
    if drops != 1 { status_code = 1 }
}

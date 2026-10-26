Drain<.Participant: Type>: Contract = (
    .drain : (.self: &Participant, .storage: $&Allocation) -> () where empties(storage)
)

Cell: Type = ()

implement Drain<Cell> (.drain = _impl_drain_Cell)

_impl_drain_Cell := (.self: &Cell, .storage: $&Allocation) -> () {}

main := () -> () {
    cell ::= Cell()
    _ ::= to_virtual<Drain>(&cell)
}

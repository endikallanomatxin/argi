Drain<.Participant: Type>: Contract = (
    .drain : (.self: &Participant, .storage: $&Allocation, .clear: Bool) -> () where empties(
        storage
    )
)

Cell: Type = ()

implement Drain<Cell> (.drain = _impl_drain_Cell)

_impl_drain_Cell := (.self: &Cell, .storage: $&Allocation, .clear: Bool) -> () {
    if clear { trusted_opaque_mark_empty(storage) }
}

main := () -> () {
    cell ::= Cell()
    _ ::= to_virtual<Drain>(&cell)
}

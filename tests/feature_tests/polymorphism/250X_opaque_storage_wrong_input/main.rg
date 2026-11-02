Store#(.Participant: Type): Contract = (
    .put : (
        .self    : &Participant,
        .storage : $&Allocation,
        .slot    : $&Tracked,
        .value   : Tracked,
        .other   : Tracked
    ) -> () where {
        retains(storage, value)
    }
)

Tracked := (.reference: &Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {

    }
)

Cell: Type = ()

implement Store#(Cell) (.put = _impl_put_Cell)

_impl_put_Cell := (
    .self: &Cell, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked, .other: Tracked
) -> () {
    trusted_opaque_move_in#(Tracked, Allocation)(storage, slot, ~other)
}

main := () -> () {
    cell ::= Cell()
    _ ::= to_virtual#(Store)(&cell)
}

Store: Abstract = (
    put(.self: &Self, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked, .other: Tracked) -> () where {
        retains(storage, value)
    }
)

Tracked: Type = (.reference: &Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {

    }
)

Cell: Type = ()

Cell implements Store

put(.self: &Cell, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked, .other: Tracked) -> () := {
    trusted_opaque_move_in#(Tracked, Allocation)(storage, slot, ~other)
}

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Store)(&cell)
}

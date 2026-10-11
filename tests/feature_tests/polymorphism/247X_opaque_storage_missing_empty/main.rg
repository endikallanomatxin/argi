Drain: Abstract = (
    drain(.self: &Self, .storage: $&Allocation) -> () where empties(storage)
)

Cell: Type = ()

Cell implements Drain

drain(.self: &Cell, .storage: $&Allocation) -> () := {}

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Drain)(&cell)
}

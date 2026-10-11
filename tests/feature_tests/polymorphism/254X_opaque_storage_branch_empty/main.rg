Drain: Abstract = (
    drain(.self: &Self, .storage: $&Allocation, .clear: Bool) -> () where empties(storage)
)

Cell: Type = ()

Cell implements Drain

drain(.self: &Cell, .storage: $&Allocation, .clear: Bool) -> () := {
    if clear { trusted_opaque_mark_empty(storage) }
}

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Drain)(&cell)
}

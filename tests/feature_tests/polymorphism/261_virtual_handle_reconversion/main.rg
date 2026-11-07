Counter#(.Participant: Type): Contract = (
    .bump: (.self: $&Participant) -> () where {}
)

Cell := (.value: Int32)

implement Counter#(Cell) (
    .bump = (.self: $&Cell) -> () { self&.value = self&.value + 1 }
)

-- The copy retains the concrete receiver, not the intermediate handle's slot.
forward := (.cell: $&Cell) -> (.result: Virtual#(Counter)) {
    intermediate ::= Virtual#(Counter)(cell)
    result = Virtual#(Counter)($&intermediate)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    handle ::= forward($&cell)
    bump($&handle)
    repeated ::= Virtual#(Counter)($&handle)
    bump($&repeated)
    if cell.value != 2 { abort }
}

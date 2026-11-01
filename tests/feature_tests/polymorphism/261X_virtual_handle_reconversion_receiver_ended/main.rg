Counter#(.Participant: Type): Contract = (
    .bump: (.self: $&Participant) -> () where {}
)

Cell := (.value: Int32)

implement Deinit#(Cell) (.deinit = (.self: $&Cell) -> () {})

implement Counter#(Cell) (
    .bump = (.self: $&Cell) -> () { self&.value = self&.value + 1 }
)

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    first ::= to_virtual#(Counter)($&cell)
    second ::= to_virtual#(Counter)($&first)
    deinit($&cell)
    bump($&second)
}

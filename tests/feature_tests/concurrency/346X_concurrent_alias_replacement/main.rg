Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cell ::= Cell(1)
    shared ::= $$&cell
    cell = Cell(2)
}

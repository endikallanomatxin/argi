Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cells :: [2]Cell = (Cell(1), Cell(2))
    shared ::= $$&cells[0]
    if cells[1].value != 2 { abort }
    recover_ordinary(.owner = $&cells[0])
    if cells[0].value != 1 { abort }
}

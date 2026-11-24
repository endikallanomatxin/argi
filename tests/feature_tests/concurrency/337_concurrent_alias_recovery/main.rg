Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cell ::= Cell(1)
    shared ::= $$&cell
    recover_ordinary(.owner = $&cell)
    cell.value = 2
    if cell.value != 2 { abort }
}

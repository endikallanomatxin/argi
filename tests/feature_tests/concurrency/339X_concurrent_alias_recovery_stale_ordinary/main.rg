Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cell ::= Cell(1)
    old ::= &cell
    shared ::= $$&cell
    recover_ordinary(.owner = $&cell)
    if old&.value == 0 { abort }
}

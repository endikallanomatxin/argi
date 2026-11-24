Cell := (.value: Int32)
Pair := (.left: Cell, .right: Cell)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cell ::= Cell(1)
    old ::= &cell.value
    shared ::= $$&cell
    x ::= old&
}

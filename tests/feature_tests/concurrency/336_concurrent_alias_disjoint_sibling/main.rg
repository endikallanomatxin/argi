Cell := (.value: Int32)
Pair := (.left: Cell, .right: Cell)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    pair ::= Pair(Cell(1), Cell(2))
    shared ::= $$&pair.left
    pair.right.value = 3
    if pair.right.value != 3 { abort }
}

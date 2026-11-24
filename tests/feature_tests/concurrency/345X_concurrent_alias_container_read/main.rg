Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
Pair := (.left: Cell, .right: Cell)
sum := (.pair: Pair) -> (.value: Int32) { value = pair.left.value + pair.right.value }

main := () -> () {
    pair ::= Pair(Cell(1), Cell(2))
    shared ::= $$&pair.left
    if sum(pair) != 3 { abort }
}

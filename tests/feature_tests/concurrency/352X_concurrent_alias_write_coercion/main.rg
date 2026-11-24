Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
set := (.cell: $&Cell) -> () { cell&.value = 7 }

main := () -> () {
    cell ::= Cell(0)
    shared ::= $$&cell
    set(shared)
}

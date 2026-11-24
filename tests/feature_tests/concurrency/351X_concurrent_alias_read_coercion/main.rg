Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
observe := (.cell: &Cell) -> (.n: Int32) { n = cell&.value }

main := () -> () {
    cell ::= Cell(0)
    shared ::= $$&cell
    if observe(shared).n == 0 { abort }
}

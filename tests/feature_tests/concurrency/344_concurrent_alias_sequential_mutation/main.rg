Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    cell ::= Cell(0)
    first ::= $&cell
    second ::= $&cell
    first&.value = 1
    second&.value = first&.value + 1
    if cell.value != 2 { abort }
}

Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

read_after_branch := (.share: Bool) -> (.result: Int32) {
    cell ::= Cell(0)
    if share {
        handle ::= $$&cell
    }
    result = cell.value
}

main := () -> () {
    if read_after_branch(true).result != 0 { abort }
}

Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()


observe := (.shared: $$&Cell) -> (.value: Int32) {
    view ::= trusted_concurrent_view(.shared = shared)
    value = view&.value
}

main := () -> () {
    cell ::= Cell(1)
    shared ::= $$&cell
    aliases :: [2]$$&Cell = (shared, shared)
    recover_ordinary(.owner = $&cell)
    if observe(aliases[1]).value == 0 { abort }
}

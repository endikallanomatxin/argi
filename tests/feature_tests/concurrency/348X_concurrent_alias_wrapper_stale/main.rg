Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()

Wrapper := (.handle: $$&Cell)
wrap := (.handle: $$&Cell) -> (.result: Wrapper) { result = (.handle = handle) }
observe := (.shared: $$&Cell) -> (.value: Int32) {
    view ::= trusted_concurrent_view(.shared = shared)
    value = view&.value
}

main := () -> () {
    cell ::= Cell(1)
    shared ::= $$&cell
    box ::= wrap(shared)
    recover_ordinary(.owner = $&cell)
    if observe(box.handle).value == 0 { abort }
}

Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
observe := (.cell: &Cell) -> (.value: Int32) { value = cell&.value }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= Cell(1)
    task ::= unwrap_or_abort(async#(observe)(.args = (.cell = &cell)))
    shared ::= $$&cell
    _ = unwrap_or_abort(await($&task))
}

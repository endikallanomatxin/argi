_probe() -> (.value: Int32): CFunction(.symbol = "external_probe") where { no_access() }
Cell := (.ffi: $&ForeignFunctionInterface)
implement ConcurrentAlias#(Cell) ()
read := (.cell: $$&Cell) -> (.value: Int32) {
    view ::= trusted_concurrent_view(.shared = cell)
    value = _probe(.ffi = view&.ffi).value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= Cell(system.ffi)
    shared ::= $$&cell
    task ::= unwrap_or_abort(async#(read)(.args = (.cell = shared)))
    _ = unwrap_or_abort(await($&task))
    recover_ordinary(.owner = $&cell)
}

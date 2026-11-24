increment := (.cell: $$&AtomicUInt32) -> (.previous: UInt32) {
    previous = shared_fetch_add(.self = cell, .value = 1).previous
}

start := (.cell: $$&AtomicUInt32, .executor: Virtual#(Executor)) -> (.task: Future#(result_of#(increment))) {
    task = unwrap_or_abort(async#(increment)(.args = (.cell = cell), .executor = executor))
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    first ::= start(.cell = shared, .executor = executor)
    second ::= start(.cell = shared, .executor = executor)
    _ = unwrap_or_abort(await($&first))
    _ = unwrap_or_abort(await($&second))
    recover_ordinary(.owner = $&cell)
    if load(.self = &cell).value != 2 { abort }
}

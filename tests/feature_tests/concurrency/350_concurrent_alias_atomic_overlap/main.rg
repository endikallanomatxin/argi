increment := (.cell: $$&AtomicUInt32) -> (.previous: UInt32) {
    previous = shared_fetch_add(.self = cell, .value = 1).previous
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    first ::= unwrap_or_abort(async#(increment)(.args = (.cell = shared)))
    second ::= unwrap_or_abort(async#(increment)(.args = (.cell = shared)))
    _ = shared_fetch_add(.self = shared, .value = 1)
    _ = unwrap_or_abort(await($&first))
    _ = unwrap_or_abort(await($&second))
    recover_ordinary(.owner = $&cell)
    if load(.self = &cell).value != 3 { abort }
}

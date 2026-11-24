CounterOps#(.T: Type): Contract = (
    .increment: (.self: $$&T) -> (.previous: UInt32) where { no_access() isolated() }
)
implement CounterOps#(AtomicUInt32) (
    .increment = (.self: $$&AtomicUInt32) -> (.previous: UInt32) {
        previous = shared_fetch_add(.self = self, .value = 1).previous
    }
)

increment := (.cell: $$&AtomicUInt32) -> (.previous: UInt32) {
    counter ::= Virtual#(CounterOps)(cell)
    previous = CounterOps#().increment(&counter).previous
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    first ::= unwrap_or_abort(async#(increment)(.args = (.cell = shared)))
    second ::= unwrap_or_abort(async#(increment)(.args = (.cell = shared)))
    _ = unwrap_or_abort(await($&first))
    _ = unwrap_or_abort(await($&second))
    recover_ordinary(.owner = $&cell)
    if load(.self = &cell).value != 2 { abort }
}

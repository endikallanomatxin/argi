CounterOps#(.Receiver: Type): Contract = (
    .increment: (.self: Receiver) -> (.previous: UInt32) where { writes(self) isolated() }
)
implement CounterOps#($$&AtomicUInt32) (
    .increment = (.self: $$&AtomicUInt32) -> (.previous: UInt32) {
        previous = shared_fetch_add(.self = self, .value = 1).previous
    }
)

increment := (.counter: Virtual#(CounterOps)) -> (.previous: UInt32) {
    previous = counter.increment().previous
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    counter ::= Virtual#(CounterOps)(shared)
    first ::= unwrap_or_abort(async#(increment)(.args = (.counter = counter)))
    second ::= unwrap_or_abort(async#(increment)(.args = (.counter = counter)))
    _ = unwrap_or_abort(await($&first))
    _ = unwrap_or_abort(await($&second))
    recover_ordinary(.owner = $&cell)
    if load(.self = &cell).value != 2 { abort }
}

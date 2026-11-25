write := (.target: $&Int32) -> () { target& = 42 }
start := (
    .target: $&Int32,
    .saved: $&?Future#(Void),
    .executor: Virtual#(Executor)
) -> (.result: Int32) {
    assume executor
    future ::= unwrap_or_abort(async#(write)(.args = (.target = target)))
    saved& = ..some(.value = ~future)
    result = 7
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    saved :: ?Future#(Void) = ..none
    value = start(.target = $&value, .saved = $&saved)
    match ~saved {
        ..some ~entry {
            future ::= ~entry.value
            _ = unwrap_or_abort(await($&future))
        }
        ..none { abort }
    }
}

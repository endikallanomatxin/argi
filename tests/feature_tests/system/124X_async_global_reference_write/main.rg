counter :: Int32 = 0
write := (.target: $&Int32) -> () { target& = 42 }
work := () -> () {
    alias ::= $&counter
    write(.target = alias)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}

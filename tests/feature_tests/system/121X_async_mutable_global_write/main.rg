counter :: Int32 = 0
write_counter := () -> () { counter = 42 }
work := () -> () { write_counter() }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}

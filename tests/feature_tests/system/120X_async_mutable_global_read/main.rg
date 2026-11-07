counter :: Int32 = 42
read_counter := () -> (.result: Int32) { result = counter }
work := () -> (.result: Int32) { result = read_counter() }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}

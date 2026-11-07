compute := () -> (.result: Int32) { result = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(compute)(.args = ()))
    copied := future
    _ = copied
}

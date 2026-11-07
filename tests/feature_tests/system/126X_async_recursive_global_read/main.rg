counter :: Int32 = 42
first := (.n: Int32) -> (.result: Int32) {
    if n == 0 { result = counter return }
    result = second(.n = n - 1)
}
second := (.n: Int32) -> (.result: Int32) { result = first(.n = n) }
work := () -> (.result: Int32) { result = second(.n = 1) }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}

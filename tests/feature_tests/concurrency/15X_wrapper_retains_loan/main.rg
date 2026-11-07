write := (.value: $&Int32) -> () { value& = 42 }
start := (.value: $&Int32, .executor: Virtual#(Executor)) -> (.result: Future#(Void)) {
    assume executor
    result = unwrap_or_abort(.value = async#(write)(.args = (.value = value)))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 1
    future ::= start(.value = $&value)
    value = 2
    _ = unwrap_or_abort(.value = await($&future))
}

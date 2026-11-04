write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
start := (.executor: Virtual#(Executor)) -> (.result: Future#(Void)) {
    assume executor
    local :: Int32 = 1
    result = unwrap_or_abort(.value = async#(write)(.args = (.value = $&local)))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= start()
    _ = unwrap_or_abort(.value = await($&future))
}

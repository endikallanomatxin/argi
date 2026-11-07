write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
start := (.value: $&Int32, .executor: Virtual#(Executor)) -> (.result: Future#(Void)) {
    assume executor
    result = unwrap_or_abort(.value = async#(write)(.args = (.value = value)))
}
finish := (.future: $&Future#(Void)) -> () {
    _ = unwrap_or_abort(.value = await(future))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 1
    future ::= start(.value = $&value)
    finish(.future = $&future)
    if value != 42 { abort }
}

read := (.value: &Int32) -> (.result: Int32) { result = value& }
start := (.value: &Int32, .executor: Virtual#(Executor)) -> (.result: Future#(Int32)) {
    assume executor
    result = unwrap_or_abort(.value = async#(read)(.args = (.value = value)))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    first ::= start(.value = &value)
    second ::= start(.value = &value)
    if unwrap_or_abort(.value = await($&first)) != 42 { abort }
    if value != 42 { abort }
    if unwrap_or_abort(.value = await($&second)) != 42 { abort }
    value = 7
    if value != 7 { abort }
}

read := (.value: &Int32) -> (.result: Int32) { result = value& }
finish_after_write := (.future: $&Future#(Int32), .value: $&Int32) -> () {
    value& = 7
    _ = unwrap_or_abort(.value = await(future))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    finish_after_write(.future = $&future, .value = $&value)
}

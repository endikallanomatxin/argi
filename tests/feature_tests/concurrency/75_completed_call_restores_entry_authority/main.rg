read := (.value: &Int32) -> (.result: Int32) { result = value& }
finish := (.future: $&Future#(Int32)) -> () {
    _ = unwrap_or_abort(.value = await(future))
}
write := (.value: $&Int32) -> () { value& = 7 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    finish(.future = $&future)
    write(.value = $&value)
    if value != 7 { abort }
}

read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.read_value: &Int32, .write_value: $&Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = read_value), .executor = executor))
    write_value& = 7
    _ = unwrap_or_abort(.value = await($&future))
}
forward := (.first: &Int32, .second: $&Int32, .executor: Virtual#(Executor)) -> () {
    work(.read_value = first, .write_value = second, .executor = executor)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    forward(.first = &value, .second = $&value, .executor = executor)
}

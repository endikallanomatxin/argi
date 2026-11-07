Number: CUnion = (.first: Int32, .second: Int32)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.read_value: &Int32, .write_value: $&Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = read_value), .executor = executor))
    write_value& = 7
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    value: Number = (.first = 42)
    work(.read_value = &value.first, .write_value = $&value.second, .executor = executor)
}

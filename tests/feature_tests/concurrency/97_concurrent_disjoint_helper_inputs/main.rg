read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.read_value: &Int32, .write_value: $&Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = read_value), .executor = executor))
    write_value& = 7
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 42
    other :: Int32 = 0
    work(.read_value = &value, .write_value = $&other, .executor = executor)
    if value != 42 or other != 7 { abort }
}

read := (.value: &Int32) -> (.result: Int32) { result = value& }
Inputs := (.read_value: &Int32, .write_value: $&Int32)
work := (.inputs: Inputs, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = inputs.read_value), .executor = executor))
    inputs.write_value& = 7
    _ = unwrap_or_abort(.value = await($&future))
}
forward := (.inputs: Inputs, .executor: Virtual#(Executor)) -> () {
    work(.inputs = inputs, .executor = executor)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    forward(.inputs = (.read_value = &value, .write_value = $&value), .executor = executor)
}

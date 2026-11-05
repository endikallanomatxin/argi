Number: CUnion = (.first: Int32, .second: Int32)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value: Number = (.first = 7)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value.second)))
    value.first = 42
    _ = unwrap_or_abort(.value = await($&future))
}

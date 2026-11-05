Number: CUnion = (.first: Int32, .second: Int32)
Envelope := (.number: Number)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value: Envelope = (.number = (.first = 7))
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value.number.second)))
    value.number.first = 42
    _ = unwrap_or_abort(.value = await($&future))
}

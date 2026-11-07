Number: CUnion = (.first: Int32, .second: Int32)
write := (.value: $&Int32) -> (.result: Int32) { value& = 42 result = value& }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value: Number = (.first = 7)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value.second)))
    other ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value.first)))
    _ = unwrap_or_abort(.value = await($&other))
    _ = unwrap_or_abort(.value = await($&future))
}

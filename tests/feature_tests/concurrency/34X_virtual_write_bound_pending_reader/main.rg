AccessWriter#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .value: $&Int32) -> () where { writes(value) invalidates(value) }
)
Provider := (.marker: Int32)
implement AccessWriter#(Provider) (
    .set = (.self: &Provider, .value: $&Int32) -> () { value& = 42 }
)
forward := (.writer: Virtual#(AccessWriter), .value: $&Int32) -> () {
    AccessWriter#().set(.self = &writer, .value = value)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    provider: Provider = (.marker = 0)
    writer ::= Virtual#(AccessWriter)(&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    forward(.writer = writer, .value = $&value)
}

AccessReader#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .value: &Int32) -> (.result: Int32) where { reads(value) }
)
AccessWriter#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .value: $&Int32) -> () where { writes(value) invalidates(value) }
)
PureValue#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { no_access() }
)
Provider := (.marker: Int32)
implement AccessReader#(Provider) (
    .get = (.self: &Provider, .value: &Int32) -> (.result: Int32) { result = value& }
)
implement AccessWriter#(Provider) (
    .set = (.self: &Provider, .value: $&Int32) -> () { value& = 42 }
)
implement PureValue#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = 42 }
)
forward := (.reader: Virtual#(AccessReader), .value: &Int32) -> (.result: Int32) {
    result = AccessReader#().get(.self = &reader, .value = value)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    provider: Provider = (.marker = 0)
    reader ::= to_virtual#(AccessReader)(&provider)
    writer ::= to_virtual#(AccessWriter)(&provider)
    pure ::= to_virtual#(PureValue)(&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if forward(.reader = reader, .value = &value) != 42 { abort }
    if PureValue#().get(.self = &pure) != 42 { abort }
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
    AccessWriter#().set(.self = &writer, .value = $&value)
}

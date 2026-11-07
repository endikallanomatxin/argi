Context := (.counter: $&Int32)
Inspect#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .context: Context) -> (.result: Int32) where { reads(context.counter) }
)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: Context) -> () where { writes(context.counter) }
)
Provider := (.marker: Int32)
implement Inspect#(Provider) (
    .get = (.self: &Provider, .context: Context) -> (.result: Int32) { result = context.counter& }
)
implement Update#(Provider) (
    .set = (.self: &Provider, .context: Context) -> () { context.counter& = 42 }
)
forward := (.reader: Virtual#(Inspect), .context: Context) -> (.result: Int32) {
    result = Inspect#().get(.self = &reader, .context = context)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    provider: Provider = (.marker = 0)
    reader ::= Virtual#(Inspect)(&provider)
    writer ::= Virtual#(Update)(&provider)
    value :: Int32 = 7
    context: Context = (.counter = $&value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if forward(.reader = reader, .context = context) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    Update#().set(.self = &writer, .context = context)
    if value != 42 { abort }
}

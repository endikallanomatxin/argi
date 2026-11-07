Context := (.counter: $&Int32)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: Context) -> () where { writes(context.counter) }
)
Provider := (.marker: Int32)
implement Update#(Provider) (
    .set = (.self: &Provider, .context: Context) -> () { context.counter& = 42 }
)
forward := (.writer: Virtual#(Update), .context: Context) -> () {
    Update#().set(.self = &writer, .context = context)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    provider: Provider = (.marker = 0)
    writer ::= Virtual#(Update)(&provider)
    value :: Int32 = 7
    context: Context = (.counter = $&value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    forward(.writer = writer, .context = context)
}

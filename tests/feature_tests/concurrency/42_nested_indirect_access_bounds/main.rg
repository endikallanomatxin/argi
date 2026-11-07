Counter := (.value: $&Int32)
Context := (.counter: &Counter)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: Context) -> () where {
        reads(context.counter)
        writes(context.counter.value)
    }
)
Provider := (.marker: Int32)
implement Update#(Provider) (
    .set = (.self: &Provider, .context: Context) -> () {
        context.counter&.value& = 42
    }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    writer ::= Virtual#(Update)(&provider)
    value :: Int32 = 7
    counter: Counter = (.value = $&value)
    context: Context = (.counter = &counter)
    Update#().set(.self = &writer, .context = context)
    if value != 42 { abort }
}

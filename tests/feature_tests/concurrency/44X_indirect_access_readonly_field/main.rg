Context := (.counter: &Int32)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: Context) -> () where { writes(context.counter) }
)
Provider := (.marker: Int32)
implement Update#(Provider) (
    .set = (.self: &Provider, .context: Context) -> () {}
)
main := () -> () {
    provider: Provider = (.marker = 0)
    writer ::= to_virtual#(Update)(&provider)
    value :: Int32 = 7
    Update#().set(.self = &writer, .context = (.counter = &value))
}

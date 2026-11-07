Context := (.counter: $&Int32, .other: $&Int32)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: Context) -> () where { writes(context.counter) }
)
Provider := (.marker: Int32)
implement Update#(Provider) (
    .set = (.self: &Provider, .context: Context) -> () { context.other& = 42 }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    writer ::= Virtual#(Update)(&provider)
    value :: Int32 = 7
    other :: Int32 = 0
    Update#().set(.self = &writer, .context = (.counter = $&value, .other = $&other))
}

Context := (.counter: &Int32)
Inspect#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .context: Context) -> () where { reads(context.missing) }
)
Provider := (.marker: Int32)
implement Inspect#(Provider) (.get = (.self: &Provider, .context: Context) -> () {})
main := () -> () {
    provider: Provider = (.marker = 0)
    reader ::= Virtual#(Inspect)(&provider)
    value :: Int32 = 7
    Inspect#().get(.self = &reader, .context = (.counter = &value))
}

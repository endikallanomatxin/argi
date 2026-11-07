foreign := import("./foreign")
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .context: foreign.Context) -> () where { writes(context._counter) }
)
Provider := (.marker: Int32)
implement Update#(Provider) (.set = (.self: &Provider, .context: foreign.Context) -> () {})
main := () -> () {
    provider: Provider = (.marker = 0)
    writer ::= Virtual#(Update)(&provider)
    value :: Int32 = 7
    Update#().set(.self = &writer, .context = foreign.make(.value = $&value))
}

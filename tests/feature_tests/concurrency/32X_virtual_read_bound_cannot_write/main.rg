ReadOnly#(.Provider: Type): Contract = (
    .apply: (.self: &Provider, .value: $&Int32) -> () where { reads(value) }
)
Provider := (.marker: Int32)
write := (.value: $&Int32) -> () { value& = 42 }
implement ReadOnly#(Provider) (
    .apply = (.self: &Provider, .value: $&Int32) -> () { write(.value = value) }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    reader ::= Virtual#(ReadOnly)(&provider)
    value :: Int32 = 0
    ReadOnly#().apply(.self = &reader, .value = $&value)
}

Operation#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .source: $&Int32, .destination: $&Int32) -> () where { no_access() }
)
Provider := (.marker: Int32)
implement Operation#(Provider) (
    .run = (.self: &Provider, .source: $&Int32, .destination: $&Int32) -> () { trusted_opaque_drop#(Int32)(.slot = source) }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    operation ::= to_virtual#(Operation)(&provider)
}

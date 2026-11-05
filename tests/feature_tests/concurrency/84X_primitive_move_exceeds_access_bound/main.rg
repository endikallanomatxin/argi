Operation#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .source: $&Int32, .destination: $&Int32) -> () where { reads(source) writes(destination) }
)
Provider := (.marker: Int32)
implement Operation#(Provider) (
    .run = (.self: &Provider, .source: $&Int32, .destination: $&Int32) -> () { relocate#(Int32)(.source = source, .destination = destination) }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    operation ::= to_virtual#(Operation)(&provider)
}

Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider) -> () where { reads(self) writes(self.counter) }
)
Provider := (.counter: $&Int32)
implement Update#(Provider) (
    .set = (.self: &Provider) -> () { self&.counter& = 42 }
)
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (.counter = $&value)
    Update#(Provider).set(.self = &provider)
    if value != 42 { abort }
}

Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
)
Cell := (.value: Int32)
Holder := (.target: &Cell)
Provider := (.holder: &Holder)
implement Counter#(Provider) (
    .state = region(self.holder.target.value)
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.holder&.target&.value }
)
forward := (.counter: Virtual#(Counter)) -> (.result: Virtual#(Counter)) { result = counter }
main := () -> () {
    first ::= Cell(7)
    second ::= Cell(9)
    first_holder: Holder = (.target = &first)
    second_holder: Holder = (.target = &second)
    provider: Provider = (.holder = &first_holder)
    counter ::= forward(to_virtual#(Counter)(&provider))
    provider.holder = &second_holder
    _ = Counter#().get(&counter)
}

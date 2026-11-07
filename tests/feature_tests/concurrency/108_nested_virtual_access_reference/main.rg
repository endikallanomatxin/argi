Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
)
Provider := (.value: &Int32)
Holder := (.counter: Virtual#(Counter))
implement Counter#(Provider) (
    .state = region(self.value),
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.value& }
)
read_holder := (.holder: &Holder) -> (.result: Int32) {
    result = Counter#().get(.self = &holder&.counter)
}
main := () -> () {
    value :: Int32 = 42
    provider: Provider = (.value = &value)
    holder: Holder = (.counter = Virtual#(Counter)(&provider))
    if read_holder(.holder = &holder) != 42 { abort }
}

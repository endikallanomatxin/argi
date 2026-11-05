Counter#(.Provider: Type): Contract = (
    domain state
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
)
Provider := (.value: &Int32)
Holder := (.counter: Virtual#(Counter))
implement Counter#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.value& }
) where { state(self.value) }
read_holder := (.holder: Holder) -> (.result: Int32) {
    result = Counter#().get(.self = &holder.counter)
}
main := () -> () {
    value :: Int32 = 42
    provider: Provider = (.value = &value)
    holder: Holder = (.counter = to_virtual#(Counter)(&provider))
    if read_holder(.holder = holder) != 42 { abort }
}

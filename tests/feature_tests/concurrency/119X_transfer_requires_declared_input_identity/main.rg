Counter#(.Provider: Type): Contract = (
    domain state
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
    .set: (.self: &Provider) -> () where writes(self.state)
)
CounterProvider := (.value: $&Int32)
implement Counter#(CounterProvider) (
    .get = (.self: &CounterProvider) -> (.result: Int32) { result = self&.value& },
    .set = (.self: &CounterProvider) -> () { self&.value& = 42 }
) where { state(self.value) }
RelayProvider := (.marker: Int32)
Relay#(.Provider: Type): Contract = (
    .forward: (.self: &Provider, .source: Virtual#(Counter), .other: Virtual#(Counter)) -> (.result: Virtual#(Counter)) where {
        no_access()
        transfers(result, source)
    }
)
implement Relay#(RelayProvider) (
    .forward = (.self: &RelayProvider, .source: Virtual#(Counter), .other: Virtual#(Counter)) -> (.result: Virtual#(Counter)) {
        result = ~other
    }
)
main := () -> () {
    relay_provider ::= RelayProvider(0)
    relay ::= to_virtual#(Relay)(&relay_provider)
    first :: Int32 = 7
    second :: Int32 = 9
    first_provider: CounterProvider = (.value = $&first)
    second_provider: CounterProvider = (.value = $&second)
    first_counter ::= to_virtual#(Counter)(&first_provider)
    second_counter ::= to_virtual#(Counter)(&second_provider)
    _ = Relay#().forward(&relay, ~first_counter, ~second_counter)
}

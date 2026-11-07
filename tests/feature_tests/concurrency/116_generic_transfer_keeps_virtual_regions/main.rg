Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
    .set: (.self: &Provider) -> () where writes(self.state)
)
CounterProvider := (.value: $&Int32)
implement Counter#(CounterProvider) (
    .state = region(self.value),
    .get = (.self: &CounterProvider) -> (.result: Int32) { result = self&.value& },
    .set = (.self: &CounterProvider) -> () { self&.value& = 42 }
)
Holder := (.counter: Virtual#(Counter))
RelayProvider := #(.Item: Type) (.marker: Int32)
Relay#(.Provider: Type): Contract = (
    .Item: Type
    .forward: (.self: &Provider, .source: Item) -> (.result: Item) where {
        no_access()
        transfers(result, source)
    }
)
implement#(.T: Type) Relay#(RelayProvider#(T)) (
    .Item: Type = T,
    .forward = (.self: &RelayProvider#(T), .source: T) -> (.result: T) {
        forwarded ::= ~source
        result = ~forwarded
    }
)
forward_again := #(.T: Type) (
    .relay: Virtual#(Relay#(.Item: T)), .source: T
) -> (.result: T) {
    result = Relay#(.Item: T).forward(.self = &relay, .source = ~source)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    relay_provider ::= RelayProvider#(Holder)(0)
    relay ::= Virtual#(Relay#(.Item: Holder))(&relay_provider)
    value :: Int32 = 7
    counter_provider: CounterProvider = (.value = $&value)
    holder: Holder = (.counter = Virtual#(Counter)(&counter_provider))
    forwarded ::= forward_again#(Holder)(.relay = relay, .source = ~holder)
    if Counter#().get(&forwarded.counter) != 7 { abort }
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if Counter#().get(&forwarded.counter) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    Counter#().set(&forwarded.counter)
    if value != 42 { abort }
}

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
    .forward: (.self: &Provider, .source: &Virtual#(Counter)) -> (.result: Virtual#(Counter)) where {
        reads(source)
        depends_on(result, source)
    }
)
implement Relay#(RelayProvider) (
    .forward = (.self: &RelayProvider, .source: &Virtual#(Counter)) -> (.result: Virtual#(Counter)) {
        result = source&
    }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    relay_provider ::= RelayProvider(0)
    relay ::= to_virtual#(Relay)(&relay_provider)
    value :: Int32 = 7
    counter_provider: CounterProvider = (.value = $&value)
    counter ::= to_virtual#(Counter)(&counter_provider)
    forwarded ::= Relay#().forward(.self = &relay, .source = &counter)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    _ = Counter#().get(&forwarded)
    _ = unwrap_or_abort(.value = await($&future))
}

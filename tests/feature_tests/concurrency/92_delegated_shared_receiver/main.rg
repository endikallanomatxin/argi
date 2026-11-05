Counter#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self) }
)
ForwardCounter#(.Provider: Type): Contract = (
    .target: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.target) }
)
CounterState := (.value: Int32)
Forwarder := (.base: Virtual#(Counter))
implement Counter#(CounterState) (
    .get = (.self: &CounterState) -> (.result: Int32) { result = self&.value }
)
implement ForwardCounter#(Forwarder) (
    .target = region(self.base),
    .get = (.self: &Forwarder) -> (.result: Int32) { result = Counter#().get(.self = &self&.base) }
)
read := (.value: &CounterState) -> (.result: Int32) { result = value&.value }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    state: CounterState = (.value = 7)
    forwarder: Forwarder = (.base = to_virtual#(Counter)($&state))
    counter ::= to_virtual#(ForwardCounter)($&forwarder)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &state)))
    if ForwardCounter#().get(.self = &counter) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
}

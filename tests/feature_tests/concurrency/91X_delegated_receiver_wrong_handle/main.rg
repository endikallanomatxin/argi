Counter#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { writes(self) }
)
ForwardCounter#(.Provider: Type): Contract = (
    .target: Region#(Provider)
    .set: (.self: $&Provider) -> () where { writes(self.target) }
)
CounterState := (.value: Int32)
Forwarder := (.base: Virtual#(Counter), .other: Virtual#(Counter))
implement Counter#(CounterState) (
    .set = (.self: $&CounterState) -> () { self&.value = 42 }
)
implement ForwardCounter#(Forwarder) (
    .target = region(self.base),
    .set = (.self: $&Forwarder) -> () { Counter#().set(.self = $&self&.other) }
)
read := (.value: &CounterState) -> (.result: Int32) { result = value&.value }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    state: CounterState = (.value = 7)
    forwarder: Forwarder = (.base = Virtual#(Counter)($&state), .other = Virtual#(Counter)($&state))
    counter ::= Virtual#(ForwardCounter)($&forwarder)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &state)))
    _ = unwrap_or_abort(.value = await($&future))
    ForwardCounter#().set(.self = $&counter)
    if state.value != 42 { abort }
}

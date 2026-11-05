Counter#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (.value: $&Int32)
Holder := (.counter: Virtual#(Counter))
implement Counter#(Provider) (
    .set = (.self: &Provider) -> () { self&.value& = 42 }
) where { state(self.value) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.holder: Holder, .value: &Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = value), .executor = executor))
    Counter#().set(.self = &holder.counter)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (.value = $&value)
    holder: Holder = (.counter = to_virtual#(Counter)(&provider))
    work(.holder = holder, .value = &value, .executor = executor)
}

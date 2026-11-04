CounterAccess#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .set = (.self: &Provider) -> () { self&._counter& = 42 }
) where { state(self._counter) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
perform := (.counter: Virtual#(CounterAccess), .value: $&Int32, .executor: Virtual#(Executor)) -> () {
    assume executor
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value&)))
    CounterAccess#().set(.self = &counter)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    counter ::= to_virtual#(CounterAccess)(&provider)
    perform(.counter = counter, .value = $&value, .executor = executor)
}

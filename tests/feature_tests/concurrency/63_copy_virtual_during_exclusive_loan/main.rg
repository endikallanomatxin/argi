CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._counter& }
)
write := (.value: $&Int32) -> () { value& = 42 }
perform := (.counter: Virtual#(CounterAccess), .value: $&Int32, .executor: Virtual#(Executor)) -> () {
    assume executor
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = value)))
    copied ::= counter
    _ = unwrap_or_abort(.value = await($&future))
    if CounterAccess#().get(.self = &copied) != 42 { abort }
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    counter ::= Virtual#(CounterAccess)(&provider)
    perform(.counter = counter, .value = $&value, .executor = executor)
}

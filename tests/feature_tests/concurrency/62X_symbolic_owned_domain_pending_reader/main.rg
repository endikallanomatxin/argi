CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: $&Provider) -> () where { writes(self.state) invalidates(self.state) }
)
Provider := (._counter: Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .set = (.self: $&Provider) -> () { self&._counter = 42 }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
perform := (.provider: $&Provider, .executor: Virtual#(Executor)) -> () {
    assume executor
    counter ::= to_virtual#(CounterAccess)(provider)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &provider&._counter)))
    CounterAccess#().set(.self = $&counter)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= to_virtual#(Executor)($&executor_provider)
    provider: Provider = (._counter = 7)
    perform(.provider = $&provider, .executor = executor)
}

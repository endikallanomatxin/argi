Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32)
implement Counter#(Provider) (
    .state = region(self._counter)
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._counter& }
    .set = (.self: &Provider) -> () { self&._counter& = 42 }
)
Forwarder := (.base: Virtual#(Counter))
implement Counter#(Forwarder) (
    .state = region(self.base.state)
    .get = (.self: &Forwarder) -> (.result: Int32) { result = Counter#().get(&self&.base) }
    .set = (.self: &Forwarder) -> () { Counter#().set(&self&.base) }
)
make := (.self: &Forwarder) -> (.result: Virtual#(Counter)) {
    result = to_virtual#(Counter)(self)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    wrapper ::= Forwarder(to_virtual#(Counter)(&provider))
    outer ::= make(&wrapper)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    Counter#().set(&outer)
}

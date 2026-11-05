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
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    inner ::= to_virtual#(Counter)(&provider)
    wrapper ::= Forwarder(inner)
    outer ::= make(&wrapper)
    if Counter#().get(&outer) != 7 { abort }
    Counter#().set(&outer)
    if value != 42 { abort }
}

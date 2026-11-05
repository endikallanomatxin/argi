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
make_changing := (.self: &Forwarder, .destination: $&Forwarder, .other: Virtual#(Counter)) -> (.result: Virtual#(Counter)) {
    result = to_virtual#(Counter)(self)
    destination&.base = other
}
main := () -> () {
    a :: Int32 = 7
    b :: Int32 = 9
    first: Provider = (._counter = $&a)
    second: Provider = (._counter = $&b)
    wrapper ::= Forwarder(to_virtual#(Counter)(&first))
    destination ::= Forwarder(to_virtual#(Counter)(&first))
    outer ::= make_changing(&wrapper, $&destination, to_virtual#(Counter)(&second))
    if Counter#().get(&outer) != 7 { abort }
}

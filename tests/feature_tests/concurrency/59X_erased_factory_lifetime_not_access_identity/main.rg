CounterAccess#(.Provider: Type): Contract = (
    domain state
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._counter& }
) where { state(self._counter) }
Factory#(.Provider: Type): Contract = (
    .make: (.self: &Provider) -> (.result: Virtual#(CounterAccess)) where { depends_on(result, self) }
)
Holder := (.counter: Virtual#(CounterAccess))
implement Factory#(Holder) (
    .make = (.self: &Holder) -> (.result: Virtual#(CounterAccess)) { result = self&.counter }
)
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._counter = $&value)
    counter ::= to_virtual#(CounterAccess)(&provider)
    holder: Holder = (.counter = counter)
    factory ::= to_virtual#(Factory)(&holder)
    returned ::= Factory#().make(.self = &factory)
    _ = CounterAccess#().get(.self = &returned)
}

CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .get = (.self: &Provider) -> (.result: Int32) { result = self&._counter& }
)
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
    counter ::= Virtual#(CounterAccess)(&provider)
    holder: Holder = (.counter = counter)
    factory ::= Virtual#(Factory)(&holder)
    returned ::= Factory#().make(.self = &factory)
    _ = CounterAccess#().get(.self = &returned)
}

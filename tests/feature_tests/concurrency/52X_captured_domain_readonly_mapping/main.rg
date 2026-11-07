CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: &Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .set = (.self: &Provider) -> () {}
)
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._counter = &value)
    counter ::= Virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
}

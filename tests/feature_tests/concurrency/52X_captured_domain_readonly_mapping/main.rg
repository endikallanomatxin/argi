CounterAccess#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: &Int32)
implement CounterAccess#(Provider) (
    .set = (.self: &Provider) -> () {}
) where { state(self._counter) }
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._counter = &value)
    counter ::= to_virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
}

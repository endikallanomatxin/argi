CounterAccess#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Resources := (.first: $&Int32, .second: $&Int32)
Provider := (._resources: Resources)
implement CounterAccess#(Provider) (
    .set = (.self: &Provider) -> () {
        self&._resources.first& = 42
        self&._resources.second& = 42
    }
) where { state(self._resources.first, self._resources.second) }
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._resources = (.first = $&value, .second = $&value))
    counter ::= to_virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
    if value != 42 { abort }
}

CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Resources := (.first: $&Int32, .second: $&Int32)
Provider := (._resources: Resources)
implement CounterAccess#(Provider) (
    .state = region(self._resources.first, self._resources.second),
    .set = (.self: &Provider) -> () {
        self&._resources.first& = 42
        self&._resources.second& = 42
    }
)
main := () -> () {
    value :: Int32 = 7
    provider: Provider = (._resources = (.first = $&value, .second = $&value))
    counter ::= Virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
    if value != 42 { abort }
}

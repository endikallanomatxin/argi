CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .set = (.self: &Provider) -> () { self&._counter& = 42 }
)
Pure#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .value: $&Int32) -> () where { no_access() }
)
Empty := (.marker: Int32)
implement Pure#(Empty) (
    .run = (.self: &Empty, .value: $&Int32) -> () {
        provider: Provider = (._counter = value)
        counter ::= to_virtual#(CounterAccess)(&provider)
        CounterAccess#().set(.self = &counter)
    }
)
main := () -> () {
    empty: Empty = (.marker = 0)
    pure ::= to_virtual#(Pure)(&empty)
    value :: Int32 = 7
    Pure#().run(.self = &pure, .value = $&value)
}

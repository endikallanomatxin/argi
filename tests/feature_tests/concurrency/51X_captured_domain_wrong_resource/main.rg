CounterAccess#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32, ._other: $&Int32)
implement CounterAccess#(Provider) (
    .set = (.self: &Provider) -> () { self&._other& = 42 }
) where { state(self._counter) }
main := () -> () {
    value :: Int32 = 7
    other :: Int32 = 0
    provider: Provider = (._counter = $&value, ._other = $&other)
    counter ::= to_virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
}

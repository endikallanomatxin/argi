CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (._counter: $&Int32, ._other: $&Int32)
implement CounterAccess#(Provider) (
    .state = region(self._counter),
    .set = (.self: &Provider) -> () { self&._other& = 42 }
)
main := () -> () {
    value :: Int32 = 7
    other :: Int32 = 0
    provider: Provider = (._counter = $&value, ._other = $&other)
    counter ::= Virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
}

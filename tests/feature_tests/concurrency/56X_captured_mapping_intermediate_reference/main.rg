CounterAccess#(.Provider: Type): Contract = (
    domain state
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Holder := (.counter: $&Int32)
Provider := (._holder: &Holder)
implement CounterAccess#(Provider) (.set = (.self: &Provider) -> () {}) where { state(self._holder.counter) }
perform := (.provider: &Provider) -> () {
    counter ::= to_virtual#(CounterAccess)(provider)
    CounterAccess#().set(.self = &counter)
}
main := () -> () {
    value :: Int32 = 7
    holder: Holder = (.counter = $&value)
    provider: Provider = (._holder = &holder)
    perform(.provider = &provider)
}

CounterAccess#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Holder := (.counter: Int32)
Provider := (._holder: &Holder)
implement CounterAccess#(Provider) (
    .state = region(self._holder.counter),
    .set = (.self: &Provider) -> () {})
main := () -> () {
    holder: Holder = (.counter = 7)
    provider: Provider = (._holder = &holder)
    counter ::= to_virtual#(CounterAccess)(&provider)
    CounterAccess#().set(.self = &counter)
}

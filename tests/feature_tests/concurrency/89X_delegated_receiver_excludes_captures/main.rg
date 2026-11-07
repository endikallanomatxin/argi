Counter#(.Provider: Type): Contract = (
    .external: Region#(Provider)
    .set: (.self: $&Provider) -> () where { writes(self.external) }
)
ForwardCounter#(.Provider: Type): Contract = (
    .target: Region#(Provider)
    .set: (.self: $&Provider) -> () where { writes(self.target) }
)
CounterState := (.value: $&Int32)
Forwarder := (.base: Virtual#(Counter))
implement Counter#(CounterState) (
    .external = region(self.value),
    .set = (.self: $&CounterState) -> () { self&.value& = 42 }
)
implement ForwardCounter#(Forwarder) (
    .target = region(self.base),
    .set = (.self: $&Forwarder) -> () { Counter#().set(.self = $&self&.base) }
)
main := () -> () {
    value :: Int32 = 7
    state: CounterState = (.value = $&value)
    forwarder: Forwarder = (.base = Virtual#(Counter)($&state))
    counter ::= Virtual#(ForwardCounter)($&forwarder)
}

Counter#(.Provider: Type): Contract = (
    domain external
    .set: (.self: $&Provider) -> () where { writes(self.external) }
)
ForwardCounter#(.Provider: Type): Contract = (
    domain target
    .set: (.self: $&Provider) -> () where { writes(self.target) }
)
CounterState := (.value: $&Int32)
Forwarder := (.base: Virtual#(Counter))
implement Counter#(CounterState) (
    .set = (.self: $&CounterState) -> () { self&.value& = 42 }
) where { external(self.value) }
implement ForwardCounter#(Forwarder) (
    .set = (.self: $&Forwarder) -> () { Counter#().set(.self = $&self&.base) }
) where { target(self.base) }
main := () -> () {
    value :: Int32 = 7
    state: CounterState = (.value = $&value)
    forwarder: Forwarder = (.base = to_virtual#(Counter)($&state))
    counter ::= to_virtual#(ForwardCounter)($&forwarder)
}

Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: (.self: $&T) -> () where writes(self.state)
)
Provider := (.reference: $&Int32)
implement Counter#(Provider) (
    .state = region(self),
    .set = (.self: $&Provider) -> () { self&.reference& = 42 }
)
main := () -> () {
    value :: Int32 = 0
    provider ::= Provider($&value)
    counter ::= to_virtual#(Counter)($&provider)
    set($&counter)
}

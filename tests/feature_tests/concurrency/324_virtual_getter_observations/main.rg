Slot := (.reference: &Int32)
Source#(.T: Type): Contract = (
    .get: (.self: &T) -> (.result: $&Slot)
        where { reads(self) depends_on(result, self) }
)
Provider := (.slot: $&Slot)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) { result = self&.slot }
)

main := () -> () {
    first: Int32 = 7
    second: Int32 = 42
    a ::= Slot(&first)
    b ::= Slot(&second)
    provider ::= Provider($&a)
    source ::= Virtual#(Source)(&provider)
    before := Source#().get(.self = &source)
    provider.slot = $&b
    after := Source#().get(.self = &source)
    if before&.reference& != 7 { abort }
    if after&.reference& != 42 { abort }
}

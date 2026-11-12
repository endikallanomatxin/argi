Slot := (.reference: &Int32)
Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: $&Slot) where { depends_on(result, self) }
)
Provider := (.slot: $&Slot)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) { result = self&.slot }
)
update := (.slot: $&Slot, .source: Virtual#(Source), .replacement: &Int32, .change: Bool) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        slot&.reference = &temporary
        target ::= slot
        if change { target = Source#().get(.self = &source) }
        target&.reference = replacement
    }
    result = slot&.reference&
}
main := (.system: System) -> () {
    stable: Int32 = 7
    first ::= Slot(&stable)
    other ::= Slot(&stable)
    provider ::= Provider($&other)
    source ::= Virtual#(Source)(&provider)
    _ = update(.slot = $&first, .source = source, .replacement = &stable, .change = true)
}

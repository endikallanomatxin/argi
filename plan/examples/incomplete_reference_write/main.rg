Slot := (.reference: &Int32)
Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: $&Slot) where { depends_on(result, self) }
)
Provider := (.slot: $&Slot)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) { result = self&.slot }
)
update := (.slot: $&Slot, .source: Virtual#(Source), .other: &Slot, .replacement: &Int32, .change: Bool) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        slot&.reference = replacement
        target ::= slot
        if change { target = Source#().get(.self = &source) }
        target&.reference = &temporary
        slot&.reference = replacement
    }
    result = other&.reference&
}
main := (.system: System) -> () {
    stable: Int32 = 7
    first ::= Slot(&stable)
    other ::= Slot(&stable)
    provider ::= Provider($&other)
    source ::= Virtual#(Source)(&provider)
    value ::= update(.slot = $&first, .source = source, .other = &other, .replacement = &stable, .change = true)
    if value != 7 { abort }
}

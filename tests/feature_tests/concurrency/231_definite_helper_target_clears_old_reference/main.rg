Slot := (.reference: &Int32)
Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: $&Slot) where { depends_on(result, self) }
)
Provider := (.slot: $&Slot)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) { result = self&.slot }
)
select_slot := (.known: $&Slot, .source: Virtual#(Source), .change: Bool) -> (.target: $&Slot) {
    target = known
    if change { target = Source#().get(.self = &source) }
}
update := (.slot: $&Slot, .source: Virtual#(Source), .replacement: &Int32, .change: Bool) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        slot&.reference = &temporary
        target ::= select_slot(.known = slot, .source = source, .change = change)
        target&.reference = replacement
        slot&.reference = replacement
    }
    result = slot&.reference&
}
main := (.system: System) -> () {
    stable: Int32 = 7
    first ::= Slot(&stable)
    other ::= Slot(&stable)
    provider ::= Provider($&other)
    source ::= Virtual#(Source)(&provider)
    value ::= update(.slot = $&first, .source = source, .replacement = &stable, .change = true)
    if value != 7 { abort }
}

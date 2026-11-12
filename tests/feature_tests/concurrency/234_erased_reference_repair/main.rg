Slot := (.reference: &Int32)
Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: $&Slot) where { depends_on(result, self) }
)
Provider := (.slot: $&Slot)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) { result = self&.slot }
)
repair := (.source: Virtual#(Source), .replacement: &Int32) -> () {
    target ::= Source#().get(.self = &source)
    {
        temporary: Int32 = 42
        target&.reference = &temporary
        target&.reference = replacement
    }
}
main := (.system: System) -> () {
    original: Int32 = 7
    replacement: Int32 = 9
    slot ::= Slot(&original)
    provider ::= Provider($&slot)
    source ::= Virtual#(Source)(&provider)
    repair(.source = source, .replacement = &replacement)
    if slot.reference& != 9 { abort }
}

Slot := (.reference: &Int32)
Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: $&Slot) where { depends_on(result, self) }
)
Provider := (.first: $&Slot, .second: $&Slot, .index: $&Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: $&Slot) {
        if self&.index& == 0 { result = self&.first } else { result = self&.second }
        self&.index& = self&.index& + 1
    }
)
update := (.source: Virtual#(Source), .first: &Slot, .replacement: &Int32) -> (.result: Int32) {
    index ::= 0
    while index < 2 {
        target ::= Source#().get(.self = &source)
        if index == 0 {
            temporary: Int32 = 42
            target&.reference = &temporary
        } else {
            target&.reference = replacement
        }
        index = index + 1
    }
    result = first&.reference&
}
main := (.system: System) -> () {
    stable: Int32 = 7
    first ::= Slot(&stable)
    second ::= Slot(&stable)
    index ::= 0
    provider ::= Provider($&first, $&second, $&index)
    source ::= Virtual#(Source)(&provider)
    _ = update(.source = source, .first = &first, .replacement = &stable)
}

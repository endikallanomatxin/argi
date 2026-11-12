Slot := (.reference: &Int32)
repair := (.first: $&Slot, .second: &Slot, .replacement: &Int32) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        first&.reference = &temporary
    }
    first&.reference = replacement
    result = second&.reference&
}
main := (.system: System) -> () {
    original: Int32 = 7
    replacement: Int32 = 9
    slot ::= Slot(&original)
    if repair(.first = $&slot, .second = &slot, .replacement = &replacement) != 9 { abort }
}

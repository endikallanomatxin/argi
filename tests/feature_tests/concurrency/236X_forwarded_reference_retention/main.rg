Slot := (.reference: &Int32)
inspect := (.first: $&Slot, .second: &Slot, .replacement: &Int32) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        first&.reference = &temporary
    }
    result = second&.reference&
    first&.reference = replacement
}
forward := (.first: $&Slot, .second: &Slot, .replacement: &Int32) -> (.result: Int32) {
    result = inspect(.first = first, .second = second, .replacement = replacement)
}
main := (.system: System) -> () {
    stable: Int32 = 7
    slot ::= Slot(&stable)
    _ = forward(.first = $&slot, .second = &slot, .replacement = &stable)
}

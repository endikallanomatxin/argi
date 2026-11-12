Slot := (.reference: &Int32)
inspect := (.first: $&Slot, .second: &Slot, .replacement: &Int32) -> (.result: Int32) {
    {
        temporary: Int32 = 42
        first&.reference = &temporary
    }
    result = second&.reference&
    first&.reference = replacement
}
main := (.system: System) -> () {
    stable: Int32 = 7
    first ::= Slot(&stable)
    second ::= Slot(&stable)
    if inspect(.first = $&first, .second = &second, .replacement = &stable) != 7 { abort }
}

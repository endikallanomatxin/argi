Slot := (.reference: &Int32)
branch :: Bool = true
choose_second := () -> (.selected: Bool) { selected = branch }

main := () -> () {
    stable: Int32 = 7
    selected :: &Int32 = &stable
    {
        temporary: Int32 = 42
        first ::= Slot(&stable)
        second ::= Slot(&temporary)
        cell ::= &first
        if choose_second() { cell = &second }
        selected = cell&.reference
    }
    if selected& != 7 { abort }
}

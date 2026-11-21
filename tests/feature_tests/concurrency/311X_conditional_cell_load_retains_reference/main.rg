branch :: Bool = true
choose_second := () -> (.selected: Bool) { selected = branch }

main := () -> () {
    stable: Int32 = 7
    selected :: &Int32 = &stable
    {
        temporary: Int32 = 42
        first: &Int32 = &stable
        second: &Int32 = &temporary
        cell ::= &first
        if choose_second() { cell = &second }
        selected = cell&
    }
    if selected& != 7 { abort }
}

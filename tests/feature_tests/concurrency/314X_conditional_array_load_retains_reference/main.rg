branch :: Bool = true
index_value :: UIntNative = 1
index := () -> (.selected: UIntNative) { selected = index_value }
choose_second := () -> (.selected: Bool) { selected = branch }

main := () -> () {
    stable: Int32 = 7
    selected :: &Int32 = &stable
    {
        temporary: Int32 = 42
        first: [2]&Int32 = (&stable, &stable)
        second: [2]&Int32 = (&stable, &temporary)
        cell ::= &first
        if choose_second() { cell = &second }
        selected = cell&[index()]
    }
    if selected& != 7 { abort }
}

index_value :: UIntNative = 1
index := () -> (.result: UIntNative) { result = index_value }

main := () -> () {
    first: Int32 = 7
    selected :: &Int32 = &first
    {
        second: Int32 = 9
        before: [2]&Int32 = (&first, &first)
        after: [2]&Int32 = (&first, &second)
        base ::= &before[0]
        if index() == 1 { base = &after[0] }
        element := trusted_reference_offset#(.t: &Int32)(.base = base, .elements = index()).reference
        selected = element&
    }
    if selected& != 9 { abort }
}

branch :: Bool = true
choose_second := () -> (.selected: Bool) { selected = branch }

main := () -> () {
    first: Int32 = 11
    second: Int32 = 22
    left: [2]&Int32 = (&second, &first)
    right: [2]&Int32 = (&first, &second)
    base ::= &left[0]
    if choose_second() { base = &right[0] }
    element := trusted_reference_offset#(.t: &Int32)(.base = base, .elements = 1).reference
    selected := element&
    if selected& != 22 { abort }
}

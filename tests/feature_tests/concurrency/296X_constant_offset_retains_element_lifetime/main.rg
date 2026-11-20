main := () -> () {
    first: Int32 = 7
    selected :: &Int32 = &first
    {
        second: Int32 = 9
        values: [2]&Int32 = (&first, &second)
        element := trusted_reference_offset#(.t: &Int32)(.base = &values[0], .elements = 1).reference
        selected = element&
    }
    if selected& != 9 { abort }
}

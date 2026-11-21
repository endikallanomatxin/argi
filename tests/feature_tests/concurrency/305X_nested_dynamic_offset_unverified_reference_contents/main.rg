index_value :: UIntNative = 1
index := () -> (.result: UIntNative) { result = index_value }

main := () -> () {
    first: Int32 = 7
    selected :: &Int32 = &first
    {
        second: Int32 = 9
        values: [2][2]&Int32 = ((&first, &first), (&first, &second))
        element := trusted_reference_offset#(.t: &Int32)(.base = &values[index()][0], .elements = index()).reference
        selected = element&
    }
    if selected& != 9 { abort }
}

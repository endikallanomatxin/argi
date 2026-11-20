index_value :: UIntNative = 1
index := () -> (.result: UIntNative) { result = index_value }

main := () -> () {
    first: Int32 = 7
    second: Int32 = 9
    selected :: &Int32 = &first
    {
        values: [2]&Int32 = (&first, &second)
        element := &values[index()]
        selected = element&
    }
    if selected& != 9 { abort }
}

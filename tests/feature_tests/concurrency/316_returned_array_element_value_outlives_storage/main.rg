index_value :: UIntNative = 1
index := () -> (.selected: UIntNative) { selected = index_value }

select := (.array: &[2]&Int32, .offset: UIntNative) -> (.result: &&Int32) {
    result = &array&[offset]
}
forward := (.array: &[2]&Int32, .offset: UIntNative) -> (.result: &&Int32) {
    result = select(array, offset)
}

main := () -> () {
    stable: Int32 = 7
    selected :: &Int32 = &stable
    {
        values: [2]&Int32 = (&stable, &stable)
        cell := forward(&values, index())
        selected = cell&
    }
    if selected& != 7 { abort }
}

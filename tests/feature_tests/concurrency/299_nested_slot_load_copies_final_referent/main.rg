load := (.outer: &&&Int32) -> (.result: &Int32) {
    inner := outer&
    result = inner&
}

main := () -> () {
    value: Int32 = 7
    selected :: &Int32 = &value
    {
        inner: &Int32 = &value
        outer: &&Int32 = &inner
        selected = load(.outer = &outer)
    }
    if selected& != 7 { abort }
}

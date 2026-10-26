Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () {})

release := (.first: $&Owner, .second: $&Owner, .third: $&Owner, .again: Bool) -> () {
    selected ::= first
    next ::= second
    while again {
        selected = next
        next = third
    }
    deinit(third)
    deinit(selected)
}

main := () -> () {
    first ::= Owner(1)
    second ::= Owner(2)
    third ::= Owner(3)
    release($&first, $&second, $&third, false)
}

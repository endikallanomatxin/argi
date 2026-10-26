drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

release := (.first: $&Owner, .second: $&Owner) -> () {
    selected ::= first
    alias ::= selected
    deinit(selected)
    selected = second
    deinit(alias)
}

main := () -> () {
    first ::= Owner(1)
    second ::= Owner(2)
    release($&first, $&second)
}

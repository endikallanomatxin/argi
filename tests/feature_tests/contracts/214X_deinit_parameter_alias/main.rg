drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

release := (.value: $&Owner) -> () {
    alias ::= value
    deinit(value)
    deinit(alias)
}

main := () -> () {
    value ::= Owner(1)
    release($&value)
}

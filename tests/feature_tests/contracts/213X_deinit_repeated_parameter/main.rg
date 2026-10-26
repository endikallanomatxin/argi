drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

release := (.value: $&Owner) -> () {
    deinit(value)
    deinit(value)
}

main := () -> () {
    value ::= Owner(1)
    release($&value)
}

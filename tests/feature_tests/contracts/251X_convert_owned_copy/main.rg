Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () {})

main := () -> () {
    owner ::= Owner(7)
    copied ::= owner | convert<.to: Owner>(_)
}

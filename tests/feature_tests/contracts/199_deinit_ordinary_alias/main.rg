drops :: Int32 = 0

Owner := (.value: Int32)

observe := (.self: $&Owner) -> () { drops = drops + self&.value }

implement Deinit<Owner> (.deinit = observe)

create := () -> () {
    value ::= Owner(1)
    observe($&value)
    if value.value != 1 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 2 { abort }
}

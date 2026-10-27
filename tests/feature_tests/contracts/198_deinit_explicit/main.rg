drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)

create := () -> () {
    value ::= Owner(42)
    deinit($&value)
}

main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 1 { abort }
}

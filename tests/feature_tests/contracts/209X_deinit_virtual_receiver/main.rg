Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

main := () -> () {
    value ::= Owner(42)
    erased ::= Virtual#(Deinit)($&value)
}

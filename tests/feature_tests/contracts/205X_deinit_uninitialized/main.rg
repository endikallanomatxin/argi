Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

main := () -> () {
    value :: Owner
    deinit($&value)
}

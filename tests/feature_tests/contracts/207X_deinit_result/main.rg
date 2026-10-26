Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> (.result: Int32) { result = 0 })

main := () -> () {}

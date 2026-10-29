Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    owner ::= Owner(7)
    copied ::= owner | convert#(.to: Owner)(_)
}

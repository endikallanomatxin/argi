drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

exercise := (.error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    owner ::= Owner(7)
    converted ::= ~owner | convert#(.to: Owner)(_)
    if converted.value != 7 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    exercise()
    if drops != 1 { status_code = 1 }
}

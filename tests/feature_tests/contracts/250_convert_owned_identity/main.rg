drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

exercise := () -> () {
    owner ::= Owner(7)
    converted ::= ~owner | convert#(.to: Owner)(_)
    if converted.value != 7 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    exercise()
    if drops != 1 { status_code = 1 }
}

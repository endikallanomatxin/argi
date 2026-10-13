drops :: Int32 = 0
Owner: Type = (.value: Int32)
implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })
release := (.first: $&Owner, .second: $&Owner) -> () { deinit(first) deinit(second) }
main := () -> (.status_code: Int32 = 0) {
    first ::= Owner(1) second ::= Owner(2)
    release($&first, $&second)
    if drops != 2 { abort }
}

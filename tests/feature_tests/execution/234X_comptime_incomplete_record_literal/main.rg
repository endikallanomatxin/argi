Pair := (.left: Int32, .right: Int32)

make_pair := () -> (.result: Pair) { result = (.left = 42) }

main := () -> (.status_code: Int32) {
    status_code = #run () -> (.value: Int32) {
        pair ::= make_pair()
        value = pair.left
    }
}

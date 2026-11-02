Pair := (.left: Int32, .right: Int32)

main := () -> (.status_code: Int32) {
    pair: Pair = (.left = 42)
    status_code = pair.left
}

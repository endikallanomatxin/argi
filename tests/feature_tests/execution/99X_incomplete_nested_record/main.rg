Pair := (.first: Int32, .second: (.value: Int32, .missing: Int32))

probe := (.complete: Bool) -> (.result: Int32) {
    pair :: Pair
    pair.first = 40
    pair.second.value = 2
    if complete { pair.second.missing = 0 }
    copy ::= pair
    result = copy.first
}

main := () -> (.status_code: Int32) {
    status_code = probe(.complete = true)
}

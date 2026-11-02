answer := () -> (.value: Int32 = 42) {}

test dependency_only := () -> !() {
    testing.expect(true)!
}

test shared_name := () -> !() {
    testing.expect(false)!
}

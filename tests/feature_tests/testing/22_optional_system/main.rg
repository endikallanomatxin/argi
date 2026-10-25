test without_system := () -> !() {
    testing.expect_equal(
        .expected = 42
        .actual   = #run () -> (.value: Int32) {
            value = 42
        }
    )!
}

test with_system := (.system: System) -> !() {
    testing.expect(true)!
}

test modern := (.system: System) -> !() {
    testing.expect(true)!
}

test multiline := (.system: System) -> !() {
    testing.expect_equal(.expected = 7, .actual = 7)!
}

-- Explicit empty input/output defaults use the same definition syntax.
test explicit := (.system: System) -> !() {
    testing.expect(true)!
}

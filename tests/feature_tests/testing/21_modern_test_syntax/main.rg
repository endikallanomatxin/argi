test modern := (.system: System) -> !() {
    testing.expect(true)!
}

test multiline :=
    (
        .system: System
    ) -> !() {
    testing.expect_equal(.expected = 7, .actual = 7)!
}

-- Ordinary named functions and tests both retain legacy syntax compatibility.
test legacy(.system: System) -> !() := {
    testing.expect(true)!
}

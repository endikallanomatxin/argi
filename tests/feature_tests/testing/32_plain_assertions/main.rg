-- Ordinary assertions need neither System nor diagnostic capabilities.
test plain_assertions := () -> !() {
    testing.expect(true)!
    testing.expect_equal(42, 42)!
    testing.expect_equal_strings("argi", "argi")!
    expected: [3]UInt8 = (1, 2, 3)
    actual: [3]UInt8 = (1, 2, 3)
    testing.expect_equal_bytes(view(&expected), view(&actual))!
    testing.expect_error(
        .expected_reason = ..test_failed, .actual_result = testing.expect(false)
    )!
    testing.expect_error(
        .expected_reason = ..test_failed, .actual_result = testing.expect_equal(1, 2)
    )!
    testing.expect_error(..test_failed, testing.fail())!
}

test plain_failure := () -> !() {
    testing.expect(false)!
}

test plain_skip := () -> !() {
    testing.skip()!
}

test bounded_message(.system: System) -> !() := {
    testing.expect(
        .condition = false
        .message   = "context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context "
    )!
}

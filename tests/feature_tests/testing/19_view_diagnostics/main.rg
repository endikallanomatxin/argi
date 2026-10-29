test view_mismatch := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    expected :: [3]Int32 = (1, 2, 3)
    actual :: [3]Int32 = (1, 9, 3)
    testing.expect_equal_views(
        .expected = view(.self = &expected), .actual = view(.self = &actual)
    )!
}

test byte_prefix := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    expected :: [2]UInt8 = (1, 2)
    actual :: [1]UInt8 = (1)
    testing.expect_equal_bytes(
        .expected = view(.self = &expected), .actual = view(.self = &actual)
    )!
}

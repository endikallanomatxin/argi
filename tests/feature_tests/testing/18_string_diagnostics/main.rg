test string_mismatch := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    testing.expect_equal_strings(
        .expected = "abc", .actual = "axc", .message = "checking payload"
    )!
}

test string_prefix := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    testing.expect_equal_strings(.expected = "abc", .actual = "ab")!
}

test string_empty := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    testing.expect_equal_strings(.expected = "", .actual = "x")!
}

test string_embedded_nul := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    expected :: [3]UInt8 = (65, 0, 90)
    actual :: [3]UInt8 = (65, 0, 91)
    testing.expect_equal_strings(.expected = "A\0Z", .actual = "A\0[")!
}

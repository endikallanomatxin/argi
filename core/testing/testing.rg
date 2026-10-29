..test_failed
..test_skipped

test_fail_impl := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed))
) {
    assume error_tracer

    result = ..error(.reason = ..test_failed)
}

test_skip_impl := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_skipped))
) {
    assume error_tracer

    result = ..error(.reason = ..test_skipped)
}

fail_c_string := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed))
) {
    assume error_tracer

    test_fail_impl()!! message

    result = ..ok Void()
}

skip := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_skipped))
) {
    assume error_tracer

    test_skip_impl()!! message

    result = ..ok Void()
}

expect := (.condition: Bool, .message: StringView = "", .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed))
) {
    assume error_tracer

    if condition {
        result = ..ok Void()
        return
    }

    result = _testing_failure(
        .detail = "expect failed: condition was false", .message = message
    )
}

_assert_equal_generic := #(.t: Type) (
    .expected: t, .actual: t, .message: StringView = "", .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed))) {
    assume error_tracer

    if expected == actual {
        result = ..ok Void()
        return
    }

    result = _testing_failure(
        .detail = "expect_equal failed: expected and actual differ", .message = message
    )
}

expect_error := #(.t: Type, .reasons: Type) (
    .expected_reason : reasons,
    .actual_result   : Errable#(t, reasons),
    .error_tracer    : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed))) {
    assume error_tracer

    fail(.message = "testing.expect_error must be lowered by the compiler")!
}

..test_failed
..test_skipped

test_fail_impl := () -> (.result: Errable#(Void, (..test_failed))) {
    result = ..error(.reason = ..test_failed)
}

test_skip_impl := () -> (.result: Errable#(Void, (..test_skipped))) {
    result = ..error(.reason = ..test_skipped)
}

fail_c_string := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))
) {
    assume error_tracer

    test_fail_impl()!! message

    result = ..ok Void()
}

skip := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_skipped), ErrorWithTrace#((..test_skipped)))
) {
    assume error_tracer

    test_skip_impl()!! message

    result = ..ok Void()
}

expect := (.condition: Bool, .message: StringView = "", .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))
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
) -> (.result: Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))) {
    assume error_tracer

    if expected == actual {
        result = ..ok Void()
        return
    }

    result = _testing_failure(
        .detail = "expect_equal failed: expected and actual differ", .message = message
    )
}

expect_error := #(.t: Type, .reasons: Type, .error_type: Type) (
    .expected_reason : reasons,
    .actual_result   : Errable#(t, reasons, error_type),
    .error_tracer    : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))) {
    assume error_tracer

    match actual_result {
        ..ok ~value {
            fail(.message = "expect_error failed: expected an error but got success")!
        }
        ..error error {
            if error.reason != expected_reason {
                fail(.message = "expect_error failed: error reason mismatch")!
            }
        }
    }
    result = ..ok Void()
}

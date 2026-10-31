..test_failed
..test_skipped

test_fail_impl := () -> (.result: Errable#(Void, (..test_failed))) {
    result = ..error(.reason = ..test_failed)
}

test_skip_impl := () -> (.result: Errable#(Void, (..test_skipped))) {
    result = ..error(.reason = ..test_skipped)
}

fail_c_string_with_trace := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))
) {
    assume error_tracer

    test_fail_impl()!! message

    result = ..ok Void()
}

skip_with_trace := (.message: &CChar, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Void, (..test_skipped), ErrorWithTrace#((..test_skipped)))
) {
    assume error_tracer

    test_skip_impl()!! message

    result = ..ok Void()
}

expect_with_trace := (
    .condition: Bool, .message: StringView = "", .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))) {
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

expect_error_with_trace := #(.t: Type, .reasons: Type, .error_type: Type) (
    .expected_reason : reasons,
    .actual_result   : Errable#(t, reasons, error_type),
    .error_tracer    : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed), ErrorWithTrace#((..test_failed)))) {
    assume error_tracer

    match actual_result {
        ..ok ~value {
            fail_with_trace(.message = "expect_error failed: expected an error but got success")!
        }
        ..error error {
            if error.reason != expected_reason {
                fail_with_trace(.message = "expect_error failed: error reason mismatch")!
            }
        }
    }
    result = ..ok Void()
}

-- Basic assertions communicate failure without borrowing diagnostic resources.
-- Rich assertions explicitly opt into tracing through *_with_trace.
expect := (.condition: Bool) -> (.result: Errable#(Void, (..test_failed))) {
    if condition {
        result = ..ok Void()
        return
    }
    result = fail()
}

expect_equal := #(.Value: Type) (.expected: Value, .actual: Value) -> (
    .result : Errable#(Void, (..test_failed))
) {
    result = expect(expected == actual)
}

expect_error := #(.t: Type, .reasons: Type, .error_type: Type) (
    .expected_reason: reasons, .actual_result: Errable#(t, reasons, error_type)
) -> (.result: Errable#(Void, (..test_failed))) {
    match actual_result {
        ..ok ~value { result = ..error(.reason = ..test_failed) }
        ..error error { result = expect(error.reason == expected_reason) }
    }
}

fail := () -> (.result: Errable#(Void, (..test_failed))) { result = test_fail_impl() }

skip := () -> (.result: Errable#(Void, (..test_skipped))) { result = test_skip_impl() }

expect_equal_strings := #(.Value: Type: _TestTextEquality#(Value)) (
    .expected: Value, .actual: Value
) -> (.result: Errable#(Void, (..test_failed))) {
    result = expect_equal(.expected = expected, .actual = actual)
}

expect_equal_views := #(.t: Type) (.expected: ArrayView#(t), .actual: ArrayView#(t)) -> (
    .result : Errable#(Void, (..test_failed))
) {
    expect(length(&expected).count == length(&actual).count)!
    index :: UIntNative = 0
    while index < length(&expected).count {
        left ::= unwrap_or_abort(.value = get(&expected, .index = index))
        right ::= unwrap_or_abort(.value = get(&actual, .index = index))
        expect_equal(.expected = left, .actual = right)!
        index = index + 1
    }
    result = ..ok Void()
}

expect_equal_bytes := expect_equal_views#(UInt8)

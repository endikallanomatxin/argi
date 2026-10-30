..some_reason

some_fallible_call := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(
        .t: Int32, .reasons: (..some_reason), .error_type: ErrorWithTrace#((..some_reason))
    )
) {
    assume error_tracer

    result = ..ok(.value = 7)
}

test expected_error_unexpected_ok := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    call_result := some_fallible_call()
    testing.expect_error(.expected_reason = ..some_reason, .actual_result = ~call_result)!
}

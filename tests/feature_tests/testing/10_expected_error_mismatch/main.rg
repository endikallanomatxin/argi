..some_reason
..other_reason

some_fallible_call() -> (.result: Errable#(.t: Int32, .reasons: (..some_reason, ..other_reason))) := {
    result = ..error(.reason = ..other_reason)
}

test expected_error_mismatch(.system: System = System()) -> !() := {
    call_result := some_fallible_call()
    testing.expect_error(.expected_reason = ..some_reason, .actual_result = ~call_result)!
}

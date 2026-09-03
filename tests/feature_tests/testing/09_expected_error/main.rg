..some_reason

some_fallible_call() -> (.result: Errable#(.t: Int32, .reasons: (..some_reason))) := {
    result = ..error(.reason = ..some_reason)
}

test expected_error(.system: System = System()) -> !() := {
    call_result := some_fallible_call()
    testing.expect_error(.expected_reason = ..some_reason, .actual_result = ~call_result)!
}

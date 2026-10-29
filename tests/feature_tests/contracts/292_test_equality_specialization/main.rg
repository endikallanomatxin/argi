calls :: Int32 = 0

Token := (.value: Int32)

implement ImplicitlyCopyable#(Token) ()

implement TestEquality#(Token) (
    .check_equal = (
        .expected     : Token,
        .actual       : Token,
        .message      : StringView,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Void, (..test_failed))) {
        assume error_tracer

        calls = calls + 1
        if expected.value == actual.value {
            result = ..ok Void()
        } else {
            result = ..error(.reason = ..test_failed)
        }
    }
)

assert_same := #(.T: Type: TestEquality#(T)) (
    .expected: T, .actual: T, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..test_failed))) {
    assume error_tracer

    result = expect_equal(.expected = expected, .actual = actual)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    one ::= Token(1)
    two ::= Token(2)
    unwrap_or_abort(.value = assert_same(.expected = one, .actual = one))
    match expect_equal(.expected = one, .actual = two) {
        ..ok _ { status_code = 1 }
        ..error item { if item.reason != ..test_failed { status_code = 2 } }
    }
    if calls != 2 { status_code = 3 }
}

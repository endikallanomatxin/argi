-- Assertions specialize diagnostics within one operation identity.
TestEquality#(.Value: Type): Contract = (
    .check_equal : (
        .expected     : Value,
        .actual       : Value,
        .message      : StringView,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Void, (..test_failed)))
)

implement#(.Value: Type) TestEquality#(Value) (.check_equal = _assert_equal_generic)

expect_equal := #(.Value: Type: TestEquality#(Value)) (
    .expected     : Value,
    .actual       : Value,
    .message      : StringView = "",
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..test_failed))) {
    assume error_tracer

    result = TestEquality#(
        Value
    ).check_equal(.expected = expected, .actual = actual, .message = message)
}

_TestNumericDiagnostic#(.Value: Type): Contract = (
    .append_number : (.self: $&_TestDiagnostic, .value: Value) -> ()
)

_testing_append_number := #(.Value: Type: _TestNumericDiagnostic#(Value)) (
    .self: $&_TestDiagnostic, .value: Value
) -> () {
    _TestNumericDiagnostic#(Value).append_number(.self = self, .value = value)
}

implement TestEquality#(Int8) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(Int8) (.append_number = _testing_append_integer)

implement TestEquality#(Int16) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(Int16) (.append_number = _testing_append_integer)

implement TestEquality#(Int32) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(Int32) (.append_number = _testing_append_integer)

implement TestEquality#(Int64) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(Int64) (.append_number = _testing_append_integer)

implement TestEquality#(UInt8) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(UInt8) (.append_number = _testing_append_integer)

implement TestEquality#(UInt16) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(UInt16) (.append_number = _testing_append_integer)

implement TestEquality#(UInt32) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(UInt32) (.append_number = _testing_append_integer)

implement TestEquality#(UInt64) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(UInt64) (.append_number = _testing_append_integer)

implement TestEquality#(UIntNative) (.check_equal = _assert_equal_integer)

implement _TestNumericDiagnostic#(UIntNative) (.append_number = _testing_append_integer)

implement TestEquality#(Float16) (.check_equal = _assert_equal_float)

implement _TestNumericDiagnostic#(Float16) (.append_number = _testing_append_float)

implement TestEquality#(Float32) (.check_equal = _assert_equal_float)

implement _TestNumericDiagnostic#(Float32) (.append_number = _testing_append_float)

implement TestEquality#(Float64) (.check_equal = _assert_equal_float)

implement _TestNumericDiagnostic#(Float64) (.append_number = _testing_append_float)

implement TestEquality#(Bool) (.check_equal = _assert_equal_bool)

implement TestEquality#(StringView) (.check_equal = _assert_text_views)

implement TestEquality#(&String) (.check_equal = _assert_owned_strings)

_TestTextEquality#(.Value: Type): Contract = ()

implement _TestTextEquality#(StringView) ()

implement _TestTextEquality#(&String) ()

expect_equal_strings := #(.Value: Type: _TestTextEquality#(Value)) (
    .expected     : Value,
    .actual       : Value,
    .message      : StringView = "",
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..test_failed))) {
    assume error_tracer

    result = expect_equal(.expected = expected, .actual = actual, .message = message)
}

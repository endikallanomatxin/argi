-- Diagnostic text uses initialized stack storage and fits one tracer context.
-- Successful assertions do not construct diagnostics or require an allocator.
_TestDiagnostic: Type = (._bytes: [128]UInt8, ._length: UIntNative)

_TestDiagnostic init() -> (.result: _TestDiagnostic) := {
    result = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)
}

_testing_append(.self: $&_TestDiagnostic, .text: StringView) -> () := {
    index :: UIntNative = 0
    while index < text.length and self&._length < 128 {
        self&._bytes[self&._length] = bytes_get(.view = &text, .index = index).byte
        self&._length = self&._length + 1
        index = index + 1
    }
}

_testing_append_number#(.t: Type: Int)(.self: $&_TestDiagnostic, .value: t) -> () := {
    encoded ::= _decimal_encode#(.t: t)(.value = value)
    _testing_append(.self = self, .text = _decimal_view(.self = &encoded).view)
}

_testing_append_number#(.t: Type: Float)(.self: $&_TestDiagnostic, .value: t) -> () := {
    encoded ::= _float_encode(.value = value)
    _testing_append(.self = self, .text = _float_text_view(.self = &encoded).view)
}

_testing_detail(.self: &_TestDiagnostic) -> (.text: StringView) := {
    text = (.data = &self&._bytes[0], .length = self&._length)
}

_testing_failure(
        .detail  : StringView,
        .message : StringView
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    if message.length != 0 { add_context(.context = message) }
    test_fail_impl()!! detail
    result = ..ok Void()
}

fail(.message: StringView) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    test_fail_impl()!! message
    result = ..ok Void()
}

expect_equal#(
        .t : Type: Int
    )(
        .expected : t,
        .actual   : t,
        .message  : StringView = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    if expected == actual {
        result = ..ok Void()
        return
    }
    diagnostic ::= _TestDiagnostic()
    _testing_append(.self = $&diagnostic, .text = "expect_equal failed: expected ")
    _testing_append_number(.self = $&diagnostic, .value = expected)
    _testing_append(.self = $&diagnostic, .text = ", actual ")
    _testing_append_number(.self = $&diagnostic, .value = actual)
    result = _testing_failure(
        .detail  = _testing_detail(.self = &diagnostic).text
        .message = message
    )
}

expect_equal#(
        .t : Type: Float
    )(
        .expected : t,
        .actual   : t,
        .message  : StringView = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    if expected == actual {
        result = ..ok Void()
        return
    }
    diagnostic ::= _TestDiagnostic()
    _testing_append(.self = $&diagnostic, .text = "expect_equal failed: expected ")
    _testing_append_number(.self = $&diagnostic, .value = expected)
    _testing_append(.self = $&diagnostic, .text = ", actual ")
    _testing_append_number(.self = $&diagnostic, .value = actual)
    result = _testing_failure(
        .detail  = _testing_detail(.self = &diagnostic).text
        .message = message
    )
}

expect_equal(
        .expected : Bool,
        .actual   : Bool,
        .message  : StringView = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    if expected == actual {
        result = ..ok Void()
        return
    }
    detail :: StringView = "expect_equal failed: expected false, actual true"
    if expected { detail = "expect_equal failed: expected true, actual false" }
    result = _testing_failure(.detail = detail, .message = message)
}

_testing_lengths(.self: $&_TestDiagnostic, .expected: UIntNative, .actual: UIntNative) -> () := {
    _testing_append(.self = self, .text = "; lengths expected ")
    _testing_append_number(.self = self, .value = expected)
    _testing_append(.self = self, .text = ", actual ")
    _testing_append_number(.self = self, .value = actual)
}

_testing_compare_text(
        .expected : StringView,
        .actual   : StringView,
        .kind     : StringView,
        .message  : StringView  = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    common ::= expected.length
    if actual.length < common { common = actual.length }
    index :: UIntNative = 0
    while index < common {
        if [
            bytes_get(.view = &expected, .index = index).byte
            != bytes_get(.view = &actual, .index = index).byte
        ] { break }
        index = index + 1
    }
    if index == common and expected.length == actual.length {
        result = ..ok Void()
        return
    }
    diagnostic ::= _TestDiagnostic()
    _testing_append(.self = $&diagnostic, .text = kind)
    _testing_append(.self = $&diagnostic, .text = " differ at byte ")
    _testing_append_number(.self = $&diagnostic, .value = index)
    _testing_append(.self = $&diagnostic, .text = ": expected ")
    if index < expected.length {
        _testing_append_number(
            .self  = $&diagnostic
            .value = bytes_get(.view = &expected, .index = index).byte
        )
    } else { _testing_append(.self = $&diagnostic, .text = "<end>") }
    _testing_append(.self = $&diagnostic, .text = ", actual ")
    if index < actual.length {
        _testing_append_number(
            .self  = $&diagnostic
            .value = bytes_get(.view = &actual, .index = index).byte
        )
    } else { _testing_append(.self = $&diagnostic, .text = "<end>") }
    _testing_lengths(.self = $&diagnostic, .expected = expected.length, .actual = actual.length)
    result = _testing_failure(
        .detail  = _testing_detail(.self = &diagnostic).text
        .message = message
    )
}

expect_equal_strings(
        .expected : StringView,
        .actual   : StringView,
        .message  : StringView  = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    result = _testing_compare_text(
        .expected = expected
        .actual   = actual
        .message  = message
        .kind     = "strings"
    )
}

expect_equal(
        .expected : StringView,
        .actual   : StringView,
        .message  : StringView  = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    result = expect_equal_strings(.expected = expected, .actual = actual, .message = message)
}

expect_equal_strings(
        .expected : &String,
        .actual   : &String,
        .message  : StringView = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    result = expect_equal_strings(
        .expected = as_view(.self = expected)
        .actual   = as_view(.self = actual)
        .message  = message
    )
}

expect_equal_views#(
        .t : Type
    )(
        .expected : ArrayViewRO#(.t: t),
        .actual   : ArrayViewRO#(.t: t),
        .message  : StringView           = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    expected_length ::= length(.self = &expected).count
    actual_length ::= length(.self = &actual).count
    common ::= expected_length
    if actual_length < common { common = actual_length }
    index :: UIntNative = 0
    while index < common {
        left ::= trusted_reference_offset#(.t: t)(
            .base     = data(.self = &expected).pointer
            .elements = index
        ).reference
        right ::= trusted_reference_offset#(.t: t)(
            .base     = data(.self = &actual).pointer
            .elements = index
        ).reference
        if left&!= right&{ break }
        index = index + 1
    }
    if index == common and expected_length == actual_length {
        result = ..ok Void()
        return
    }
    diagnostic ::= _TestDiagnostic()
    _testing_append(.self = $&diagnostic, .text = "views differ at index ")
    _testing_append_number(.self = $&diagnostic, .value = index)
    _testing_lengths(.self = $&diagnostic, .expected = expected_length, .actual = actual_length)
    result = _testing_failure(
        .detail  = _testing_detail(.self = &diagnostic).text
        .message = message
    )
}

expect_equal_bytes(
        .expected : ArrayViewRO#(.t: UInt8),
        .actual   : ArrayViewRO#(.t: UInt8),
        .message  : StringView               = ""
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..test_failed))
    ) := {
    expected_length ::= length(.self = &expected).count
    actual_length ::= length(.self = &actual).count
    left :: StringView = ""
    right :: StringView = ""
    if expected_length != 0 {
        left = (.data = data(.self = &expected).pointer, .length = expected_length)
    }
    if actual_length != 0 {
        right = (.data = data(.self = &actual).pointer, .length = actual_length)
    }
    result = _testing_compare_text(
        .expected = left
        .actual   = right
        .message  = message
        .kind     = "bytes"
    )
}

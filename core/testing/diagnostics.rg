-- Diagnostic text uses initialized stack storage and fits one tracer context.
-- Successful assertions do not construct diagnostics or require an allocator.
_TestDiagnostic: Type = (._bytes: [128]UInt8, ._length: UIntNative)

implement Init#(_TestDiagnostic, ()) (
    .Result : Type = _TestDiagnostic
    .init   = (.args: ()) -> (.result: Result) {
        result = (._bytes = zeroed#(.t: [128]UInt8)(), ._length = 0)
    }
)

_testing_append(.self: $&_TestDiagnostic, .text: StringView) -> () := {
    index :: UIntNative = 0

    while index < text._length {
        decoded ::= unwrap_or_abort(.value = utf8_decode(.text = text, .offset = index))
        if decoded.width > 128 - self&._length { return }
        offset :: UIntNative = 0
        while offset < decoded.width {
            self&._bytes[self&._length] = bytes_get(.view = &text, .index = index + offset).byte
            self&._length = self&._length + 1
            offset = offset + 1
        }
        index = index + decoded.width
    }
}

_testing_append_integer#(.t: Type: Int)(.self: $&_TestDiagnostic, .value: t) -> () := {
    encoded ::= _decimal_encode#(.t: t)(.value = value)
    _testing_append(self, .text = _decimal_view(&encoded).view)
}

_testing_append_float#(.t: Type: Float)(.self: $&_TestDiagnostic, .value: t) -> () := {
    encoded ::= _float_encode(.value = value)
    _testing_append(self, .text = _float_text_view(&encoded).view)
}

_testing_detail(.self: &_TestDiagnostic) -> (.text: StringView) := {
    text = (._data = &self&._bytes[0], ._length = self&._length)
}

_testing_failure(.detail: StringView, .message: StringView) -> (
    .result : Errable#(Void, (..test_failed))
) := {
    if message._length != 0 { add_context(.context = message) }
    test_fail_impl()!! detail

    result = ..ok Void()
}

fail(.message: StringView) -> (.result: Errable#(Void, (..test_failed))) := {
    test_fail_impl()!! message

    result = ..ok Void()
}

_assert_equal_integer#(.t: Type: Int)(.expected: t, .actual: t, .message: StringView = "") -> (
    .result : Errable#(Void, (..test_failed))
) := {
    if expected == actual {
        result = ..ok Void()
        return
    }

    diagnostic ::= _TestDiagnostic()
    _testing_append($&diagnostic, .text = "expect_equal failed: expected ")
    _testing_append_number($&diagnostic, .value = expected)
    _testing_append($&diagnostic, .text = ", actual ")
    _testing_append_number($&diagnostic, .value = actual)

    result = _testing_failure(.detail = _testing_detail(&diagnostic).text, .message = message)
}

_assert_equal_float#(.t: Type: Float)(.expected: t, .actual: t, .message: StringView = "") -> (
    .result : Errable#(Void, (..test_failed))
) := {
    if expected == actual {
        result = ..ok Void()
        return
    }

    diagnostic ::= _TestDiagnostic()
    _testing_append($&diagnostic, .text = "expect_equal failed: expected ")
    _testing_append_number($&diagnostic, .value = expected)
    _testing_append($&diagnostic, .text = ", actual ")
    _testing_append_number($&diagnostic, .value = actual)

    result = _testing_failure(.detail = _testing_detail(&diagnostic).text, .message = message)
}

_assert_equal_bool(.expected: Bool, .actual: Bool, .message: StringView = "") -> (
    .result : Errable#(Void, (..test_failed))
) := {
    if expected == actual {
        result = ..ok Void()
        return
    }

    detail ::= "expect_equal failed: expected false, actual true"

    if expected { detail = "expect_equal failed: expected true, actual false" }

    result = _testing_failure(.detail = detail, .message = message)
}

_testing_lengths(.self: $&_TestDiagnostic, .expected: UIntNative, .actual: UIntNative) -> () := {
    _testing_append(self, .text = "; lengths expected ")
    _testing_append_number(self, .value = expected)
    _testing_append(self, .text = ", actual ")
    _testing_append_number(self, .value = actual)
}

_testing_compare_byte_ranges(
    .expected : ArrayViewRO#(UInt8),
    .actual   : ArrayViewRO#(UInt8),
    .kind     : StringView,
    .message  : StringView = ""
) -> (.result: Errable#(Void, (..test_failed))) := {
    common ::= length(&expected).count

    if length(&actual).count < common { common = length(&actual).count }
    index :: UIntNative = 0

    while index < common {
        if [
            unwrap_or_abort(.value = get(&expected, .index = index))
            != unwrap_or_abort(.value = get(&actual, .index = index))
        ] { break }
        index = index + 1
    }

    if index == common and length(&expected).count == length(&actual).count {
        result = ..ok Void()
        return
    }

    diagnostic ::= _TestDiagnostic()
    _testing_append($&diagnostic, .text = kind)
    _testing_append($&diagnostic, .text = " differ at byte ")
    _testing_append_number($&diagnostic, .value = index)
    _testing_append($&diagnostic, .text = ": expected ")

    if index < length(&expected).count {
        _testing_append_number(
            $&diagnostic, .value = unwrap_or_abort(.value = get(&expected, .index = index))
        )
    } else {
        _testing_append($&diagnostic, .text = "<end>")
    }
    _testing_append($&diagnostic, .text = ", actual ")

    if index < length(&actual).count {
        _testing_append_number(
            $&diagnostic, .value = unwrap_or_abort(.value = get(&actual, .index = index))
        )
    } else {
        _testing_append($&diagnostic, .text = "<end>")
    }
    _testing_lengths(
        $&diagnostic, .expected = length(&expected).count, .actual = length(&actual).count
    )

    result = _testing_failure(.detail = _testing_detail(&diagnostic).text, .message = message)
}

_assert_text_views(.expected: StringView, .actual: StringView, .message: StringView = "") -> (
    .result : Errable#(Void, (..test_failed))
) := {
    result = _testing_compare_byte_ranges(
        .expected = string_bytes(.text = expected)
        .actual   = string_bytes(.text = actual)
        .message  = message
        .kind     = "strings"
    )
}

_assert_owned_strings(.expected: &String, .actual: &String, .message: StringView = "") -> (
    .result : Errable#(Void, (..test_failed))
) := {
    result = expect_equal_strings(
        .expected = as_view(expected), .actual = as_view(actual), .message = message
    )
}

expect_equal_views#(.t: Type)(
    .expected: ArrayViewRO#(.t: t), .actual: ArrayViewRO#(.t: t), .message: StringView = ""
) -> (.result: Errable#(Void, (..test_failed))) := {
    expected_length ::= length(&expected).count
    actual_length ::= length(&actual).count
    common ::= expected_length

    if actual_length < common { common = actual_length }
    index :: UIntNative = 0

    while index < common {
        left ::= trusted_reference_offset#(.t: t)(
            .base = data(&expected).pointer, .elements = index
        ).reference
        right ::= trusted_reference_offset#(.t: t)(
            .base = data(&actual).pointer, .elements = index
        ).reference
        if left&!= right&{ break }
        index = index + 1
    }

    if index == common and expected_length == actual_length {
        result = ..ok Void()
        return
    }

    diagnostic ::= _TestDiagnostic()
    _testing_append($&diagnostic, .text = "views differ at index ")
    _testing_append_number($&diagnostic, .value = index)
    _testing_lengths($&diagnostic, .expected = expected_length, .actual = actual_length)

    result = _testing_failure(.detail = _testing_detail(&diagnostic).text, .message = message)
}

expect_equal_bytes(
    .expected : ArrayViewRO#(.t: UInt8),
    .actual   : ArrayViewRO#(.t: UInt8),
    .message  : StringView = ""
) -> (.result: Errable#(Void, (..test_failed))) := {
    result = _testing_compare_byte_ranges(
        .expected = expected, .actual = actual, .message = message, .kind = "bytes"
    )
}

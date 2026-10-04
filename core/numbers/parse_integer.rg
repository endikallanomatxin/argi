-- Decode ASCII digits without integer casts. The target-domain counter stays
-- within 0..35, so every supported integer type can represent it.
_integer_parse_digit#(.t: Type: Int)(.byte: UInt8) -> (.value: ?t) := {
    normalized :: UInt8 = byte
    if normalized >= 65 and normalized <= 90 {
        normalized = normalized + 32
    }
    alphabet :: StringView = "0123456789abcdefghijklmnopqrstuvwxyz"
    index :: UIntNative = 0
    digit :: t = 0
    while index < alphabet.length {
        if bytes_get(.view = &alphabet, .index = index).byte == normalized {
            value = ..some(.value = digit)
            return
        }
        index = index + 1
        digit = digit + 1
    }
    value = ..none
}

_integer_parse#(
        .t : Type: Int
    )(
        .text           : StringView,
        .base           : UInt8,
        .minimum        : t,
        .maximum        : t,
        .allow_negative : Bool,
    ) -> (
        .result : Errable#(.t: t, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    if base < 2 or base > 36 {
        result = ..error(.reason = ..invalid_base)
        return
    }
    if text.length == 0 {
        result = ..error(.reason = ..invalid_input)
        return
    }
    index :: UIntNative = 0
    negative :: Bool = false
    first ::= bytes_get(.view = &text, .index = 0).byte
    if first == 45 {
        if allow_negative == false {
            result = ..error(.reason = ..invalid_input)
            return
        }
        negative = true
        index = 1
    } else {
        if first == 43 { index = 1 }
    }
    if index == text.length {
        result = ..error(.reason = ..invalid_input)
        return
    }
    radix :: t = 0
    remaining :: UInt8 = base
    while remaining > 0 {
        radix = radix + 1
        remaining = remaining - 1
    }
    accumulated :: t = 0
    while index < text.length {
        decoded ::= _integer_parse_digit#(.t: t)(
            .byte = bytes_get(.view = &text, .index = index).byte
        ).value
        match decoded {
            ..none {
                result = ..error(.reason = ..invalid_input)
                return
            }
            ..some payload {
                digit ::= payload.value
                if digit >= radix {
                    result = ..error(.reason = ..invalid_input)
                    return
                }
                if negative {
                    -- Accumulate negatively: the signed minimum's magnitude
                    -- need not fit in the positive range. Division truncates
                    -- toward zero, giving the smallest permitted accumulator.
                    cutoff ::= minimum + digit
                    cutoff = cutoff / radix
                    if accumulated < cutoff {
                        result = ..error(.reason = ..out_of_range)
                        return
                    }
                    accumulated = accumulated * radix - digit
                } else {
                    cutoff ::= maximum - digit
                    cutoff = cutoff / radix
                    if accumulated > cutoff {
                        result = ..error(.reason = ..out_of_range)
                        return
                    }
                    accumulated = accumulated * radix + digit
                }
            }
        }
        index = index + 1
    }
    result = ..ok accumulated
}

parse_uint8(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: UInt8, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: UInt8)(
        .text           = text
        .base           = base
        .minimum        = 0
        .maximum        = 255
        .allow_negative = false
    ).result
}

parse_uint16(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: UInt16, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: UInt16)(
        .text           = text
        .base           = base
        .minimum        = 0
        .maximum        = 65535
        .allow_negative = false
    ).result
}

parse_uint32(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: UInt32, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: UInt32)(
        .text           = text
        .base           = base
        .minimum        = 0
        .maximum        = 4294967295
        .allow_negative = false
    ).result
}

parse_uint64(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: UInt64, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: UInt64)(
        .text           = text
        .base           = base
        .minimum        = 0
        .maximum        = 18446744073709551615
        .allow_negative = false
    ).result
}

parse_int8(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: Int8, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: Int8)(
        .text           = text
        .base           = base
        .minimum        = -128
        .maximum        = 127
        .allow_negative = true
    ).result
}

parse_int16(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: Int16, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: Int16)(
        .text           = text
        .base           = base
        .minimum        = -32768
        .maximum        = 32767
        .allow_negative = true
    ).result
}

parse_int32(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: Int32, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: Int32)(
        .text           = text
        .base           = base
        .minimum        = -2147483648
        .maximum        = 2147483647
        .allow_negative = true
    ).result
}

parse_int64(
        .text : StringView,
        .base : UInt8       = 10,
    ) -> (
        .result : Errable#(.t: Int64, .reasons: (..invalid_base, ..invalid_input, ..out_of_range))
    ) := {
    result = _integer_parse#(.t: Int64)(
        .text           = text
        .base           = base
        .minimum        = -9223372036854775808
        .maximum        = 9223372036854775807
        .allow_negative = true
    ).result
}

parse_uintnative(
        .text : StringView,
        .base : UInt8       = 10
    ) -> (
        .result : Errable#(
            .t       : UIntNative,
            .reasons : (..invalid_base, ..invalid_input, ..out_of_range)
        )
    ) := {
    zero :: UIntNative = 0
    maximum ::= _integer_limits(.value = zero).maximum
    result = _integer_parse#(.t: UIntNative)(
        .text           = text
        .base           = base
        .minimum        = 0
        .maximum        = maximum
        .allow_negative = false
    ).result
}

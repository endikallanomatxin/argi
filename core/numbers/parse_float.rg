-- Decimal inputs are rounded from exact rational integers, without an
-- intermediate floating-point format or a dependency on the host library.
_float_parse := #(.t: Type: Float) (
    .text: StringView, .precision: Int32, .maximum_exponent: Int32, .minimum_exponent: Int32,
    .maximum_decimal_order: UIntNative, .minimum_decimal_order: UIntNative
) -> (.result: Errable#(t, (..invalid_input, ..out_of_range))) {

    if text._length == 0 {
        result = ..error(.reason = ..invalid_input)
        return
    }

    index :: UIntNative = 0
    negative ::= false
    first ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))

    if first == 45 or first == 43 {
        negative = first == 45
        index = index + 1
    }

    numerator ::= _FloatDecimalInteger()
    denominator ::= _FloatDecimalInteger()
    denominator.words[0] = 1
    has_digit ::= false
    point ::= false
    fractional :: UIntNative = 0
    significant :: UIntNative = 0
    retained :: UIntNative = 0
    sticky ::= false

    while index < text._length {
        byte ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
        if byte == 46 {
            if point {
                result = ..error(.reason = ..invalid_input)
                return
            }
            point = true
        } else {
            if byte < 48 or byte > 57 { break }
            has_digit = true
            if point { fractional = fractional + 1 }
            digit ::= [byte - 48] | convert#(.to: UInt32)(_)
            if significant != 0 or digit != 0 {
                significant = significant + 1
                -- Binary64's most demanding midpoint is a multiple of
                -- 2^-1075, whose terminating decimal has at most 768 significant
                -- digits. Beyond 800 digits only the presence of a nonzero
                -- tail can affect nearest/even rounding.
                if retained < 800 {
                    _float_integer_multiply($&numerator, .factor = 10, .addend = digit)
                    retained = retained + 1
                } else {
                    if digit != 0 { sticky = true }
                }
            }
        }
        index = index + 1
    }

    if has_digit == false {
        result = ..error(.reason = ..invalid_input)
        return
    }

    exponent_negative ::= false
    exponent :: UIntNative = 0

    if index < text._length {
        byte ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
        if byte != 101 and byte != 69 {
            result = ..error(.reason = ..invalid_input)
            return
        }
        index = index + 1
        if index < text._length {
            sign ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
            if sign == 45 or sign == 43 {
                exponent_negative = sign == 45
                index = index + 1
            }
        }
        start ::= index
        -- The exponent cannot be cancelled by more fractional/significand
        -- digits than the input contains. Saturation still scans every byte,
        -- preserving invalid-input precedence even after an enormous exponent.
        cap ::= text._length + 2048
        while index < text._length {
            digit_byte ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
            if digit_byte < 48 or digit_byte > 57 {
                result = ..error(.reason = ..invalid_input)
                return
            }
            digit ::= [digit_byte - 48] | convert#(.to: UIntNative)(_)
            if exponent <= cap / 10 {
                exponent = exponent * 10 + digit
                if exponent > cap { exponent = cap }
            } else {
                exponent = cap
            }
            index = index + 1
        }
        if start == index {
            result = ..error(.reason = ..invalid_input)
            return
        }
    }

    zero :: t = 0.0
    one :: t = 1.0
    two :: t = 2.0
    half :: t = 0.5
    minus_one :: t = -1.0

    if significant == 0 {
        if negative { zero = zero * minus_one }
        result = ..ok zero
        return
    }

    -- Reject only orders that cannot round to a finite nonzero target. Grammar
    -- validation above must finish first, even when the exponent saturates.
    positive_order :: UIntNative = significant - 1
    negative_order :: UIntNative = fractional
    if exponent_negative {
        negative_order = negative_order + exponent
    } else {
        positive_order = positive_order + exponent
    }
    if positive_order >= negative_order {
        if positive_order - negative_order > maximum_decimal_order {
            result = ..error(.reason = ..out_of_range)
            return
        }
    } else {
        if negative_order - positive_order > minimum_decimal_order {
            result = ..error(.reason = ..out_of_range)
            return
        }
    }

    positive_power :: UIntNative = significant - retained
    negative_power :: UIntNative = fractional

    if exponent_negative {
        negative_power = negative_power + exponent
    } else {
        positive_power = positive_power + exponent
    }

    power :: Int32 = 0

    if positive_power >= negative_power {
        difference ::= positive_power - negative_power
        if difference > 400 {
            result = ..error(.reason = ..out_of_range)
            return
        }
        power = unwrap_or_abort(.value = difference | convert#(.to: Int32)(_)).result
    } else {
        difference ::= negative_power - positive_power
        if difference > 1200 {
            result = ..error(.reason = ..out_of_range)
            return
        }
        power = 0 - unwrap_or_abort(.value = difference | convert#(.to: Int32)(_)).result
    }
    -- A retained significand has at most 800 digits. Powers outside these
    -- bounds cannot approach any supported finite nonzero float. Within the
    -- bounds, 256 limbs hold both the rational and its normalization shifts.
    while power >= 4 {
        _float_integer_multiply($&numerator, .factor = 10000)
        power = power - 4
    }
    while power > 0 {
        _float_integer_multiply($&numerator, .factor = 10)
        power = power - 1
    }
    while power <= -4 {
        _float_integer_multiply($&denominator, .factor = 10000)
        power = power + 4
    }
    while power < 0 {
        _float_integer_multiply($&denominator, .factor = 10)
        power = power + 1
    }

    numerator_bits ::= _float_integer_bit_length(&numerator).bits
    denominator_bits ::= _float_integer_bit_length(&denominator).bits
    binary_exponent :: Int32 = 0
    if numerator_bits >= denominator_bits {
        difference ::= numerator_bits - denominator_bits
        _float_integer_shift_left($&denominator, .bits = difference)
        binary_exponent = unwrap_or_abort(.value = difference | convert#(.to: Int32)(_)).result
    } else {
        difference ::= denominator_bits - numerator_bits
        _float_integer_shift_left($&numerator, .bits = difference)
        binary_exponent = 0 - unwrap_or_abort(.value = difference | convert#(.to: Int32)(_)).result
    }
    if _float_integer_compare(.left = &numerator, .right = &denominator).order < 0 {
        _float_integer_multiply($&numerator, .factor = 2)
        binary_exponent = binary_exponent - 1
    }

    if binary_exponent > maximum_exponent or binary_exponent < minimum_exponent - 1 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    bits :: Int32 = precision
    available ::= binary_exponent - minimum_exponent + 1

    if available < bits { bits = available }
    mantissa :: t = 0.0
    odd ::= false
    remaining ::= bits

    while remaining > 0 {
        mantissa = mantissa * two
        odd = _float_integer_compare(.left = &numerator, .right = &denominator).order >= 0
        if odd {
            mantissa = mantissa + one
            _float_integer_subtract($&numerator, .other = &denominator)
        }
        _float_integer_multiply($&numerator, .factor = 2)
        remaining = remaining - 1
    }

    if _float_integer_compare(.left = &numerator, .right = &denominator).order >= 0 {
        _float_integer_subtract($&numerator, .other = &denominator)
        if odd or sticky or _float_integer_nonzero(&numerator).value {
            mantissa = mantissa + one
        }
    }

    if mantissa == zero {
        result = ..error(.reason = ..out_of_range)
        return
    }

    if binary_exponent == maximum_exponent {
        limit :: t = 1.0
        count :: Int32 = precision
        while count > 0 {
            limit = limit * two
            count = count - 1
        }
        if mantissa == limit {
            result = ..error(.reason = ..out_of_range)
            return
        }
    }

    scale :: t = 1.0
    shift ::= binary_exponent - bits + 1

    while shift > 0 {
        scale = scale * two
        shift = shift - 1
    }

    while shift < 0 {
        scale = scale * half
        shift = shift + 1
    }

    value ::= mantissa * scale

    if negative { value = value * minus_one }

    result = ..ok value
}

parse_float16 := (.text: StringView) -> (
    .result : Errable#(Float16, (..invalid_input, ..out_of_range))
) {

    result = _float_parse#(.t: Float16)(
        .text = text, .precision = 11, .maximum_exponent = 15, .minimum_exponent = -24,
        .maximum_decimal_order = 4, .minimum_decimal_order = 8
    ).result
}

parse_float32 := (.text: StringView) -> (
    .result : Errable#(Float32, (..invalid_input, ..out_of_range))
) {

    result = _float_parse#(.t: Float32)(
        .text = text, .precision = 24, .maximum_exponent = 127, .minimum_exponent = -149,
        .maximum_decimal_order = 38, .minimum_decimal_order = 46
    ).result
}

parse_float64 := (.text: StringView) -> (
    .result : Errable#(Float64, (..invalid_input, ..out_of_range))
) {

    result = _float_parse#(.t: Float64)(
        .text = text, .precision = 53, .maximum_exponent = 1023, .minimum_exponent = -1074,
        .maximum_decimal_order = 308, .minimum_decimal_order = 324
    ).result
}

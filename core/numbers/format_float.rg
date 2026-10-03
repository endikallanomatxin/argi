-- Every finite binary value has a nearest/even rounding interval. Exact integers
-- describe its two midpoints, including the narrower lower interval at a
-- normal power of two. Decimal candidates are tested against that interval;
-- no floating arithmetic, locale, allocation, or decimal parser is involved.
_FloatText: Type = (
    .bytes : [32]UInt8 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0)
    .length : UIntNative = 0
)
-- Binary64 needs at most 1076 powers of five and a 55-bit coefficient:
-- fewer than 800 decimal digits, within the shared 4096-bit limb capacity.
_FloatExactDigits: Type = (
    .bytes : [800]UInt8 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    )
    .start : UIntNative = 800
)
_FloatEncoding: Type = (
    .bits           : UInt64
    .fraction_unit  : UInt64
    .exponent_limit : UInt64
    .bias           : Int32
)

_float_encoding(.value: Float16) -> (.encoding: _FloatEncoding) := {
    bits ::= trusted_reinterpret_reference#(.from: Float16, .to: UInt16)(.base = &value).reference&
    encoding = (.bits = UInt64(.value = bits), .fraction_unit = 1024, .exponent_limit = 32,
        .bias = 15)
}

_float_encoding(.value: Float32) -> (.encoding: _FloatEncoding) := {
    bits ::= trusted_reinterpret_reference#(.from: Float32, .to: UInt32)(.base = &value).reference&
    encoding = (.bits = UInt64(.value = bits), .fraction_unit = 8388608, .exponent_limit = 256,
        .bias = 127)
}

_float_encoding(.value: Float64) -> (.encoding: _FloatEncoding) := {
    bits ::= trusted_reinterpret_reference#(.from: Float64, .to: UInt64)(.base = &value).reference&
    encoding = (.bits = bits, .fraction_unit = 4503599627370496, .exponent_limit = 2048,
        .bias = 1023)
}

_float_exact_digits(.integer: _FloatDecimalInteger) -> (.digits: _FloatExactDigits) := {
    digits = _FloatExactDigits()
    remaining ::= integer
    while true {
        byte ::= _decimal_digit#(.t: UInt32)(.digit = _float_integer_divide_ten(.self = $&remaining).remainder).byte
        digits.start = digits.start - 1
        digits.bytes[digits.start] = byte
        if _float_integer_nonzero(.self = &remaining).value == false { break }
    }
}

_float_inside_interval(.candidate: &_FloatDecimalInteger, .lower: &_FloatDecimalInteger,
    .upper : &_FloatDecimalInteger, .closed: Bool) -> (.inside: Bool) := {
    low ::= _float_integer_compare(.left = candidate, .right = lower).order
    high ::= _float_integer_compare(.left = candidate, .right = upper).order
    inside = [low > 0 or [low == 0 and closed]] and [high < 0 or [high == 0 and closed]]
}

_float_text_byte(.text: $&_FloatText, .byte: UInt8) -> () := {
    if text&.length == 32 { abort }
    text&.bytes[text&.length] = byte
    text&.length = text&.length + 1
}

_float_text_view(.self: &_FloatText) -> (.view: StringView) := {
    view = (.data = &self&.bytes[0], .length = self&.length)
}

_float_render(.coefficient: UInt64, .power: Int32, .negative: Bool) -> (.text: _FloatText) := {
    text = _FloatText()
    if negative { _float_text_byte(.text = $&text, .byte = 45) }
    reduced ::= coefficient
    scale ::= power
    while reduced % 10 == 0 { reduced = reduced / 10 scale = scale + 1 }
    digits ::= _decimal_encode(.value = reduced)
    count :: UIntNative = 20 - digits.start
    exponent ::= scale + unwrap_or_abort(.value = Int32(.value = count)).result - 1
    index :: UIntNative = 0
    -- One notation policy applies to every width: fixed for exponents -4..15,
    -- scientific outside that range. Integral fixed values retain '.0'.
    if exponent < -4 or exponent >= 16 {
        _float_text_byte(.text = $&text, .byte = digits.bytes[digits.start])
        index = 1
        if index < count { _float_text_byte(.text = $&text, .byte = 46) }
        while index < count {
            _float_text_byte(.text = $&text, .byte = digits.bytes[digits.start + index])
            index = index + 1
        }
        _float_text_byte(.text = $&text, .byte = 101)
        if exponent < 0 { _float_text_byte(.text = $&text, .byte = 45) exponent = 0 - exponent }
        exponent_digits ::= _decimal_encode(.value = exponent)
        index = exponent_digits.start
        while index < 20 {
            _float_text_byte(.text = $&text, .byte = exponent_digits.bytes[index])
            index = index + 1
        }
        return
    }
    if exponent < 0 {
        _float_text_byte(.text = $&text, .byte = 48)
        _float_text_byte(.text = $&text, .byte = 46)
        zeros ::= 0 - exponent - 1
        while zeros > 0 { _float_text_byte(.text = $&text, .byte = 48) zeros = zeros - 1 }
        while index < count {
            _float_text_byte(.text = $&text, .byte = digits.bytes[digits.start + index])
            index = index + 1
        }
        return
    }
    before_point ::= UIntNative(.value = exponent + 1)
    before ::= unwrap_or_abort(.value = before_point).result
    while index < count or index < before {
        if index == before { _float_text_byte(.text = $&text, .byte = 46) }
        byte :: UInt8 = 48
        if index < count { byte = digits.bytes[digits.start + index] }
        _float_text_byte(.text = $&text, .byte = byte)
        index = index + 1
    }
    if count <= before {
        _float_text_byte(.text = $&text, .byte = 46)
        _float_text_byte(.text = $&text, .byte = 48)
    }
}

_float_encode#(.t: Type: Float)(.value: t) -> (.text: _FloatText) := {
    encoding ::= _float_encoding(.value = value)
    sign_unit ::= encoding.fraction_unit * encoding.exponent_limit
    negative ::= encoding.bits >= sign_unit
    magnitude ::= encoding.bits % sign_unit
    fraction ::= magnitude % encoding.fraction_unit
    exponent_field ::= magnitude / encoding.fraction_unit
    text = _FloatText()
    if exponent_field == encoding.exponent_limit - 1 {
        if fraction != 0 {
            _float_text_byte(.text = $&text, .byte = 110)
            _float_text_byte(.text = $&text, .byte = 97)
            _float_text_byte(.text = $&text, .byte = 110)
        } else {
            if negative { _float_text_byte(.text = $&text, .byte = 45) }
            _float_text_byte(.text = $&text, .byte = 105)
            _float_text_byte(.text = $&text, .byte = 110)
            _float_text_byte(.text = $&text, .byte = 102)
        }
        return
    }
    if magnitude == 0 {
        if negative { _float_text_byte(.text = $&text, .byte = 45) }
        _float_text_byte(.text = $&text, .byte = 48)
        _float_text_byte(.text = $&text, .byte = 46)
        _float_text_byte(.text = $&text, .byte = 48)
        return
    }
    mantissa ::= fraction
    binary_power ::= 1 - encoding.bias
    if exponent_field != 0 {
        mantissa = mantissa + encoding.fraction_unit
        binary_power = unwrap_or_abort(.value = Int32(.value = exponent_field)).result - encoding.bias
    }
    unit ::= encoding.fraction_unit
    while unit > 1 { binary_power = binary_power - 1 unit = unit / 2 }
    -- Midpoints are integral at a common scale two binary places below value.
    -- At a normal binade boundary the predecessor has half the spacing.
    lower_coefficient ::= mantissa * 4 - 2
    if fraction == 0 and exponent_field > 1 { lower_coefficient = mantissa * 4 - 1 }
    lower ::= _float_integer_from_u64(.value = lower_coefficient).integer
    upper ::= _float_integer_from_u64(.value = mantissa * 4 + 2).integer
    exact ::= _float_integer_from_u64(.value = mantissa * 4).integer
    binary_power = binary_power - 2
    decimal_scale :: Int32 = 0
    while binary_power < 0 {
        _float_integer_multiply(.self = $&lower, .factor = 5)
        _float_integer_multiply(.self = $&upper, .factor = 5)
        _float_integer_multiply(.self = $&exact, .factor = 5)
        decimal_scale = decimal_scale + 1
        binary_power = binary_power + 1
    }
    while binary_power > 0 {
        _float_integer_multiply(.self = $&lower, .factor = 2)
        _float_integer_multiply(.self = $&upper, .factor = 2)
        _float_integer_multiply(.self = $&exact, .factor = 2)
        binary_power = binary_power - 1
    }
    digits ::= _float_exact_digits(.integer = exact).digits
    count :: UIntNative = 800 - digits.start
    place ::= _float_integer_from_u64(.value = 1).integer
    remaining ::= count - 1
    while remaining > 0 {
        _float_integer_multiply(.self = $&place, .factor = 10) remaining = remaining - 1
    }
    floor ::= _FloatDecimalInteger()
    coefficient :: UInt64 = 0
    index :: UIntNative = 0
    closed ::= mantissa % 2 == 0
    while index < count and index < 17 {
        digit ::= UInt32(.value = digits.bytes[digits.start + index] - 48)
        coefficient = coefficient * 10 + UInt64(.value = digit)
        _float_integer_add_multiple(.self = $&floor, .other = &place, .factor = digit)
        ceil ::= floor
        _float_integer_add_multiple(.self = $&ceil, .other = &place, .factor = 1)
        floor_ok ::= _float_inside_interval(.candidate = &floor, .lower = &lower, .upper = &upper,
            .closed = closed).inside
        ceil_ok ::= _float_inside_interval(.candidate = &ceil, .lower = &lower, .upper = &upper,
            .closed = closed).inside
        if floor_ok or ceil_ok {
            prefer_ceil :: Bool = false
            if index + 1 < count {
                next ::= digits.bytes[digits.start + index + 1]
                if next > 53 { prefer_ceil = true }
                if next == 53 {
                    tail ::= index + 2
                    sticky :: Bool = false
                    while tail < count {
                        if digits.bytes[digits.start + tail] != 48 { sticky = true break }
                        tail = tail + 1
                    }
                    prefer_ceil = sticky or coefficient % 2 != 0
                }
            }
            if floor_ok == false or [ceil_ok and prefer_ceil] { coefficient = coefficient + 1 }
            power ::= unwrap_or_abort(.value = Int32(.value = count - index - 1)).result - decimal_scale
            text = _float_render(.coefficient = coefficient, .power = power, .negative = negative).text
            return
        }
        _float_integer_divide_ten(.self = $&place)
        index = index + 1
    }
    -- Seventeen significant decimal digits suffice for every supported width.
    abort
}

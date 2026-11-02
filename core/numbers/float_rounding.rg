_float_replace_bits := #(.Value: Type: _FloatRepresentation#(Value)) (
    .value: Value, .bits: UInt64
) -> (.result: Value) {
    result = _FloatRepresentation#(Value).replace_bits(.value = value, .bits = bits)
}

-- Clear fractional mantissa bits without integer conversion of the value.
-- Integral large values and nonfinite values retain their exact encoding.
truncate_float := #(.t: Type: Float) (.value: t) -> (.result: t) {

    encoding ::= _float_encoding(.value = value).encoding
    sign_unit ::= encoding.fraction_unit * encoding.exponent_limit
    sign ::= encoding.bits / sign_unit * sign_unit
    magnitude ::= encoding.bits % sign_unit
    exponent ::= magnitude / encoding.fraction_unit

    if exponent == encoding.exponent_limit - 1 {
        result = value
        return
    }

    bias ::= unwrap_or_abort(.value = encoding.bias | convert#(.to: UInt64)(_))

    if exponent < bias {
        result = _float_replace_bits(.value = value, .bits = sign).result
        return
    }

    shifts ::= exponent - bias
    unit ::= encoding.fraction_unit

    while shifts > 0 and unit > 1 {
        unit = unit / 2
        shifts = shifts - 1
    }

    result = _float_replace_bits(
        .value = value, .bits = encoding.bits - magnitude % unit
    ).result
}

floor_float := #(.t: Type: Float) (.value: t) -> (.result: t) {
    one :: t = 1.0

    result = truncate_float#(.t: t)(.value = value).result

    if is_finite#(.t: t)(.value = value).ok {
        if value < result { result = result - one }
    }
}

ceil_float := #(.t: Type: Float) (.value: t) -> (.result: t) {
    one :: t = 1.0

    result = truncate_float#(.t: t)(.value = value).result

    if is_finite#(.t: t)(.value = value).ok {
        if value > result { result = result + one }
    }
}

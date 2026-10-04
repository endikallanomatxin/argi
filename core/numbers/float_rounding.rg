_float_replace_bits(.value: Float16, .bits: UInt64) -> (.result: Float16) := {
    native ::= unwrap_or_abort(.value = UInt16(.value = bits))
    result = trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(.base = &native).reference&
}

_float_replace_bits(.value: Float32, .bits: UInt64) -> (.result: Float32) := {
    native ::= unwrap_or_abort(.value = UInt32(.value = bits))
    result = trusted_reinterpret_reference#(.from: UInt32, .to: Float32)(.base = &native).reference&
}

_float_replace_bits(.value: Float64, .bits: UInt64) -> (.result: Float64) := {
    result = trusted_reinterpret_reference#(.from: UInt64, .to: Float64)(.base = &bits).reference&
}

-- Clear fractional mantissa bits without integer conversion of the value.
-- Integral large values and nonfinite values retain their exact encoding.
truncate_float#(.t: Type: Float)(.value: t) -> (.result: t) := {
    encoding ::= _float_encoding(.value = value).encoding
    sign_unit ::= encoding.fraction_unit * encoding.exponent_limit
    sign ::= encoding.bits / sign_unit * sign_unit
    magnitude ::= encoding.bits % sign_unit
    exponent ::= magnitude / encoding.fraction_unit
    if exponent == encoding.exponent_limit - 1 {
        result = value
        return
    }
    bias ::= unwrap_or_abort(.value = UInt64(.value = encoding.bias))
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
    result = _float_replace_bits(.value = value, .bits = encoding.bits - magnitude % unit).result
}

floor_float#(.t: Type: Float)(.value: t) -> (.result: t) := {
    one :: t = 1.0
    result = truncate_float#(.t: t)(.value = value).result
    if is_finite#(.t: t)(.value = value).ok {
        if value < result { result = result - one }
    }
}

ceil_float#(.t: Type: Float)(.value: t) -> (.result: t) := {
    one :: t = 1.0
    result = truncate_float#(.t: t)(.value = value).result
    if is_finite#(.t: t)(.value = value).ok {
        if value > result { result = result + one }
    }
}

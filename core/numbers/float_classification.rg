FloatClass: Type = (..zero, ..subnormal, ..normal, ..infinity, ..nan)

FloatClass implements ImplicitlyCopyable

-- Inspect IEEE fields rather than comparing values: NaN comparisons and
-- negative zero must not erase the classification or sign bit.
classify_float#(.t: Type: Float)(.value: t) -> (.classification: FloatClass) := {
    encoding ::= _float_encoding(.value = value).encoding
    magnitude ::= encoding.bits % [encoding.fraction_unit * encoding.exponent_limit]
    exponent ::= magnitude / encoding.fraction_unit
    fraction ::= magnitude % encoding.fraction_unit

    if exponent == encoding.exponent_limit - 1 {
        classification = ..infinity
        if fraction != 0 { classification = ..nan }
        return
    }

    if exponent == 0 {
        classification = ..zero
        if fraction != 0 { classification = ..subnormal }
        return
    }

    classification = ..normal
}

float_sign_bit#(.t: Type: Float)(.value: t) -> (.negative: Bool) := {
    encoding ::= _float_encoding(.value = value).encoding
    negative = encoding.bits >= encoding.fraction_unit * encoding.exponent_limit
}

is_finite#(.t: Type: Float)(.value: t) -> (.ok: Bool) := {
    match classify_float#(.t: t)(.value = value).classification {
        ..zero { ok = true }
        ..subnormal { ok = true }
        ..normal { ok = true }
        ..infinity { ok = false }
        ..nan { ok = false }
    }
}

is_nan#(.t: Type: Float)(.value: t) -> (.ok: Bool) := {
    match classify_float#(.t: t)(.value = value).classification {
        ..nan { ok = true }
        ..zero { ok = false }
        ..subnormal { ok = false }
        ..normal { ok = false }
        ..infinity { ok = false }
    }
}

is_infinite#(.t: Type: Float)(.value: t) -> (.ok: Bool) := {
    match classify_float#(.t: t)(.value = value).classification {
        ..infinity { ok = true }
        ..zero { ok = false }
        ..subnormal { ok = false }
        ..normal { ok = false }
        ..nan { ok = false }
    }
}

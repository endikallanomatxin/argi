-- Scalar IEEE math delegates to LLVM intrinsics without FFI capability.
-- No fast-math flags are enabled. Domain errors follow IEEE results (NaN or
-- infinity); these functions do not expose libc errno or floating exceptions.
_float_math#(.t: Type: Float)(.operation: UInt32, .left: t, .right: t) -> (.result: t) := {}

sqrt#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 0, .left = value, .right = value).result
}

sin#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 1, .left = value, .right = value).result
}

cos#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 2, .left = value, .right = value).result
}

exp#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 3, .left = value, .right = value).result
}

log#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 4, .left = value, .right = value).result
}

exp2#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 6, .left = value, .right = value).result
}

log2#(.t: Type: Float)(.value: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 7, .left = value, .right = value).result
}

pow#(.t: Type: Float)(.base: t, .exponent: t) -> (.result: t) := {
    result = _float_math#(.t: t)(.operation = 5, .left = base, .right = exponent).result
}

abs_float#(.t: Type: Float)(.value: t) -> (.result: t) := {
    encoding ::= _float_encoding(.value = value).encoding
    result = _float_replace_bits(
        .value = value
        .bits  = [
            encoding.bits
            % [encoding.fraction_unit * encoding.exponent_limit]
        ]
    ).result
}

hypot#(.t: Type: Float)(.left: t, .right: t) -> (.result: t) := {
    a ::= abs_float#(.t: t)(.value = left).result
    b ::= abs_float#(.t: t)(.value = right).result
    if is_infinite(.value = a).ok {
        result = a
        return
    }
    if is_infinite(.value = b).ok {
        result = b
        return
    }
    if is_nan(.value = a).ok {
        result = a
        return
    }
    if is_nan(.value = b).ok {
        result = b
        return
    }
    if a < b {
        saved ::= a
        a = b
        b = saved
    }
    zero :: t = 0.0
    one :: t = 1.0
    if a == zero {
        result = a
        return
    }
    ratio ::= b / a
    result = a * sqrt#(.t: t)(.value = one + ratio * ratio).result
}

main() -> (.status_code: Int32 = 0) := {
    positive :: Float64 = 2.75
    negative :: Float64 = -2.75
    if truncate_float#(.t: Float64)(.value = positive).result != 2.0 { abort }
    if truncate_float#(.t: Float64)(.value = negative).result != -2.0 { abort }
    if floor_float#(.t: Float64)(.value = positive).result != 2.0 { abort }
    if floor_float#(.t: Float64)(.value = negative).result != -3.0 { abort }
    if ceil_float#(.t: Float64)(.value = positive).result != 3.0 { abort }
    if ceil_float#(.t: Float64)(.value = negative).result != -2.0 { abort }
    small :: Float32 = -0.25
    truncated ::= truncate_float#(.t: Float32)(.value = small).result
    if float_sign_bit#(.t: Float32)(.value = truncated).negative == false { abort }
    if truncated != 0.0 { abort }
    bits :: UInt16 = 0
    while true {
        value ::= trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(.base = &bits).reference&
        integral ::= truncate_float#(.t: Float16)(.value = value).result
        integral_bits ::= trusted_reinterpret_reference#(.from: Float16, .to: UInt16)(
            .base = &integral
        ).reference&
        if [
            float_sign_bit#(.t: Float16)(.value = value).negative
            != float_sign_bit#(.t: Float16)(.value = integral).negative
        ] { abort }
        if is_finite#(.t: Float16)(.value = value).ok {
            lower ::= floor_float#(.t: Float16)(.value = value).result
            upper ::= ceil_float#(.t: Float16)(.value = value).result
            if lower > value or upper < value { abort }
            if upper - lower > 1.0 { abort }
            if truncate_float#(.t: Float16)(.value = integral).result != integral { abort }
        } else { if integral_bits != bits { abort } }
        if bits == 65535 { break }
        bits = bits + 1
    }
}

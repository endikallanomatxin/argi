main() -> (.status_code: Int32 = 0) := {
    bits :: UInt16 = 0
    zero :: UIntNative = 0
    subnormal :: UIntNative = 0
    normal :: UIntNative = 0
    infinity :: UIntNative = 0
    nan :: UIntNative = 0
    while true {
        value ::= trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(.base = &bits).reference&
        if float_sign_bit#(.t: Float16)(.value = value).negative != [bits >= 32768] { abort }
        match classify_float#(.t: Float16)(.value = value).classification {
            ..zero { zero = zero + 1 }
            ..subnormal { subnormal = subnormal + 1 }
            ..normal { normal = normal + 1 }
            ..infinity { infinity = infinity + 1 }
            ..nan { nan = nan + 1 }
        }
        finite ::= is_finite#(.t: Float16)(.value = value).ok
        infinite ::= is_infinite#(.t: Float16)(.value = value).ok
        not_number ::= is_nan#(.t: Float16)(.value = value).ok
        if finite {
            if infinite or not_number { abort }
        } else { if infinite == not_number { abort } }
        if bits == 65535 { break }
        bits = bits + 1
    }
    if zero != 2 or subnormal != 2046 or normal != 61440 or infinity != 2 or nan != 2046 { abort }
    bits32 :: UInt32 = 4286578688
    negative_infinity ::= trusted_reinterpret_reference#(.from: UInt32, .to: Float32)(
        .base = &bits32
    ).reference&
    if is_infinite#(.t: Float32)(.value = negative_infinity).ok == false { abort }
    if float_sign_bit#(.t: Float32)(.value = negative_infinity).negative == false { abort }
    bits64 :: UInt64 = 9218868437227405313
    nan64 ::= trusted_reinterpret_reference#(.from: UInt64, .to: Float64)(.base = &bits64).reference&
    if is_nan#(.t: Float64)(.value = nan64).ok == false { abort }
}

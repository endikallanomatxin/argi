main() -> (.status_code: Int32 = 0) := {
    value :: Float64 = 9.0
    if sqrt(.value = value).result != 3.0 { abort }
    if pow(.base = value, .exponent = 2.0).result != 81.0 { abort }
    zero :: Float32 = 0.0
    if sin(.value = zero).result != 0.0 or cos(.value = zero).result != 1.0 { abort }
    if exp(.value = zero).result != 1.0 or log(.value = 1.0).result != 0.0 { abort }
    if hypot(.left = 3.0, .right = 4.0).result != 5.0 { abort }
    half :: Float16 = 4.0
    if sqrt(.value = half).result != 2.0 { abort }
    if is_nan(.value = sqrt(.value = -1.0).result).ok == false { abort }
    large :: Float64 = 1.0e200
    result ::= hypot(.left = large, .right = large).result
    if is_finite(.value = result).ok == false or result <= large { abort }
}

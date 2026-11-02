-- Orient a work frame from a normal and an in-plane heading. The heading is
-- projected onto the plane and normalized, not used as a scale or skew axis.
-- No automatic fallback axis is chosen when that heading is indeterminate.
frame_from_directions := #(.Scalar: Type: Float) (
    .origin: Point#(Scalar), .normal: Displacement#(Scalar), .x_direction: Displacement#(Scalar)
) -> (.result: Errable#(Frame#(Scalar), GeometryErrors)) {
    if finite_point(origin).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    z ::= _frame_unit_direction(normal)!
    heading ::= _frame_unit_direction(x_direction)!
    -- Normalize before crossing to avoid squaring large or tiny input scales.
    raw_y ::= cross(.left = z, .right = heading).result
    sine ::= norm(raw_y).value
    if sine == 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    if sine <= _float_resolution#(Scalar)().value * 64.0 {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    y: Displacement#(Scalar) = (raw_y.x / sine, raw_y.y / sine, raw_y.z / sine)
    x ::= cross(.left = y, .right = z).result
    value: Frame#(Scalar) = (.origin = origin, .x = x, .y = y, .z = z)
    validate_frame(value)!
    result = ..ok value
}

_frame_unit_direction := #(.Scalar: Type: Float) (.value: Displacement#(Scalar)) -> (
    .result : Errable#(Displacement#(Scalar), GeometryErrors)
) {
    if [
        is_finite(value.x).ok == false
        or is_finite(value.y).ok == false
        or is_finite(value.z).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    length ::= norm(value).value
    if is_finite(length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if length == 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    result = ..ok(value.x / length, value.y / length, value.z / length)
}

-- Derivatives with respect to angle in radians, including their speed.
-- Translation is validated but never added to a derivative vector.
circle_derivative := #(.Scalar: Type: Float) (.circle: Circle#(Scalar), .angle: Scalar) -> (
    .result : Errable#(Displacement#(Scalar), GeometryErrors)
) {
    validate_circle(circle)!
    if is_finite(angle).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    derivative ::= _frame_vector(
        .frame = circle.frame
        .x     = [0.0 - circle.radius * sin(angle).result]
        .y     = [circle.radius * cos(angle).result]
        .z     = 0.0
    ).value
    if finite_displacement(derivative).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok derivative
}

ellipse_derivative := #(.Scalar: Type: Float) (.ellipse: Ellipse#(Scalar), .angle: Scalar) -> (
    .result : Errable#(Displacement#(Scalar), GeometryErrors)
) {
    validate_ellipse(ellipse)!
    if is_finite(angle).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    c ::= cos(angle).result
    s ::= sin(angle).result
    derivative: Displacement#(Scalar) = (
        .x = ellipse.sine.x * c - ellipse.cosine.x * s
        .y = ellipse.sine.y * c - ellipse.cosine.y * s
        .z = ellipse.sine.z * c - ellipse.cosine.z * s
    )
    if finite_displacement(derivative).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok derivative
}

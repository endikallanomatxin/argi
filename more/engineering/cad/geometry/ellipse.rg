-- Conjugate radius vectors need not be principal axes. This representation
-- preserves the natural angular parameter of analytic surface intersections.
Ellipse := #(.Scalar: Type: Float) (
    .center : Point#(Scalar),
    .cosine : Displacement#(Scalar),
    .sine   : Displacement#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Ellipse#(Scalar)) ()

ellipse_point := #(.Scalar: Type: Float) (.ellipse: Ellipse#(Scalar), .angle: Scalar) -> (
    .result : Errable#(Point#(Scalar), GeometryErrors)
) {
    validate_ellipse(ellipse)!
    if is_finite(angle).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    c ::= cos(angle).result
    s ::= sin(angle).result
    point: Point#(Scalar) = (
        .x = ellipse.center.x + ellipse.cosine.x * c + ellipse.sine.x * s
        .y = ellipse.center.y + ellipse.cosine.y * c + ellipse.sine.y * s
        .z = ellipse.center.z + ellipse.cosine.z * c + ellipse.sine.z * s
    )
    if finite_point(point).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok point
}

-- Check independent conjugate axes without squaring their model-unit scale.
-- Degeneracy is a support property, independent of modeling tolerance.
validate_ellipse := #(.Scalar: Type: Float) (.ellipse: Ellipse#(Scalar)) -> (
    .result : Errable#(Void, GeometryErrors)
) {
    if [
        finite_point(ellipse.center).ok == false
        or finite_displacement(ellipse.cosine).ok == false
        or finite_displacement(ellipse.sine).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    a ::= norm(ellipse.cosine).value
    b ::= norm(ellipse.sine).value
    if is_finite(a).ok == false or is_finite(b).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if a == 0.0 or b == 0.0 {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    first: Displacement#(Scalar) = (
        .x = ellipse.cosine.x / a
        .y = ellipse.cosine.y / a
        .z = [ellipse.cosine.z / a]
    )
    second: Displacement#(Scalar) = (
        .x = ellipse.sine.x / b
        .y = ellipse.sine.y / b
        .z = [ellipse.sine.z / b]
    )
    if norm(cross(.left = first, .right = second).result).value == 0.0 {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    result = ..ok Void()
}

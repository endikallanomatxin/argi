-- Certificate for the admitted analytic trim families, using coefficient
-- identities rather than samples. Arbitrary pcurves require a future validator.
_certify_circular_trim := #(.Scalar: Type: Float) (
    .surface   : g.Surface#(Scalar),
    .curve     : Curve#(Scalar),
    .interval  : CurveInterval#(Scalar),
    .pcurve    : PCurve#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    circle :: g.Circle#(Scalar) = (
        .frame = (
            .origin = (0.0, 0.0, 0.0)
            .x      = (1.0, 0.0, 0.0)
            .y      = (0.0, 1.0, 0.0)
            .z      = (0.0, 0.0, 1.0)
        )
        .radius = 1.0
    )
    match curve {
        ..ellipse _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..circle c { circle = c.value }
        ..segment _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
    }
    if circle.radius <= tolerance {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    tau: Scalar = 6.283185307179586
    -- Center, cosine and sine errors add along the full boundary. Allocate a
    -- separate budget to each rather than allowing three modeling tolerances.
    coefficient_tolerance ::= tolerance / 3.0
    match surface {
        ..plane p {
            basis ::= g.frame(.origin = p.value.origin, .axis = p.value.normal)!
            match pcurve {
                ..harmonic _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..line _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..ellipse uv {
                    determinant ::= uv.cosine.u * uv.sine.v - uv.cosine.v * uv.sine.u
                    if is_finite(determinant).ok == false or determinant == 0.0 {
                        result = ..error(.reason = ..numeric_range)
                        return
                    }
                    if uv.start != interval.start * tau or uv.end != interval.end * tau {
                        result = ..error(.reason = ..unsupported_parameterization)
                        return
                    }
                    center ::= _trim_plane_vector(.frame = basis, .uv = uv.center).result
                    cosine ::= _trim_plane_vector(.frame = basis, .uv = uv.cosine).result
                    sine ::= _trim_plane_vector(.frame = basis, .uv = uv.sine).result
                    expected_center: g.Point#(Scalar) = (
                        .x = basis.origin.x + center.x
                        .y = basis.origin.y + center.y
                        .z = basis.origin.z + center.z
                    )
                    _trim_near_point(
                        .a         = expected_center
                        .b         = circle.frame.origin
                        .tolerance = coefficient_tolerance
                    )!
                    _trim_near_vector(
                        .a = cosine
                        .b = _trim_scale(
                            .vector = circle.frame.x, .factor = circle.radius
                        ).result
                        .tolerance = coefficient_tolerance
                    )!
                    _trim_near_vector(
                        .a = sine
                        .b = _trim_scale(
                            .vector = circle.frame.y, .factor = circle.radius
                        ).result
                        .tolerance = coefficient_tolerance
                    )!
                }
            }
        }
        ..sphere s {
            match pcurve {
                ..harmonic _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..ellipse _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..line uv {
                    if [
                        uv.start.u != interval.start * tau
                        or uv.end.u != interval.end * tau
                        or uv.start.v != uv.end.v
                        or uv.start.v <= -1.5707963267948966
                        or uv.start.v >= 1.5707963267948966
                    ] {
                        result = ..error(.reason = ..unsupported_parameterization)
                        return
                    }
                    radial ::= s.radius * cos(uv.start.v).result
                    axial ::= s.radius * sin(uv.start.v).result
                    center: g.Point#(Scalar) = (
                        .x = [s.frame.origin.x + s.frame.z.x * axial]
                        .y = s.frame.origin.y + s.frame.z.y * axial
                        .z = [s.frame.origin.z + s.frame.z.z * axial]
                    )
                    _trim_near_point(
                        .a         = center
                        .b         = circle.frame.origin
                        .tolerance = coefficient_tolerance
                    )!
                    _trim_near_vector(
                        .a = _trim_scale(.vector = s.frame.x, .factor = radial).result
                        .b = _trim_scale(
                            .vector = circle.frame.x, .factor = circle.radius
                        ).result
                        .tolerance = coefficient_tolerance
                    )!
                    _trim_near_vector(
                        .a = _trim_scale(.vector = s.frame.y, .factor = radial).result
                        .b = _trim_scale(
                            .vector = circle.frame.y, .factor = circle.radius
                        ).result
                        .tolerance = coefficient_tolerance
                    )!
                }
            }
        }
        ..cylinder _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..torus _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
    }
    result = ..ok Void()
}

_trim_plane_vector := #(.Scalar: Type: Float) (
    .frame: g.Frame#(Scalar), .uv: ParameterPoint#(Scalar)
) -> (.result: g.Displacement#(Scalar)) {
    result = (
        .x = frame.x.x * uv.u + frame.y.x * uv.v
        .y = frame.x.y * uv.u + frame.y.y * uv.v
        .z = frame.x.z * uv.u + frame.y.z * uv.v
    )
}

_trim_near_vector := #(.Scalar: Type: Float) (
    .a: g.Displacement#(Scalar), .b: g.Displacement#(Scalar), .tolerance: Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    origin: g.Point#(Scalar) = (a.x, a.y, a.z)
    end: g.Point#(Scalar) = (b.x, b.y, b.z)
    result = _trim_near_point(.a = origin, .b = end, .tolerance = tolerance)
}

_trim_near_point := #(.Scalar: Type: Float) (
    .a: g.Point#(Scalar), .b: g.Point#(Scalar), .tolerance: Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    distance ::= g.norm(.vector = g.between(.from = a, .to = b).result).value
    if is_finite(distance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if distance > tolerance {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    result = ..ok Void()
}

_trim_scale := #(.Scalar: Type: Float) (.vector: g.Displacement#(Scalar), .factor: Scalar) -> (
    .result : g.Displacement#(Scalar)
) {
    result = (vector.x * factor, vector.y * factor, vector.z * factor)
}

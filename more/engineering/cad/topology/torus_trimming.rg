-- Two latitude contours bound a directed band in the unwrapped tube angle.
-- The complete longitude contour may be partitioned into shared-support arcs.
_torus_latitude := #(.Scalar: Type: Float) (.curve: PCurve#(Scalar)) -> (
    .result : Errable#(Scalar, BrepErrors)
) {
    match curve {
        ..line line {
            if is_finite(line.start.v).ok == false or line.start.v != line.end.v {
                result = ..error(.reason = ..unsupported_parameterization)
                return
            }
            result = ..ok line.start.v
        }
        ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
        ..harmonic _ { result = ..error(.reason = ..unsupported_boundary) }
    }
}

_admit_torus_band := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .surface   : g.Torus#(Scalar),
    .uses      : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .lengths   : ArrayView#(UIntNative),
    .reversed  : Bool,
    .tolerance : Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    if length(&lengths).count != 2 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    lower_count ::= get(&lengths, .index = 0)!
    upper_count ::= get(&lengths, .index = 1)!
    _admit_periodic_contour(.uses = uses, .start = 0, .count = lower_count)!
    _admit_periodic_contour(.uses = uses, .start = lower_count, .count = upper_count)!
    lower ::= get(uses, .index = 0)!
    upper ::= get(uses, .index = lower_count)!
    if lower.reversed != reversed or upper.reversed == reversed {
        result = ..error(.reason = ..inconsistent_orientation)
        return
    }
    a ::= _torus_latitude(.curve = lower.pcurve)!
    b ::= _torus_latitude(.curve = upper.pcurve)!
    tau: Scalar = 6.283185307179586
    width ::= b - a
    if is_finite(width).ok == false or width <= 0.0 or width >= tau {
        result = ..error(.reason = ..invalid_region_nesting)
        return
    }
    -- Both the selected band and its complement must have resolved clearance.
    gap ::= width
    if tau - width < gap { gap = tau - width }
    distance ::= 2.0 * surface.minor_radius * sin(gap / 2.0).result
    if is_finite(distance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if distance <= tolerance {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    i :: UIntNative = 0
    while i < lower_count + upper_count {
        use ::= get(uses, .index = i)!
        latitude ::= _torus_latitude(.curve = use.pcurve)!
        expected ::= a
        if i >= lower_count { expected = b }
        if latitude != expected {
            result = ..error(.reason = ..unsupported_parameterization)
            return
        }
        match use.pcurve {
            ..line line {
                if [
                    line.start.u != use.interval.start * tau
                    or line.end.u != use.interval.end * tau
                ] {
                    result = ..error(.reason = ..unsupported_parameterization)
                    return
                }
            }
            ..ellipse _ { abort }
            ..harmonic _ { abort }
        }
        ellipse ::= _curve_ellipse(.curve = _pool_curve(pools, .curve = use.curve)!)!
        radial ::= surface.major_radius + surface.minor_radius * cos(latitude).result
        if radial <= tolerance {
            result = ..error(.reason = ..numerical_ambiguity)
            return
        }
        height ::= surface.minor_radius * sin(latitude).result
        center: g.Point#(Scalar) = (
            .x = surface.frame.origin.x + surface.frame.z.x * height
            .y = surface.frame.origin.y + surface.frame.z.y * height
            .z = surface.frame.origin.z + surface.frame.z.z * height
        )
        _trim_near_point(.a = center, .b = ellipse.center, .tolerance = tolerance / 3.0)!
        _trim_near_vector(
            .a         = _trim_scale(.vector = surface.frame.x, .factor = radial).result
            .b         = ellipse.cosine
            .tolerance = [tolerance / 3.0]
        )!
        _trim_near_vector(
            .a         = _trim_scale(.vector = surface.frame.y, .factor = radial).result
            .b         = ellipse.sine
            .tolerance = [tolerance / 3.0]
        )!
        i = i + 1
    }
    result = ..ok Void()
}

-- Periodic reduction carries a conservative scalar precision guard.
-- Near-boundary reductions without resolved phase precision are ambiguous.
_periodic_band_contains := #(.Scalar: Type: Float) (
    .value: Scalar, .lower: Scalar, .upper: Scalar
) -> (.result: Errable#(Bool, BrepErrors)) {
    tau: Scalar = 6.283185307179586
    delta ::= value - lower
    if is_finite(delta).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if value >= lower and value <= upper {
        result = ..ok true
        return
    }
    one: Scalar = 1.0
    resolution :: Scalar = 1.0
    half ::= resolution / 2.0
    while one + half > one {
        resolution = half
        half = resolution / 2.0
    }
    magnitude ::= delta
    if magnitude < 0.0 { magnitude = 0.0 - magnitude }
    uncertainty ::= [magnitude + tau] * resolution * 8.0
    phase ::= delta - floor_float(delta / tau).result * tau
    width ::= upper - lower
    distance ::= phase - width
    if distance < 0.0 { distance = 0.0 - distance }
    if [
        uncertainty >= tau
        or phase <= uncertainty
        or tau - phase <= uncertainty
        or distance <= uncertainty
    ] {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    inside ::= phase <= width
    result = ..ok inside
}

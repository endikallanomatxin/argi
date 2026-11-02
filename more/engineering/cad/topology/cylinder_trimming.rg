_CylinderHeight := #(.Scalar: Type: Float) (
    .constant : Scalar,
    .cosine   : Scalar,
    .sine     : Scalar
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(_CylinderHeight#(Scalar)) ()

_curve_ellipse := #(.Scalar: Type: Float) (.curve: Curve#(Scalar)) -> (
    .result : Errable#(g.Ellipse#(Scalar), BrepErrors)
) {
    match curve {
        ..ellipse e { result = ..ok e.value }
        ..circle c {
            result = ..ok(
                .center = c.value.frame.origin
                .cosine = _trim_scale(
                    .vector = c.value.frame.x, .factor = c.value.radius
                ).result
                .sine = _trim_scale(
                    .vector = c.value.frame.y, .factor = c.value.radius
                ).result
            )
        }
        ..segment _ { result = ..error(.reason = ..unsupported_boundary) }
    }
}

_certify_cylinder_section := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .surface   : g.Cylinder#(Scalar),
    .use       : _ResolvedTrim#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(_CylinderHeight#(Scalar), BrepErrors)) {
    ellipse ::= _curve_ellipse(.curve = _pool_curve(pools, .curve = use.curve)!)!
    match use.pcurve {
        ..line _ { result = ..error(.reason = ..unsupported_boundary) }
        ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
        ..harmonic h {
            if [
                h.origin.u != 0.0
                or h.linear.u != 1.0
                or h.linear.v != 0.0
                or h.cosine.u != 0.0
                or h.sine.u != 0.0
                or h.start != use.interval.start * 6.283185307179586
                or h.end != use.interval.end * 6.283185307179586
            ] {
                result = ..error(.reason = ..unsupported_parameterization)
                return
            }
            center: g.Point#(Scalar) = (
                .x = surface.frame.origin.x + surface.frame.z.x * h.origin.v
                .y = surface.frame.origin.y + surface.frame.z.y * h.origin.v
                .z = surface.frame.origin.z + surface.frame.z.z * h.origin.v
            )
            a: g.Displacement#(Scalar) = (
                .x = surface.frame.x.x * surface.radius + surface.frame.z.x * h.cosine.v
                .y = surface.frame.x.y * surface.radius + surface.frame.z.y * h.cosine.v
                .z = surface.frame.x.z * surface.radius + surface.frame.z.z * h.cosine.v
            )
            b: g.Displacement#(Scalar) = (
                .x = surface.frame.y.x * surface.radius + surface.frame.z.x * h.sine.v
                .y = surface.frame.y.y * surface.radius + surface.frame.z.y * h.sine.v
                .z = surface.frame.y.z * surface.radius + surface.frame.z.z * h.sine.v
            )
            _trim_near_point(.a = center, .b = ellipse.center, .tolerance = tolerance / 3.0)!
            _trim_near_vector(.a = a, .b = ellipse.cosine, .tolerance = tolerance / 3.0)!
            _trim_near_vector(.a = b, .b = ellipse.sine, .tolerance = tolerance / 3.0)!
            result = ..ok(.constant = h.origin.v, .cosine = h.cosine.v, .sine = h.sine.v)
        }
    }
}

_admit_cylinder_band := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .surface   : g.Cylinder#(Scalar),
    .uses      : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .lengths   : ArrayView#(UIntNative),
    .reversed  : Bool,
    .tolerance : Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    if surface.radius <= tolerance {
        result = ..error(.reason = ..invalid_surface)
        return
    }
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
    a ::= _certify_cylinder_section(
        .pools = pools, .surface = surface, .use = lower, .tolerance = tolerance
    )!
    b ::= _certify_cylinder_section(
        .pools = pools, .surface = surface, .use = upper, .tolerance = tolerance
    )!
    i :: UIntNative = 0
    while i < lower_count + upper_count {
        _certify_cylinder_section(
            .pools     = pools
            .surface   = surface
            .use       = get(uses, .index = i)!
            .tolerance = tolerance
        )!
        i = i + 1
    }
    clearance ::= [
        b.constant
        - a.constant
        - hypot(.left = b.cosine - a.cosine, .right = b.sine - a.sine).result
    ]
    if is_finite(clearance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if clearance < [0.0 - tolerance] {
        result = ..error(.reason = ..invalid_region_nesting)
        return
    }
    if clearance <= tolerance {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    result = ..ok Void()
}

_admit_planar_ellipse := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .plane     : g.Plane#(Scalar),
    .use       : _ResolvedTrim#(Scalar),
    .reversed  : Bool,
    .tolerance : Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    ellipse ::= _curve_ellipse(.curve = _pool_curve(pools, .curve = use.curve)!)!
    basis ::= g.frame(.origin = plane.origin, .axis = plane.normal)!
    match use.pcurve {
        ..line _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..harmonic _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..ellipse uv {
            if [
                uv.start != use.interval.start * 6.283185307179586
                or uv.end != use.interval.end * 6.283185307179586
            ] {
                result = ..error(.reason = ..unsupported_parameterization)
                return
            }
            determinant ::= uv.cosine.u * uv.sine.v - uv.cosine.v * uv.sine.u
            if is_finite(determinant).ok == false or determinant == 0.0 {
                result = ..error(.reason = ..numeric_range)
                return
            }
            if [determinant > 0.0] != [use.reversed == reversed] {
                result = ..error(.reason = ..inconsistent_orientation)
                return
            }
            c ::= _trim_plane_vector(.frame = basis, .uv = uv.center).result
            center: g.Point#(Scalar) = (
                .x = basis.origin.x + c.x
                .y = [basis.origin.y + c.y]
                .z = [basis.origin.z + c.z]
            )
            _trim_near_point(.a = center, .b = ellipse.center, .tolerance = tolerance / 3.0)!
            _trim_near_vector(
                .a         = _trim_plane_vector(.frame = basis, .uv = uv.cosine).result
                .b         = ellipse.cosine
                .tolerance = [tolerance / 3.0]
            )!
            _trim_near_vector(
                .a         = _trim_plane_vector(.frame = basis, .uv = uv.sine).result
                .b         = ellipse.sine
                .tolerance = [tolerance / 3.0]
            )!
        }
    }
    result = ..ok Void()
}

_cylinder_height := #(.Scalar: Type: Float) (.curve: PCurve#(Scalar), .u: Scalar) -> (
    .result : Errable#(Scalar, BrepErrors)
) {
    match curve {
        ..line _ { result = ..error(.reason = ..unsupported_boundary) }
        ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
        ..harmonic h {
            value ::= h.origin.v + h.cosine.v * cos(u).result + h.sine.v * sin(u).result
            if is_finite(value).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            result = ..ok value
        }
    }
}

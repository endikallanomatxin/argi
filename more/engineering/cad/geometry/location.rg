ContourLocation := (..inside, ..outside, ..boundary)

-- Query an already validated simple contour. This does not certify simplicity
-- or hole nesting. Distance and uncertainty follow planar-region admission.
locate_in_planar_contour := #(.Scalar: Type: Float) (
    .points    : ArrayView#(Point#(Scalar)),
    .point     : Point#(Scalar),
    .plane     : Plane#(Scalar),
    .tolerance : Scalar                      = 0.000001
) -> (.result: Errable#(ContourLocation, GeometryErrors)) {
    result = _locate_in_planar_walk(
        .points = points, .point = point, .plane = plane, .tolerance = tolerance
    )
}

-- Paired bridge segments cancel in ray parity. Contacts still include them.
_locate_in_planar_walk := #(.Scalar: Type: Float) (
    .points    : ArrayView#(Point#(Scalar)),
    .point     : Point#(Scalar),
    .plane     : Plane#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(ContourLocation, GeometryErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    count ::= length(&points).count
    if count < 3 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    basis ::= frame(.origin = plane.origin, .axis = plane.normal)!
    normalized: Plane#(Scalar) = (.origin = plane.origin, .normal = basis.z)
    p ::= _location_projection(
        .point = point, .plane = normalized, .u = basis.x, .v = basis.y, .tolerance = tolerance
    )!
    resolution ::= _float_resolution#(Scalar)().value
    inside ::= false
    i :: UIntNative = 0
    while i < count {
        a ::= _location_projection(
            .point     = get(&points, .index = i)!
            .plane     = normalized
            .u         = basis.x
            .v         = basis.y
            .tolerance = tolerance
        )!
        b ::= _location_projection(
            .point     = get(&points, .index = [i + 1] % count)!
            .plane     = normalized
            .u         = basis.x
            .v         = basis.y
            .tolerance = tolerance
        )!
        if _region_near_segment(
            .a = a, .b = b, .p = p, .tolerance = tolerance, .resolution = resolution
        )! {
            result = ..ok ..boundary
            return
        }
        if [a.y > p.y] != [b.y > p.y] {
            side ::= _region_orientation(.a = a, .b = b, .p = p, .resolution = resolution)!
            if [side > 0] == [b.y > a.y] { inside = inside == false }
        }
        i = i + 1
    }
    if inside { result = ..ok ..inside } else { result = ..ok ..outside }
}

_location_projection := #(.Scalar: Type: Float) (
    .point     : Point#(Scalar),
    .plane     : Plane#(Scalar),
    .u         : Displacement#(Scalar),
    .v         : Displacement#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(_RegionPoint#(Scalar), GeometryErrors)) {
    if finite_point(point).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    projected ::= _project_region_point(.point = point, .plane = plane, .u = u, .v = v)!
    distance ::= dot(
        .left = between(.from = plane.origin, .to = point).result, .right = plane.normal
    ).value
    if _absolute(distance).result > tolerance {
        result = ..error(.reason = ..nonplanar_face)
        return
    }
    result = ..ok projected
}

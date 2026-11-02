Plane := #(.Scalar: Type: Float) (
    .origin : Point#(Scalar),
    .normal : Displacement#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Plane#(Scalar)) ()

GeometryErrors := (
    ..invalid_tolerance,
    ..invalid_surface,
    ..invalid_coordinate,
    ..degenerate_face,
    ..nonplanar_face,
    ..nonconvex_face,
    ..numeric_range,
    ..numerical_ambiguity,
    ..out_of_bounds,
    ..invalid_region_lengths,
    ..intersecting_contours,
    ..invalid_region_nesting,
    ..inconsistent_orientation,
    ..out_of_memory
)

-- Inputs must describe one strictly convex polygon, in boundary order.
-- Absolute distance tolerance is in the same units and precision as points.
polygon_plane := #(.Scalar: Type: Float, .Indices: Type: IndexableValue#(.Item: UIntNative)) (
    .points    : ArrayView#(Point#(Scalar)),
    .indices   : &Indices,
    .start     : UIntNative,
    .count     : UIntNative,
    .tolerance : Scalar
) -> (.result: Errable#(Plane#(Scalar), GeometryErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    if [start > length(indices).count or count > length(indices).count - start] {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    if count < 3 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    i :: UIntNative = 0
    while i < count {
        index ::= get(indices, .index = start + i)!
        p ::= get(&points, .index = index)!
        if finite_point(p).ok == false {
            result = ..error(.reason = ..invalid_coordinate)
            return
        }
        i = i + 1
    }
    a ::= get(&points, .index = get(indices, .index = start)!)!
    b ::= get(&points, .index = get(indices, .index = start + 1)!)!
    c ::= get(&points, .index = get(indices, .index = start + 2)!)!
    plane ::= _plane_from_corner(.a = a, .b = b, .c = c, .tolerance = tolerance)!
    _check_polygon_planarity(
        .points    = points
        .indices   = indices
        .start     = start
        .count     = count
        .plane     = plane
        .tolerance = tolerance
    )!
    _check_polygon_convexity(
        .points    = points
        .indices   = indices
        .start     = start
        .count     = count
        .plane     = plane
        .tolerance = tolerance
    )!
    result = ..ok plane
}

-- Construct a candidate plane only; polygon predicates are independent.
_plane_from_corner := #(.Scalar: Type: Float) (
    .a: Point#(Scalar), .b: Point#(Scalar), .c: Point#(Scalar), .tolerance: Scalar
) -> (.result: Errable#(Plane#(Scalar), GeometryErrors)) {
    ab ::= between(.from = a, .to = b).result
    ac ::= between(.from = a, .to = c).result
    ab_length ::= norm(ab).value
    ac_length ::= norm(ac).value
    if is_finite(ab_length).ok == false or is_finite(ac_length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if ab_length <= tolerance or ac_length <= tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    ab_unit: Displacement#(Scalar) = (
        .x = ab.x / ab_length
        .y = ab.y / ab_length
        .z = ab.z / ab_length
    )
    ac_unit: Displacement#(Scalar) = (
        .x = ac.x / ac_length
        .y = ac.y / ac_length
        .z = ac.z / ac_length
    )
    raw ::= cross(.left = ab_unit, .right = ac_unit).result
    magnitude ::= norm(raw).value
    if is_finite(magnitude).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if magnitude <= 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    normal: Displacement#(Scalar) = (
        .x = raw.x / magnitude
        .y = raw.y / magnitude
        .z = raw.z / magnitude
    )
    result = ..ok(.origin = a, .normal = normal)
}

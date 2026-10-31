-- Geometric tie-breaking makes inference independent of input traversal order.
_point_before := #(.Scalar: Type: Float) (.a: Point#(Scalar), .b: Point#(Scalar)) -> (.ok: Bool) {
    ok = a.x < b.x or [a.x == b.x and [a.y < b.y or [a.y == b.y and a.z < b.z]]]
}

-- Deterministic support plane, not a least-squares or minimum-width fit.
-- The caller validates finite points, nonempty input and positive tolerance.
_infer_region_plane := #(.Scalar: Type: Float) (
    .points: ArrayView#(Point#(Scalar)), .tolerance: Scalar
) -> (.result: Errable#(Plane#(Scalar), GeometryErrors)) {
    count ::= length(&points).count
    anchor ::= get(&points, .index = 0)!
    i :: UIntNative = 1
    while i < count {
        p ::= get(&points, .index = i)!
        if _point_before(.a = p, .b = anchor).ok { anchor = p }
        i = i + 1
    }
    endpoint ::= anchor
    longest :: Scalar = 0.0
    i = 0
    while i < count {
        p ::= get(&points, .index = i)!
        distance ::= norm(between(.from = anchor, .to = p).result).value
        if is_finite(distance).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if [
            distance > longest
            or [distance == longest and _point_before(.a = p, .b = endpoint).ok]
        ] {
            longest = distance
            endpoint = p
        }
        i = i + 1
    }
    if longest <= tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    edge ::= between(.from = anchor, .to = endpoint).result
    direction: Displacement#(Scalar) = (
        .x = edge.x / longest
        .y = edge.y / longest
        .z = [edge.z / longest]
    )
    third ::= anchor
    widest :: Scalar = 0.0
    raw :: Displacement#(Scalar) = (0.0, 0.0, 0.0)
    i = 0
    while i < count {
        p ::= get(&points, .index = i)!
        candidate ::= cross(
            .left = direction, .right = between(.from = anchor, .to = p).result
        ).result
        distance ::= norm(candidate).value
        if is_finite(distance).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if distance > widest or [distance == widest and _point_before(.a = p, .b = third).ok] {
            widest = distance
            third = p
            raw = candidate
        }
        i = i + 1
    }
    if widest <= tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    normal :: Displacement#(Scalar) = (
        .x = raw.x / widest
        .y = raw.y / widest
        .z = [raw.z / widest]
    )
    -- Fix the sign by the dominant component; ties prefer x, then y, then z.
    dominant ::= normal.x
    if normal.y * normal.y > dominant * dominant { dominant = normal.y }
    if normal.z * normal.z > dominant * dominant { dominant = normal.z }
    if dominant < 0.0 {
        normal = (0.0 - normal.x, 0.0 - normal.y, 0.0 - normal.z)
    }
    minimum :: Scalar = 0.0
    maximum :: Scalar = 0.0
    i = 0
    while i < count {
        distance ::= dot(
            .left  = normal
            .right = between(.from = anchor, .to = get(&points, .index = i)!).result
        ).value
        if is_finite(distance).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if distance < minimum { minimum = distance }
        if distance > maximum { maximum = distance }
        i = i + 1
    }
    span ::= maximum - minimum
    if is_finite(span).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    -- Center the support plane in the measured slab, including both extremes.
    shift ::= minimum + span / 2.0
    origin: Point#(Scalar) = (
        .x = anchor.x + normal.x * shift
        .y = anchor.y + normal.y * shift
        .z = [anchor.z + normal.z * shift]
    )
    if finite_point(origin).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok(.origin = origin, .normal = normal)
}

_region_plane_axis := #(.Scalar: Type: Float) (.plane: Plane#(Scalar)) -> (
    .result : Displacement#(Scalar)
) {
    n ::= plane.normal
    axis :: Displacement#(Scalar) = (1.0, 0.0, 0.0)
    smallest ::= n.x * n.x
    if n.y * n.y < smallest {
        axis = (0.0, 1.0, 0.0)
        smallest = n.y * n.y
    }
    if n.z * n.z < smallest { axis = (0.0, 0.0, 1.0) }
    raw ::= cross(.left = axis, .right = n).result
    size ::= norm(raw).value
    result = (raw.x / size, raw.y / size, raw.z / size)
}

-- Orthogonal projection onto a unit-normal plane. Result remains subject to
-- Scalar rounding; finite arithmetic does not imply exact representability.
project_on_plane := #(.Scalar: Type: Float) (.point: Point#(Scalar), .plane: Plane#(Scalar)) -> (
    .result : Errable#(Point#(Scalar), GeometryErrors)
) {
    distance ::= dot(
        .left = plane.normal, .right = between(.from = plane.origin, .to = point).result
    ).value
    projected: Point#(Scalar) = (
        .x = point.x - plane.normal.x * distance
        .y = [point.y - plane.normal.y * distance]
        .z = [point.z - plane.normal.z * distance]
    )
    if is_finite(distance).ok == false or finite_point(projected).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok projected
}

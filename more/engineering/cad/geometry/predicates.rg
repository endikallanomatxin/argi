-- Predicates consume a unit-normal candidate plane. The caller validates the
-- polygon slice, finite coordinates, count and tolerance before these passes.
_check_polygon_planarity := #(
    .Scalar: Type: Float, .Indices: Type: IndexableValue#(.Item: UIntNative)
) (
    .points    : ArrayView#(Point#(Scalar)),
    .indices   : &Indices,
    .start     : UIntNative,
    .count     : UIntNative,
    .plane     : Plane#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    i :: UIntNative = 0
    while i < count {
        p ::= get(&points, .index = get(indices, .index = start + i)!)!
        offset ::= between(.from = plane.origin, .to = p).result
        distance ::= dot(.left = plane.normal, .right = offset).value
        if is_finite(distance).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if distance > tolerance or distance < [0.0 - tolerance] {
            result = ..error(.reason = ..nonplanar_face)
            return
        }
        i = i + 1
    }
    result = ..ok Void()
}

_check_polygon_convexity := #(
    .Scalar: Type: Float, .Indices: Type: IndexableValue#(.Item: UIntNative)
) (
    .points    : ArrayView#(Point#(Scalar)),
    .indices   : &Indices,
    .start     : UIntNative,
    .count     : UIntNative,
    .plane     : Plane#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    i :: UIntNative = 0
    while i < count {
        p ::= get(&points, .index = get(indices, .index = start + i)!)!
        following ::= [i + 1] % count
        q ::= get(&points, .index = get(indices, .index = start + following)!)!
        edge ::= between(.from = p, .to = q).result
        edge_length ::= norm(edge).value
        if is_finite(edge_length).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if edge_length <= tolerance {
            result = ..error(.reason = ..degenerate_face)
            return
        }
        direction: Displacement#(Scalar) = (
            .x = edge.x / edge_length
            .y = edge.y / edge_length
            .z = edge.z / edge_length
        )
        -- Every other vertex must lie strictly to the interior side of every
        -- edge. Unlike corner-turn checks, this also rejects star polygons.
        j :: UIntNative = 0
        while j < count {
            if j != i and j != following {
                r ::= get(&points, .index = get(indices, .index = start + j)!)!
                pr ::= between(.from = p, .to = r).result
                side ::= cross(.left = direction, .right = pr).result
                height ::= dot(.left = plane.normal, .right = side).value
                if is_finite(height).ok == false {
                    result = ..error(.reason = ..numeric_range)
                    return
                }
                if height <= tolerance {
                    result = ..error(.reason = ..nonconvex_face)
                    return
                }
            }
            j = j + 1
        }
        i = i + 1
    }
    result = ..ok Void()
}

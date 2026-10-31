-- Vertices are declared identities: equal coordinates do not weld them.
declare_vertex := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .builder: $&BrepBuilder#(Scalar), .point: g.Point#(Scalar), .allocator: $&Provider
) -> (.result: Errable#(idx.Index#(VertexId), BrepErrors)) {
    if g.finite_point(point).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    offset ::= length(&builder&._points).count
    push($&builder&._points, .value = point, .allocator = allocator)!
    result = ..ok idx.bind_index#(VertexId)(.domain = &builder&._domain, .offset = offset).value
}

-- A proper interval of a shared circular or elliptic support.
-- Endpoint identities are explicit and are never welded by coordinates.
-- Canonical direction is increasing support parameter; uses may reverse it.
declare_edge := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .builder   : $&BrepBuilder#(Scalar),
    .curve     : idx.Index#(CurveId),
    .interval  : CurveInterval#(Scalar),
    .start     : idx.Index#(VertexId),
    .end       : idx.Index#(VertexId),
    .allocator : $&Provider
) -> (.result: Errable#(idx.Index#(EdgeId), BrepErrors)) {
    a ::= idx.resolve_index(.domain = &builder&._domain, .index = start)!
    b ::= idx.resolve_index(.domain = &builder&._domain, .index = end)!
    c ::= idx.resolve_index(.domain = &builder&._domain, .index = curve)!
    first ::= get(&builder&._points, .index = a)!
    last ::= get(&builder&._points, .index = b)!
    if a == b {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    span ::= interval.end - interval.start
    if [
        is_finite(interval.start).ok == false
        or is_finite(interval.end).ok == false
        or span <= 0.0
        or span > 1.0
    ] {
        result = ..error(.reason = ..invalid_parameter)
        return
    }
    id ::= c | convert#(.to: CurveId)(_)
    support ::= _pool_curve(&builder&._geometry, .curve = id)!
    p ::= first
    q ::= last
    match support {
        ..ellipse ellipse {
            if span == 1.0 {
                result = ..error(.reason = ..invalid_parameter)
                return
            }
            p = g.ellipse_point(
                .ellipse = ellipse.value, .angle = [interval.start * 6.283185307179586]
            )!
            q = g.ellipse_point(
                .ellipse = ellipse.value, .angle = [interval.end * 6.283185307179586]
            )!
        }
        ..segment _ {
            if interval.start < 0.0 or interval.end > 1.0 {
                result = ..error(.reason = ..invalid_parameter)
                return
            }
            p = curve_point(.curve = support, .parameter = interval.start)!
            q = curve_point(.curve = support, .parameter = interval.end)!
        }
        ..circle circle {
            if span == 1.0 {
                result = ..error(.reason = ..invalid_parameter)
                return
            }
            if circle.value.radius <= builder&._tolerance {
                result = ..error(.reason = ..invalid_surface)
                return
            }
            p = g.circle_point(
                .circle = circle.value, .angle = [interval.start * 6.283185307179586]
            )!
            q = g.circle_point(
                .circle = circle.value, .angle = [interval.end * 6.283185307179586]
            )!
        }
    }
    _trim_near_point(.a = first, .b = p, .tolerance = builder&._tolerance)!
    _trim_near_point(.a = last, .b = q, .tolerance = builder&._tolerance)!
    distance ::= g.norm(.vector = g.between(.from = first, .to = last).result).value
    if is_finite(distance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if distance <= builder&._tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    endpoints: _BrepEdgeVertices = ..some(.value = (.start = a, .end = b))
    result = _append_brep_edge(
        .builder   = builder
        .curve     = id
        .interval  = interval
        .vertices  = endpoints
        .allocator = allocator
    )
}

-- Builder-only canonical endpoints; absent for vertexless closed edges.
_BrepEdgeVertices := (..none, ..some(.value: _BuilderEdge))

implement ImplicitlyCopyable#(_BrepEdgeVertices) ()

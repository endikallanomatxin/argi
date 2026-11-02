g := import ("../geometry")
idx := import ("../storage")

Model := #(.Scalar: Type: Float) (
    ._domain               : idx.IndexDomain,
    ._topology             : Topology,
    ._points               : DynamicArray#(g.Point#(Scalar)),
    ._geometry             : _GeometryPools#(Scalar),
    ._face_surfaces        : DynamicArray#(SurfaceId),
    ._validation_tolerance : Scalar
)

-- Construction acceptance tolerance, not a bound on accumulated operation error.
validation_tolerance := #(.Scalar: Type: Float) (.model: &Model#(Scalar)) -> (.value: Scalar) {
    value = model&._validation_tolerance
}

point := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .vertex: VertexId) -> (
    .result : Errable#(g.Point#(Scalar), (..out_of_bounds))
) {
    result = get(&model&._points, .index = [vertex | convert#(.to: UIntNative)(_)])
}

Curve := #(.Scalar: Type: Float) (
    ..segment(.start: g.Point#(Scalar), .end: g.Point#(Scalar)),
    ..circle(.value: g.Circle#(Scalar)),
    ..ellipse(.value: g.Ellipse#(Scalar))
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Curve#(Scalar)) ()

face_surface := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(g.Surface#(Scalar), (..out_of_bounds))
) {
    reference ::= face_surface_id(model, .face = face)!
    result = _pool_surface#(Scalar)(&model&._geometry, .surface = reference)

}

edge_curve := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .edge: EdgeId) -> (
    .result : Errable#(Curve#(Scalar), (..out_of_bounds))
) {
    item ::= edge_info(model, .edge = edge)!
    match item.curve {
        ..some curve {
            result = _pool_curve#(Scalar)(&model&._geometry, .curve = curve.value)
        }
        ..none {
            first ::= halfedge_info(model, .halfedge = item.first)!
            next ::= halfedge_info(model, .halfedge = first.next)!
            -- Linear edges always have vertices; builders establish this invariant.
            start ::= unwrap_or_abort(.value = halfedge_vertex(first)).result
            end ::= unwrap_or_abort(.value = halfedge_vertex(next)).result
            if first.reversed {
                previous ::= start
                start = end
                end = previous
            }
            curve: Curve#(Scalar) = ..segment(
                .start = point(model, .vertex = start)!
                .end   = point(model, .vertex = end)!
            )
            result = ..ok curve
        }
    }
}

face_plane := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(g.Plane#(Scalar), (..out_of_bounds, ..nonplanar_face))
) {
    match face_surface(model, .face = face)! {
        ..plane plane { result = ..ok plane.value }
        ..cylinder _ { result = ..error(.reason = ..nonplanar_face) }
        ..sphere _ { result = ..error(.reason = ..nonplanar_face) }
        ..torus _ { result = ..error(.reason = ..nonplanar_face) }
    }
}

entity_counts := #(.Scalar: Type: Float) (.model: &Model#(Scalar)) -> (
    .vertices  : UIntNative,
    .edges     : UIntNative,
    .halfedges : UIntNative,
    .loops     : UIntNative,
    .faces     : UIntNative
) {
    counts ::= _topology_entity_counts(&model&._topology)
    vertices = counts.vertices
    edges = counts.edges
    halfedges = counts.halfedges
    loops = counts.loops
    faces = counts.faces
}

halfedge_info := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .halfedge: HalfEdgeId) -> (
    .result : Errable#(HalfEdge, (..out_of_bounds))
) { result = _topology_halfedge_info(&model&._topology, .halfedge = halfedge) }

edge_info := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .edge: EdgeId) -> (
    .result : Errable#(Edge, (..out_of_bounds))
) { result = _topology_edge_info(&model&._topology, .edge = edge) }

loop_info := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .loop: LoopId) -> (
    .result : Errable#(Loop, (..out_of_bounds))
) { result = _topology_loop_info(&model&._topology, .loop = loop) }

face_info := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(Face, (..out_of_bounds))
) { result = _topology_face_info(&model&._topology, .face = face) }

face_loop := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(LoopId, (..out_of_bounds, ..missing_boundary))
) { result = _topology_face_loop(&model&._topology, .face = face) }

is_closed := #(.Scalar: Type: Float) (.model: &Model#(Scalar)) -> (.ok: Bool) {
    ok = _topology_is_closed(&model&._topology).ok
}

opposite := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .halfedge: HalfEdgeId) -> (
    .result : Errable#(?HalfEdgeId, (..out_of_bounds))
) { result = _topology_opposite(&model&._topology, .halfedge = halfedge) }

-- A normalized parameter follows the canonical curve direction. Each use
-- reverses it explicitly; a closed curve's parameter origin is not a vertex.
curve_point := #(.Scalar: Type: Float) (.curve: Curve#(Scalar), .parameter: Scalar) -> (
    .result : Errable#(g.Point#(Scalar), g.GeometryErrors)
) {
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    match curve {
        ..ellipse e {
            result = g.ellipse_point(
                .ellipse = e.value, .angle = [parameter * 6.283185307179586]
            )
        }
        ..circle c {
            result = g.circle_point#(Scalar)(
                .circle = c.value, .angle = [parameter * 6.283185307179586]
            )
        }
        ..segment s {
            p: g.Point#(Scalar) = (
                .x = [1.0 - parameter] * s.start.x + parameter * s.end.x
                .y = [1.0 - parameter] * s.start.y + parameter * s.end.y
                .z = [1.0 - parameter] * s.start.z + parameter * s.end.z
            )
            if g.finite_point#(Scalar)(p).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            result = ..ok p
        }
    }
}

halfedge_point := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .halfedge: HalfEdgeId, .parameter: Scalar
) -> (.result: Errable#(g.Point#(Scalar), g.GeometryErrors)) {
    item ::= halfedge_info(model, .halfedge = halfedge)!
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    value ::= parameter
    if item.reversed { value = 1.0 - parameter }
    interval ::= edge_interval(model, .edge = item.edge)!
    value = [1.0 - value] * interval.start + value * interval.end
    curve ::= edge_curve(model, .edge = item.edge)!
    match curve {
        ..ellipse e {
            result = g.ellipse_point(.ellipse = e.value, .angle = [value * 6.283185307179586])
        }
        ..circle c {
            result = g.circle_point(.circle = c.value, .angle = [value * 6.283185307179586])
        }
        ..segment _ { result = curve_point(.curve = curve, .parameter = value) }
    }
}

face_surface_id := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(SurfaceId, (..out_of_bounds))
) {
    index ::= face | convert#(.to: UIntNative)(_)
    result = get(&model&._face_surfaces, .index = index)
}

surface_geometry := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .surface: SurfaceId) -> (
    .result : Errable#(g.Surface#(Scalar), (..out_of_bounds))
) { result = _pool_surface#(Scalar)(&model&._geometry, .surface = surface) }

-- Resolve public handles once at an API boundary; internal traversal uses compact IDs.
vertex_id := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .vertex: idx.Index#(VertexId)) -> (
    .result : Errable#(VertexId, (..wrong_domain, ..out_of_bounds))
) {
    offset ::= idx.resolve_index(.domain = &model&._domain, .index = vertex)!
    if offset >= entity_counts(model).vertices {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok(.value = offset)
}

edge_id := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .edge: idx.Index#(EdgeId)) -> (
    .result : Errable#(EdgeId, (..wrong_domain, ..out_of_bounds))
) {
    offset ::= idx.resolve_index(.domain = &model&._domain, .index = edge)!
    if offset >= entity_counts(model).edges {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok(.value = offset)
}

face_id := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: idx.Index#(FaceId)) -> (
    .result : Errable#(FaceId, (..wrong_domain, ..out_of_bounds))
) {
    offset ::= idx.resolve_index(.domain = &model&._domain, .index = face)!
    if offset >= entity_counts(model).faces {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok(.value = offset)
}

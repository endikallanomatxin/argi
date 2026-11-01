-- General explicit boundary construction shares the same domain, typed geometry
-- pools and published Model as the polygon builder. Admission is incremental:
-- circular contours and arc subdivisions use analytic coefficient checks.
BrepBuilder := #(.Scalar: Type: Float = Float32) (
    ._domain        : idx.IndexDomain,
    ._points        : DynamicArray#(g.Point#(Scalar)),
    ._geometry      : _GeometryPools#(Scalar),
    ._face_surfaces : DynamicArray#(SurfaceId),
    ._tolerance     : Scalar,
    ._edges         : DynamicArray#(Edge),
    ._edge_vertices : DynamicArray#(_BrepEdgeVertices),
    ._halfedges     : DynamicArray#(HalfEdge),
    ._loops         : DynamicArray#(Loop),
    ._faces         : DynamicArray#(Face)
)

TrimUse := #(.Scalar: Type: Float) (
    .edge     : idx.Index#(EdgeId),
    .pcurve   : PCurve#(Scalar),
    .reversed : Bool                = false
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(TrimUse#(Scalar)) ()

BrepBuilderInitArgs := #(.Scalar: Type: Float) (
    .tolerance : Scalar     = 0.000001,
    .allocator : $&Virtual#(Allocator)
)

implement#(.Scalar: Type: Float) Init#(
    BrepBuilder#(Scalar), BrepBuilderInitArgs#(Scalar)
) (
    .Result : Type = Errable#(BrepBuilder#(Scalar), BrepErrors)
    .init   = BrepBuilderInitArgs#(Scalar) -> (.result: Result) {
        if is_finite(tolerance).ok == false or tolerance <= 0.0 {
            result = ..error(.reason = ..invalid_tolerance)
            return
        }
        domain ::= idx.IndexDomain(.allocator = allocator)!
        points ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
        pools ::= _GeometryPools#(Scalar)(.allocator = allocator)!
        face_surfaces ::= DynamicArray#(SurfaceId)(.allocator = allocator)!
        edges ::= DynamicArray#(Edge)(.allocator = allocator)!
        edge_vertices ::= DynamicArray#(_BrepEdgeVertices)(.allocator = allocator)!
        halfedges ::= DynamicArray#(HalfEdge)(.allocator = allocator)!
        loops ::= DynamicArray#(Loop)(.allocator = allocator)!
        faces ::= DynamicArray#(Face)(.allocator = allocator)!
        result = ..ok(
            ._domain        = ~domain
            ._points        = ~points
            ._geometry      = ~pools
            ._face_surfaces = ~face_surfaces
            ._tolerance     = tolerance
            ._edges         = ~edges
            ._edge_vertices = ~edge_vertices
            ._halfedges     = ~halfedges
            ._loops         = ~loops
            ._faces         = ~faces
        )
    }
)

declare_surface := #(.Scalar: Type: Float) (
    .builder: $&BrepBuilder#(Scalar), .surface: g.Surface#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(SurfaceId), BrepErrors)) {
    g.validate_surface(surface)!
    id ::= _pool_add_surface(
        .pools = $&builder&._geometry, .surface = surface, .allocator = allocator
    )!
    offset ::= id | convert#(.to: UIntNative)(_)
    result = ..ok idx.bind_index#(SurfaceId)(
        .domain = &builder&._domain, .offset = offset
    ).value
}

declare_curve := #(.Scalar: Type: Float) (
    .builder: $&BrepBuilder#(Scalar), .curve: Curve#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(CurveId), BrepErrors)) {
    curve_point(.curve = curve, .parameter = 0.0)!
    curve_point(.curve = curve, .parameter = 0.25)!
    id ::= _pool_add_curve(
        .pools = $&builder&._geometry, .curve = curve, .allocator = allocator
    )!
    offset ::= id | convert#(.to: UIntNative)(_)
    result = ..ok idx.bind_index#(CurveId)(.domain = &builder&._domain, .offset = offset).value
}

-- A vertexless closed edge uses one full period of its curve. The interval is
-- explicit and independent of both the shared support and face-specific pcurves.
declare_closed_edge := #(.Scalar: Type: Float) (
    .builder   : $&BrepBuilder#(Scalar),
    .curve     : idx.Index#(CurveId),
    .interval  : CurveInterval#(Scalar)  = (.start = 0.0, .end = 1.0),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(EdgeId), BrepErrors)) {
    index ::= idx.resolve_index(.domain = &builder&._domain, .index = curve)!
    id ::= index | convert#(.to: CurveId)(_)
    support ::= _pool_curve(&builder&._geometry, .curve = id)!
    match support {
        ..segment _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..circle _ {}
        ..ellipse _ {}
    }
    if [
        is_finite(interval.start).ok == false
        or is_finite(interval.end).ok == false
        or interval.end - interval.start != 1.0
    ] {
        result = ..error(.reason = ..invalid_parameter)
        return
    }
    vertices: _BrepEdgeVertices = ..none
    result = _append_brep_edge(
        .builder   = builder
        .curve     = id
        .interval  = interval
        .vertices  = vertices
        .allocator = allocator
    )
}

_append_brep_edge := #(.Scalar: Type: Float) (
    .builder   : $&BrepBuilder#(Scalar),
    .curve     : CurveId,
    .interval  : CurveInterval#(Scalar),
    .vertices  : _BrepEdgeVertices,
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(EdgeId), BrepErrors)) {

    offset ::= length(&builder&._edges).count
    trim ::= length(&builder&._geometry.intervals).count
    maximum ::= integer_limits(.value = offset).maximum
    if offset == maximum or trim == maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(.self = $&builder&._edges, .capacity = offset + 1, .allocator = allocator)!
    ensure_capacity(
        .self = $&builder&._edge_vertices, .capacity = offset + 1, .allocator = allocator
    )!
    push($&builder&._geometry.intervals, .value = interval, .allocator = allocator)!
    trim_id ::= trim | convert#(.to: CurveIntervalId)(_)
    edge: Edge = (
        .first    = [integer_limits(.value = offset).maximum | convert#(.to: HalfEdgeId)(_)]
        .second   = ..none
        .curve    = ..some(.value = curve)
        .interval = ..some(.value = trim_id)
    )
    push_assume_capacity($&builder&._edges, .value = edge)
    push_assume_capacity($&builder&._edge_vertices, .value = vertices)
    result = ..ok idx.bind_index#(EdgeId)(.domain = &builder&._domain, .offset = offset).value
}

finish_brep := #(.Scalar: Type: Float) (
    .builder: BrepBuilder#(Scalar), .require_closed: Bool = true, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    edge_count ::= length(&builder._edges).count
    if length(&builder._faces).count == 0 {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    closed :: Bool = true
    i :: UIntNative = 0
    while i < edge_count {
        edge ::= get(&builder._edges, .index = i)!
        first_index ::= edge.first | convert#(.to: UIntNative)(_)
        if first_index >= length(&builder._halfedges).count {
            result = ..error(.reason = ..unused_edge)
            return
        }
        match edge.second { ..none { closed = false } ..some _ {} }
        i = i + 1
    }
    if require_closed and closed == false {
        result = ..error(.reason = ..open_boundary)
        return
    }
    topology: Topology = (
        ._vertex_count = length(&builder._points).count
        ._edges        = ~builder._edges
        ._halfedges    = ~builder._halfedges
        ._loops        = ~builder._loops
        ._faces        = ~builder._faces
        ._closed       = closed
    )
    _validate_vertices(&topology, .allocator = allocator)!
    result = ..ok(
        ._domain               = ~builder._domain
        ._topology             = ~topology
        ._points               = ~builder._points
        ._geometry             = ~builder._geometry
        ._face_surfaces        = ~builder._face_surfaces
        ._validation_tolerance = builder._tolerance
    )
}

_attach_brep_use := (
    .edges: $&DynamicArray#(Edge), .index: UIntNative, .halfedge: HalfEdgeId, .first: Bool
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    slot ::= get_mutable_reference(edges, .index = index)!
    if first { slot&.first = halfedge } else { slot&.second = ..some(.value = halfedge) }
    result = ..ok Void()
}

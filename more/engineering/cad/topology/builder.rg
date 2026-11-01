_BuilderEdge := (.start: UIntNative, .end: UIntNative)

_BuilderUse := (.edge: UIntNative, .reversed: Bool)

implement ImplicitlyCopyable#(_BuilderEdge) ()

implement ImplicitlyCopyable#(_BuilderUse) ()

EdgeUse := (.edge: idx.Index#(EdgeId), .reversed: Bool = false)

implement ImplicitlyCopyable#(EdgeUse) ()

-- This initial incremental path builds planar polygonal faces. Analytic batch
-- constructors share the same Model pools, without inventing general trimming.
ModelBuilder := #(.Scalar: Type: Float = Float32) (
    ._domain        : idx.IndexDomain,
    ._points        : DynamicArray#(g.Point#(Scalar)),
    ._edges         : DynamicArray#(_BuilderEdge),
    ._uses          : DynamicArray#(_BuilderUse),
    ._lengths       : DynamicArray#(UIntNative),
    ._face_surfaces : DynamicArray#(SurfaceId),
    ._geometry      : _GeometryPools#(Scalar),
    ._tolerance     : Scalar
)

ModelBuilderInitArgs := #(.Scalar: Type: Float) (
    .tolerance : Scalar     = 0.000001,
    .allocator : $&Virtual#(Allocator)
)

implement#(.Scalar: Type: Float) Init#(
    ModelBuilder#(Scalar), ModelBuilderInitArgs#(Scalar)
) (
    .Result : Type = Errable#(ModelBuilder#(Scalar), BuildErrors)
    .init   = ModelBuilderInitArgs#(Scalar) -> (.result: Result) {
        if is_finite(tolerance).ok == false or tolerance <= 0.0 {
            result = ..error(.reason = ..invalid_tolerance)
            return
        }
        domain ::= idx.IndexDomain(.allocator = allocator)!
        points ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
        edges ::= DynamicArray#(_BuilderEdge)(.allocator = allocator)!
        uses ::= DynamicArray#(_BuilderUse)(.allocator = allocator)!
        lengths ::= DynamicArray#(UIntNative)(.allocator = allocator)!
        surfaces ::= DynamicArray#(SurfaceId)(.allocator = allocator)!
        pools ::= _GeometryPools#(Scalar)(.allocator = allocator)!
        result = ..ok(
            ._domain        = ~domain
            ._points        = ~points
            ._edges         = ~edges
            ._uses          = ~uses
            ._lengths       = ~lengths
            ._face_surfaces = ~surfaces
            ._geometry      = ~pools
            ._tolerance     = tolerance
        )
    }
)

add_vertex := #(.Scalar: Type: Float) (
    .builder: $&ModelBuilder#(Scalar), .point: g.Point#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(VertexId), BuildErrors)) {

    if g.finite_point(point).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    offset ::= length(&builder&._points).count
    push($&builder&._points, .value = point, .allocator = allocator)!
    result = ..ok idx.bind_index#(VertexId)(.domain = &builder&._domain, .offset = offset).value
}

add_edge := #(.Scalar: Type: Float) (
    .builder   : $&ModelBuilder#(Scalar),
    .start     : idx.Index#(VertexId),
    .end       : idx.Index#(VertexId),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(EdgeId), BuildErrors)) {

    a ::= idx.resolve_index(.domain = &builder&._domain, .index = start)!
    b ::= idx.resolve_index(.domain = &builder&._domain, .index = end)!
    vertex_count ::= length(&builder&._points).count
    if a >= vertex_count or b >= vertex_count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    if a == b {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    edge: _BuilderEdge = (.start = a, .end = b)
    offset ::= length(&builder&._edges).count
    push($&builder&._edges, .value = edge, .allocator = allocator)!
    result = ..ok idx.bind_index#(EdgeId)(.domain = &builder&._domain, .offset = offset).value
}

add_surface := #(.Scalar: Type: Float) (
    .builder: $&ModelBuilder#(Scalar), .surface: g.Surface#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(SurfaceId), BuildErrors)) {
    g.validate_surface(surface)!
    offset ::= length(&builder&._geometry.surfaces).count
    _pool_add_surface(.pools = $&builder&._geometry, .surface = surface, .allocator = allocator)!
    result = ..ok idx.bind_index#(SurfaceId)(
        .domain = &builder&._domain, .offset = offset
    ).value
}

add_face := #(.Scalar: Type: Float) (
    .builder   : $&ModelBuilder#(Scalar),
    .surface   : idx.Index#(SurfaceId),
    .boundary  : ArrayView#(EdgeUse),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(idx.Index#(FaceId), BuildErrors)) {
    surface_index ::= idx.resolve_index(.domain = &builder&._domain, .index = surface)!
    surface_id ::= surface_index | convert#(.to: SurfaceId)(_)
    descriptor ::= get(&builder&._geometry.surfaces, .index = surface_index)!
    if descriptor.kind != 0 {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    count ::= length(&boundary).count
    if count < 3 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    -- Validate handles and reserve every destination before changing lengths.
    i :: UIntNative = 0
    while i < count {
        use ::= get(&boundary, .index = i)!
        edge ::= idx.resolve_index(.domain = &builder&._domain, .index = use.edge)!
        get(&builder&._edges, .index = edge)!
        i = i + 1
    }
    offset ::= length(&builder&._face_surfaces).count
    used ::= length(&builder&._uses).count
    if [
        count > integer_limits(.value = used).maximum - used
        or offset == integer_limits(.value = offset).maximum
    ] {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(.self = $&builder&._uses, .capacity = used + count, .allocator = allocator)!
    ensure_capacity(.self = $&builder&._lengths, .capacity = offset + 1, .allocator = allocator)!
    ensure_capacity(
        .self = $&builder&._face_surfaces, .capacity = offset + 1, .allocator = allocator
    )!
    i = 0
    while i < count {
        use ::= get(&boundary, .index = i)!
        edge ::= idx.resolve_index(.domain = &builder&._domain, .index = use.edge)!
        push_assume_capacity(
            $&builder&._uses, .value = (.edge = edge, .reversed = use.reversed)
        )
        i = i + 1
    }
    push_assume_capacity($&builder&._lengths, .value = count)
    push_assume_capacity($&builder&._face_surfaces, .value = surface_id)
    result = ..ok idx.bind_index#(FaceId)(.domain = &builder&._domain, .offset = offset).value
}

-- Validation uses transient flat arrays; published connectivity preserves all IDs.
_validate_builder_geometry := #(.Scalar: Type: Float) (
    .builder: &ModelBuilder#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(Void, BuildErrors)) {

    vertices ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    loops ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    face_count ::= length(&builder&._lengths).count
    cursor :: UIntNative = 0
    f :: UIntNative = 0
    while f < face_count {
        count ::= get(&builder&._lengths, .index = f)!
        surface ::= get(&builder&._face_surfaces, .index = f)!
        surface_index ::= surface | convert#(.to: UIntNative)(_)
        descriptor ::= get(&builder&._geometry.surfaces, .index = surface_index)!
        plane ::= get(&builder&._geometry.planes, .index = descriptor.index)!
        frame ::= g.frame(.origin = plane.origin, .axis = plane.normal)!
        i :: UIntNative = 0
        while i < count {
            use ::= get(&builder&._uses, .index = cursor + i)!
            next ::= get(&builder&._uses, .index = cursor + [i + 1] % count)!
            edge ::= get(&builder&._edges, .index = use.edge)!
            next_edge ::= get(&builder&._edges, .index = next.edge)!
            start ::= edge.start
            end ::= edge.end
            next_start ::= next_edge.start
            if use.reversed {
                start = edge.end
                end = edge.start
            }
            if next.reversed { next_start = next_edge.end }
            if end != next_start {
                result = ..error(.reason = ..invalid_face_lengths)
                return
            }
            point ::= get(&builder&._points, .index = start)!
            distance ::= g.dot(
                .left = g.between(.from = frame.origin, .to = point).result, .right = frame.z
            ).value
            if is_finite(distance).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            if distance > builder&._tolerance or distance < 0.0 - builder&._tolerance {
                result = ..error(.reason = ..nonplanar_face)
                return
            }
            push($&vertices, .value = start, .allocator = allocator)!
            i = i + 1
        }
        push($&loops, .value = 1, .allocator = allocator)!
        cursor = cursor + count
        f = f + 1
    }
    if face_count == 0 {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    points_view ::= view(&builder&._points)
    vertices_view ::= view(&vertices)
    lengths_view ::= view(&builder&._lengths)
    loops_view ::= view(&loops)
    _planar_face_planes#(.Scalar: Scalar)(
        .points           = points_view
        .vertex_indices   = vertices_view
        .contour_lengths  = lengths_view
        .face_loop_counts = loops_view
        .tolerance        = builder&._tolerance
        .allocator        = allocator
    )!
    result = ..ok Void()
}

_builder_topology := (
    .vertex_count   : UIntNative,
    .source_edges   : &DynamicArray#(_BuilderEdge),
    .source_uses    : &DynamicArray#(_BuilderUse),
    .source_lengths : &DynamicArray#(UIntNative),
    .require_closed : Bool,
    .allocator      : $&Virtual#(Allocator)
) -> (.result: Errable#(Topology, BuildErrors)) {
    edge_count ::= length(source_edges).count
    face_count ::= length(source_lengths).count
    halfedge_count ::= length(source_uses).count
    edges :: DynamicArray#(Edge) = DynamicArray#(Edge)(
        .allocator = allocator, .capacity = edge_count
    )!
    halfedges :: DynamicArray#(HalfEdge) = DynamicArray#(HalfEdge)(
        .allocator = allocator, .capacity = halfedge_count
    )!
    loops :: DynamicArray#(Loop) = DynamicArray#(Loop)(
        .allocator = allocator, .capacity = face_count
    )!
    faces :: DynamicArray#(Face) = DynamicArray#(Face)(
        .allocator = allocator, .capacity = face_count
    )!
    seen :: DynamicArray#(UInt8) = DynamicArray#(UInt8)(
        .allocator = allocator, .capacity = edge_count
    )!
    i :: UIntNative = 0
    while i < edge_count {
        empty_edge: Edge = (.first = (.value = 0), .second = ..none, .curve = ..none)
        unused: UInt8 = 0
        push_assume_capacity($&edges, .value = empty_edge)
        push_assume_capacity($&seen, .value = unused)
        i = i + 1
    }
    cursor :: UIntNative = 0
    f :: UIntNative = 0
    while f < face_count {
        count ::= get(source_lengths, .index = f)!
        source: _BuilderFaceUses = (
            .edges = source_edges
            .uses  = source_uses
            .start = cursor
            .count = count
        )
        lengths: [1]UIntNative = (count,)
        _append_topology_face_assume_capacity(
            .halfedges    = $&halfedges
            .loops        = $&loops
            .faces        = $&faces
            .uses         = &source
            .loop_lengths = view(&lengths)
            .reversed     = false
        )
        i = 0
        while i < count {
            use ::= get(source_uses, .index = cursor + i)!
            id ::= [cursor + i] | convert#(.to: HalfEdgeId)(_)
            uses: UInt8 = get(&seen, .index = use.edge)!
            if uses == 2 {
                result = ..error(.reason = ..nonmanifold_edge)
                return
            }
            if uses == 0 {
                slot ::= get_mutable_reference($&edges, .index = use.edge)!
                slot&.first = id
            } else {
                slot ::= get_mutable_reference($&edges, .index = use.edge)!
                previous ::= get(
                    &halfedges, .index = [slot&.first | convert#(.to: UIntNative)(_)]
                )!
                if previous.reversed == use.reversed {
                    result = ..error(.reason = ..inconsistent_orientation)
                    return
                }
                mate: ?HalfEdgeId = ..some(.value = id)
                slot&.second = mate
            }
            seen_slot ::= get_mutable_reference($&seen, .index = use.edge)!
            seen_slot&= uses + 1
            i = i + 1
        }
        cursor = cursor + count
        f = f + 1
    }
    closed ::= true
    i = 0
    while i < edge_count {
        uses: UInt8 = get(&seen, .index = i)!
        if uses == 0 {
            result = ..error(.reason = ..unused_edge)
            return
        }
        if uses == 1 { closed = false }
        i = i + 1
    }
    if require_closed and closed == false {
        result = ..error(.reason = ..open_boundary)
        return
    }
    topology: Topology = (
        ._vertex_count = vertex_count
        ._edges        = ~edges
        ._halfedges    = ~halfedges
        ._loops        = ~loops
        ._faces        = ~faces
        ._closed       = closed
    )
    _validate_vertices(&topology, .allocator = allocator)!
    result = ..ok ~topology
}

finish_model := #(.Scalar: Type: Float) (
    .builder: ModelBuilder#(Scalar), .require_closed: Bool = true, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    [builder | _validate_builder_geometry(&_, .allocator = allocator)]!
    topology ::= _builder_topology(
        .vertex_count   = length(&builder._points).count
        .source_edges   = &builder._edges
        .source_uses    = &builder._uses
        .source_lengths = &builder._lengths
        .require_closed = require_closed
        .allocator      = allocator
    )!
    result = ..ok(
        ._domain               = ~builder._domain
        ._topology             = ~topology
        ._points               = ~builder._points
        ._geometry             = ~builder._geometry
        ._face_surfaces        = ~builder._face_surfaces
        ._validation_tolerance = builder._tolerance
    )
}

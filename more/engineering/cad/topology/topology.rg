-- IDs are local indices in one immutable model, not persistent identities.
VertexId := (.value: UIntNative)

EdgeId := (.value: UIntNative)

HalfEdgeId := (.value: UIntNative)

LoopId := (.value: UIntNative)

FaceId := (.value: UIntNative)

CurveId := (.value: UIntNative)

implement ImplicitlyCopyable#(VertexId) ()

implement ImplicitlyCopyable#(EdgeId) ()

implement ImplicitlyCopyable#(HalfEdgeId) ()

implement ImplicitlyCopyable#(LoopId) ()

implement ImplicitlyCopyable#(FaceId) ()

implement ImplicitlyCopyable#(CurveId) ()

Edge := (
    .first    : HalfEdgeId,
    .second   : ?HalfEdgeId,
    .curve    : ?CurveId,
    .interval : ?CurveIntervalId = ..none
)

HalfEdge := (
    .origin   : ?VertexId,
    .edge     : EdgeId,
    .next     : HalfEdgeId,
    .loop     : LoopId,
    .reversed : Bool        = false,
    .pcurve   : ?PCurveId   = ..none
)

Loop := (.first: HalfEdgeId, .count: UIntNative)

implement ImplicitlyCopyable#(Edge) ()

implement ImplicitlyCopyable#(HalfEdge) ()

implement ImplicitlyCopyable#(Loop) ()

-- Face boundaries occupy one contiguous range. Only planar faces privilege an outer loop.
-- Genus describes the trimmed face, independently of its parameter chart.
Face := (
    .first_loop : LoopId,
    .loop_count : UIntNative,
    .genus      : UIntNative,
    .reversed   : Bool        = false
)

implement ImplicitlyCopyable#(Face) ()

-- Connectivity owns no coordinates and does not depend on scalar precision.
-- Walk order is defined by next, independently of physical halfedge order.
Topology := (
    ._vertex_count : UIntNative,
    ._edges        : DynamicArray#(Edge),
    ._halfedges    : DynamicArray#(HalfEdge),
    ._loops        : DynamicArray#(Loop),
    ._faces        : DynamicArray#(Face),
    ._closed       : Bool
)

_topology_entity_counts := (.topology: &Topology) -> (
    .vertices  : UIntNative,
    .edges     : UIntNative,
    .halfedges : UIntNative,
    .loops     : UIntNative,
    .faces     : UIntNative
) {
    vertices = topology&._vertex_count
    edges = length(&topology&._edges).count
    halfedges = length(&topology&._halfedges).count
    loops = length(&topology&._loops).count
    faces = length(&topology&._faces).count
}

_topology_halfedge_info := (.topology: &Topology, .halfedge: HalfEdgeId) -> (
    .result : Errable#(HalfEdge, (..out_of_bounds))
) {
    result = get(&topology&._halfedges, .index = [halfedge | convert#(.to: UIntNative)(_)])
}

_topology_edge_info := (.topology: &Topology, .edge: EdgeId) -> (
    .result : Errable#(Edge, (..out_of_bounds))
) {
    result = get(&topology&._edges, .index = [edge | convert#(.to: UIntNative)(_)])
}

_topology_loop_info := (.topology: &Topology, .loop: LoopId) -> (
    .result : Errable#(Loop, (..out_of_bounds))
) {
    result = get(&topology&._loops, .index = [loop | convert#(.to: UIntNative)(_)])
}

_topology_face_info := (.topology: &Topology, .face: FaceId) -> (
    .result : Errable#(Face, (..out_of_bounds))
) {
    result = get(&topology&._faces, .index = [face | convert#(.to: UIntNative)(_)])
}

-- First-boundary convenience query; planar builders put the exterior first.
_topology_face_loop := (.topology: &Topology, .face: FaceId) -> (
    .result : Errable#(LoopId, (..out_of_bounds, ..missing_boundary))
) {
    face_data ::= _topology_face_info(topology, .face = face)!
    if face_data.loop_count == 0 {
        result = ..error(.reason = ..missing_boundary)
        return
    }
    result = ..ok face_data.first_loop
}

_topology_is_closed := (.topology: &Topology) -> (.ok: Bool) {
    ok = topology&._closed
}

_topology_opposite := (.topology: &Topology, .halfedge: HalfEdgeId) -> (
    .result : Errable#(?HalfEdgeId, (..out_of_bounds))
) {
    item ::= _topology_halfedge_info(topology, .halfedge = halfedge)!
    edge ::= _topology_edge_info(topology, .edge = item.edge)!
    if edge.first == halfedge {
        result = ..ok edge.second
    } else {
        result = ..ok ..some(.value = edge.first)
    }
}

-- Closed curves have no preferred vertex; asking for one is an explicit error.
halfedge_vertex := (.halfedge: HalfEdge) -> (.result: Errable#(VertexId, (..missing_vertex))) {
    match halfedge.origin {
        ..none { result = ..error(.reason = ..missing_vertex) }
        ..some vertex { result = ..ok vertex.value }
    }
}

implement Convert#(UIntNative, CurveId) (
    .Result  : Type = CurveId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(CurveId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: CurveId) -> (.result: Result) { result = value.value }
)

implement Equal#(CurveId, CurveId) (
    .equal = (.left: CurveId, .right: CurveId) -> (.ok: Bool) {
        ok = left.value == right.value
    }
)

implement Convert#(UIntNative, FaceId) (
    .Result  : Type = FaceId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(FaceId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: FaceId) -> (.result: Result) { result = value.value }
)

implement Equal#(FaceId, FaceId) (
    .equal = (.left: FaceId, .right: FaceId) -> (.ok: Bool) { ok = left.value == right.value }
)

implement Convert#(UIntNative, LoopId) (
    .Result  : Type = LoopId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(LoopId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: LoopId) -> (.result: Result) { result = value.value }
)

implement Equal#(LoopId, LoopId) (
    .equal = (.left: LoopId, .right: LoopId) -> (.ok: Bool) { ok = left.value == right.value }
)

implement Convert#(UIntNative, HalfEdgeId) (
    .Result  : Type = HalfEdgeId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(HalfEdgeId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: HalfEdgeId) -> (.result: Result) { result = value.value }
)

implement Equal#(HalfEdgeId, HalfEdgeId) (
    .equal = (.left: HalfEdgeId, .right: HalfEdgeId) -> (.ok: Bool) {
        ok = [left.value == right.value]
    }
)

implement Convert#(UIntNative, EdgeId) (
    .Result  : Type = EdgeId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(EdgeId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: EdgeId) -> (.result: Result) { result = value.value }
)

implement Equal#(EdgeId, EdgeId) (
    .equal = (.left: EdgeId, .right: EdgeId) -> (.ok: Bool) { ok = left.value == right.value }
)

implement Convert#(UIntNative, VertexId) (
    .Result  : Type = VertexId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(VertexId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: VertexId) -> (.result: Result) { result = value.value }
)

implement Equal#(VertexId, VertexId) (
    .equal = (.left: VertexId, .right: VertexId) -> (.ok: Bool) {
        ok = left.value == right.value
    }
)

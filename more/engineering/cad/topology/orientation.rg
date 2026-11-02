-- Invert every component together. Entity IDs and canonical curve parameters
-- are unchanged; only face orientation and boundary traversal are reversed.
-- As with other immutable edits, the result owns a fresh checked-handle domain.
reverse_orientation := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .allocator: Virtual#(Allocator)
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    topology ::= _reverse_topology(.source = &model&._topology, .allocator = allocator)!
    points ::= copy(&model&._points, .allocator = allocator)!
    pools ::= _copy_geometry_pools(.source = &model&._geometry, .allocator = allocator)!
    surfaces ::= copy(&model&._face_surfaces, .allocator = allocator)!
    domain ::= idx.IndexDomain(.allocator = allocator)!
    result = ..ok(
        ._domain               = ~domain
        ._topology             = ~topology
        ._points               = ~points
        ._geometry             = ~pools
        ._face_surfaces        = ~surfaces
        ._validation_tolerance = model&._validation_tolerance
    )
}

_reverse_topology := (.source: &Topology, .allocator: Virtual#(Allocator)) -> (
    .result : Errable#(Topology, BuildErrors)
) {
    previous ::= _topology_predecessors(.topology = source, .allocator = allocator)!
    edges ::= copy(&source&._edges, .allocator = allocator)!
    loops ::= copy(&source&._loops, .allocator = allocator)!
    count ::= length(&source&._halfedges).count
    count_faces ::= length(&source&._faces).count
    faces ::= DynamicArray#(Face)(.allocator = allocator, .capacity = count_faces)!
    halfedges ::= DynamicArray#(HalfEdge)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0
    while i < count {
        old ::= get(&source&._halfedges, .index = i)!
        successor ::= _topology_halfedge_info(source, .halfedge = old.next)!
        item: HalfEdge = (
            .origin   = successor.origin
            .edge     = old.edge
            .next     = [get(&previous, .index = i)! | convert#(.to: HalfEdgeId)(_)]
            .loop     = old.loop
            .reversed = [old.reversed == false]
            .pcurve   = old.pcurve
        )
        push_assume_capacity($&halfedges, .value = item)
        i = i + 1
    }
    i = 0
    while i < count_faces {
        old ::= get(&source&._faces, .index = i)!
        item: Face = (
            .first_loop = old.first_loop
            .loop_count = old.loop_count
            .genus      = old.genus
            .reversed   = [old.reversed == false]
        )
        push_assume_capacity($&faces, .value = item)
        i = i + 1
    }
    result = ..ok(
        ._vertex_count = source&._vertex_count
        ._edges        = ~edges
        ._halfedges    = ~halfedges
        ._loops        = ~loops
        ._faces        = ~faces
        ._closed       = source&._closed
    )
}

mapped_face := #(.Scalar: Type: Float) (.merge: &FaceMerge#(Scalar), .source_face: FaceId) -> (
    .result : Errable#(FaceId, (..out_of_bounds))
) {
    index ::= source_face | convert#(.to: UIntNative)(_)
    destination ::= get(&merge&._faces, .index = index)!
    result = ..ok(.value = destination)
}

mapped_vertex := #(.Scalar: Type: Float) (.merge: &FaceMerge#(Scalar), .source_vertex: VertexId) -> (
    .result : Errable#(?VertexId, (..out_of_bounds))
) {
    index ::= source_vertex | convert#(.to: UIntNative)(_)
    destination ::= get(&merge&._vertices, .index = index)!
    count ::= length(&merge&._vertices).count
    value :: ?VertexId = ..none
    if destination != count {
        value = ..some(
            .value = [destination | convert#(.to: VertexId)(_)]
        )
    }
    result = ..ok value
}

mapped_edge := #(.Scalar: Type: Float) (.merge: &FaceMerge#(Scalar), .source_edge: EdgeId) -> (
    .result : Errable#(?EdgeId, (..out_of_bounds))
) {
    index ::= source_edge | convert#(.to: UIntNative)(_)
    destination ::= get(&merge&._edges, .index = index)!
    count ::= length(&merge&._edges).count
    value :: ?EdgeId = ..none
    if destination != count {
        value = ..some(
            .value = [destination | convert#(.to: EdgeId)(_)]
        )
    }
    result = ..ok value
}

mapped_face_handle := #(.Scalar: Type: Float) (
    .merge: &FaceMerge#(Scalar), .face: idx.Index#(FaceId)
) -> (.result: Errable#(idx.Index#(FaceId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = merge&._source, .index = face)!
    mapped ::= get(&merge&._faces, .index = offset)!
    result = ..ok idx.bind_index#(FaceId)(
        .domain = &merge&.model._domain, .offset = mapped
    ).value
}

-- Domain membership and deletion are scalar lookup work. Bind the resulting
-- offset to its destination domain only in the public query that owns it.
_merge_index_offset := #(.Kind: Type) (
    .source: &idx.IndexDomain, .mapping: &DynamicArray#(UIntNative), .index: idx.Index#(Kind)
) -> (.result: Errable#(?UIntNative, (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = source, .index = index)!
    mapped ::= get(mapping, .index = offset)!
    count ::= length(mapping).count
    value :: ?UIntNative = ..none
    if mapped != count { value = ..some(.value = mapped) }
    result = ..ok value
}

mapped_vertex_handle := #(.Scalar: Type: Float) (
    .merge: &FaceMerge#(Scalar), .vertex: idx.Index#(VertexId)
) -> (.result: Errable#(?idx.Index#(VertexId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= _merge_index_offset(
        .source = merge&._source, .mapping = &merge&._vertices, .index = vertex
    )!
    value :: ?idx.Index#(VertexId) = ..none
    match offset {
        ..none {}
        ..some mapped {
            value = ..some(
                .value = idx.bind_index#(VertexId)(
                    .domain = &merge&.model._domain, .offset = mapped.value
                ).value
            )
        }
    }
    result = ..ok value
}

mapped_edge_handle := #(.Scalar: Type: Float) (
    .merge: &FaceMerge#(Scalar), .edge: idx.Index#(EdgeId)
) -> (.result: Errable#(?idx.Index#(EdgeId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= _merge_index_offset(
        .source = merge&._source, .mapping = &merge&._edges, .index = edge
    )!
    value :: ?idx.Index#(EdgeId) = ..none
    match offset {
        ..none {}
        ..some mapped {
            value = ..some(
                .value = idx.bind_index#(EdgeId)(
                    .domain = &merge&.model._domain, .offset = mapped.value
                ).value
            )
        }
    }
    result = ..ok value
}

bridge_edge_images := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .source_edge: EdgeId
) -> (.result: Errable#(EdgeImages, (..out_of_bounds))) {
    index ::= source_edge | convert#(.to: UIntNative)(_)
    if index >= bridge&._edges {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    second :: ?EdgeId = ..none
    i :: UIntNative = 0
    while i < 2 {
        match bridge&._split_edges[i] {
            ..none {}
            ..some edge {
                if edge.value == source_edge {
                    second = ..some(.value = bridge&._edge_parts[i])
                }
            }
        }
        i = i + 1
    }
    result = ..ok(.first = source_edge, .second = second)
}

bridge_vertex_image := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .source_vertex: VertexId
) -> (.result: Errable#(VertexId, (..out_of_bounds))) {
    index ::= source_vertex | convert#(.to: UIntNative)(_)
    if index >= bridge&._vertices {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok source_vertex
}

bridge_edge_handle_images := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .edge: idx.Index#(EdgeId)
) -> (.result: Errable#(EdgeHandleImages, (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = bridge&._source, .index = edge)!
    id ::= offset | convert#(.to: EdgeId)(_)
    images ::= bridge_edge_images(bridge, .source_edge = id)!
    first ::= idx.bind_index#(EdgeId)(.domain = &bridge&.model._domain, .offset = offset).value
    second :: ?idx.Index#(EdgeId) = ..none
    match images.second {
        ..none {}
        ..some image {
            index ::= image.value | convert#(.to: UIntNative)(_)
            second = ..some(
                .value = idx.bind_index#(EdgeId)(
                    .domain = &bridge&.model._domain, .offset = index
                ).value
            )
        }
    }
    result = ..ok(.first = first, .second = second)
}

bridge_vertex_handle_image := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .vertex: idx.Index#(VertexId)
) -> (.result: Errable#(idx.Index#(VertexId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = bridge&._source, .index = vertex)!
    id ::= offset | convert#(.to: VertexId)(_)
    bridge_vertex_image(bridge, .source_vertex = id)!
    result = ..ok idx.bind_index#(VertexId)(
        .domain = &bridge&.model._domain, .offset = offset
    ).value
}

bridge_face_image := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .source_face: FaceId
) -> (.result: Errable#(FaceId, (..out_of_bounds))) {
    offset ::= source_face | convert#(.to: UIntNative)(_)
    if offset >= bridge&._faces {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok source_face
}

bridge_face_handle_image := #(.Scalar: Type: Float) (
    .bridge: &FaceBridge#(Scalar), .face: idx.Index#(FaceId)
) -> (.result: Errable#(idx.Index#(FaceId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = bridge&._source, .index = face)!
    id ::= offset | convert#(.to: FaceId)(_)
    bridge_face_image(bridge, .source_face = id)!
    result = ..ok idx.bind_index#(FaceId)(
        .domain = &bridge&.model._domain, .offset = offset
    ).value
}

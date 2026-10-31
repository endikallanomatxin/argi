FaceImages := (.first: FaceId, .second: ?FaceId)

EdgeImages := (.first: EdgeId, .second: ?EdgeId)

implement ImplicitlyCopyable#(FaceImages) ()

implement ImplicitlyCopyable#(EdgeImages) ()

split_face_images := #(.Scalar: Type: Float) (.split: &FaceSplit#(Scalar), .source_face: FaceId) -> (
    .result : Errable#(FaceImages, (..out_of_bounds))
) {
    index ::= source_face | convert#(.to: UIntNative)(_)
    if index >= split&._face_count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    second :: ?FaceId = ..none
    if source_face == split&.faces[0] { second = ..some(.value = split&.faces[1]) }
    result = ..ok(.first = source_face, .second = second)
}

-- The pair follows the original canonical curve, regardless of which face's
-- halfedge specified the endpoint. Unchanged edges have exactly one image.
split_edge_images := #(.Scalar: Type: Float) (.split: &FaceSplit#(Scalar), .source_edge: EdgeId) -> (
    .result : Errable#(EdgeImages, (..out_of_bounds))
) {
    index ::= source_edge | convert#(.to: UIntNative)(_)
    if index >= split&._edges {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    second :: ?EdgeId = ..none
    i :: UIntNative = 0
    while i < 2 {
        match split&._split_edges[i] {
            ..none {}
            ..some edge {
                if edge.value == source_edge {
                    second = ..some(.value = split&._edge_parts[i])
                }
            }
        }
        i = i + 1
    }
    result = ..ok(.first = source_edge, .second = second)
}

split_vertex_image := #(.Scalar: Type: Float) (
    .split: &FaceSplit#(Scalar), .source_vertex: VertexId
) -> (.result: Errable#(VertexId, (..out_of_bounds))) {
    index ::= source_vertex | convert#(.to: UIntNative)(_)
    if index >= split&._vertices {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok source_vertex
}

FaceHandleImages := (.first: idx.Index#(FaceId), .second: ?idx.Index#(FaceId))

EdgeHandleImages := (.first: idx.Index#(EdgeId), .second: ?idx.Index#(EdgeId))

split_face_handle_images := #(.Scalar: Type: Float) (
    .split: &FaceSplit#(Scalar), .face: idx.Index#(FaceId)
) -> (.result: Errable#(FaceHandleImages, (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = split&._source, .index = face)!
    id ::= offset | convert#(.to: FaceId)(_)
    images ::= split_face_images(split, .source_face = id)!
    first ::= idx.bind_index#(FaceId)(.domain = &split&.model._domain, .offset = offset).value
    second :: ?idx.Index#(FaceId) = ..none
    match images.second {
        ..none {}
        ..some image {
            index ::= image.value | convert#(.to: UIntNative)(_)
            second = ..some(
                .value = idx.bind_index#(FaceId)(
                    .domain = &split&.model._domain, .offset = index
                ).value
            )
        }
    }
    result = ..ok(.first = first, .second = second)
}

split_edge_handle_images := #(.Scalar: Type: Float) (
    .split: &FaceSplit#(Scalar), .edge: idx.Index#(EdgeId)
) -> (.result: Errable#(EdgeHandleImages, (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = split&._source, .index = edge)!
    id ::= offset | convert#(.to: EdgeId)(_)
    images ::= split_edge_images(split, .source_edge = id)!
    first ::= idx.bind_index#(EdgeId)(.domain = &split&.model._domain, .offset = offset).value
    second :: ?idx.Index#(EdgeId) = ..none
    match images.second {
        ..none {}
        ..some image {
            index ::= image.value | convert#(.to: UIntNative)(_)
            second = ..some(
                .value = idx.bind_index#(EdgeId)(
                    .domain = &split&.model._domain, .offset = index
                ).value
            )
        }
    }
    result = ..ok(.first = first, .second = second)
}

split_vertex_handle_image := #(.Scalar: Type: Float) (
    .split: &FaceSplit#(Scalar), .vertex: idx.Index#(VertexId)
) -> (.result: Errable#(idx.Index#(VertexId), (..wrong_domain, ..out_of_bounds))) {
    offset ::= idx.resolve_index(.domain = split&._source, .index = vertex)!
    id ::= offset | convert#(.to: VertexId)(_)
    split_vertex_image(split, .source_vertex = id)!
    result = ..ok idx.bind_index#(VertexId)(
        .domain = &split&.model._domain, .offset = offset
    ).value
}

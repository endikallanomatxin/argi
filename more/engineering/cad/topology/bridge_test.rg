test model_bridge_annulus := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    bridge ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    counts ::= entity_counts(&bridge.model)
    [
        testing.expect(
            [
                counts.vertices == 8
                and counts.edges == 9
                and counts.faces == 1
                and counts.loops == 1
            ]
        )!
    ]
    [
        testing.expect(
            [
                counts.halfedges == 10
                and [[loop_info(&bridge.model, .loop = (.value = 0))!].count == 10]
            ]
        )!
    ]
    uses :: UIntNative = 0
    for entry in [loop_halfedges(&bridge.model, .loop = (.value = 0))!] {
        if entry.halfedge.edge == bridge.bridge_edge { uses = uses + 1 }
    }
    testing.expect(uses == 2 and entity_counts(&source).loops == 2)!
}

test model_bridge_edge_interiors_and_history := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    face ::= idx.bind_index#(FaceId)(.domain = &source._domain, .offset = 0).value
    old_edge ::= [halfedge_info(&source, .halfedge = (.value = 0))!].edge
    offset ::= old_edge | convert#(.to: UIntNative)(_)
    edge ::= idx.bind_index#(EdgeId)(.domain = &source._domain, .offset = offset).value
    vertex ::= idx.bind_index#(VertexId)(.domain = &source._domain, .offset = 3).value
    bridge ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.5)
            .hole     = (.halfedge = (.value = 7), .parameter = 0.5)
        )!
    ]
    counts ::= entity_counts(&bridge.model)
    [
        testing.expect(
            [
                counts.vertices == 10
                and counts.edges == 11
                and counts.faces == 1
                and counts.halfedges == 12
            ]
        )!
    ]
    [
        testing.expect([[point(&bridge.model, .vertex = bridge.exterior_vertex)!].x == 2.0])!
    ]
    [
        testing.expect([[point(&bridge.model, .vertex = bridge.hole_vertex)!].x == 2.0])!
    ]
    mapped_face ::= bridge_face_handle_image(&bridge, .face = face)!
    [
        testing.expect([[face_id(&bridge.model, .face = mapped_face)!].value == 0])!
    ]
    mapped_vertex ::= bridge_vertex_handle_image(&bridge, .vertex = vertex)!
    [
        testing.expect([[vertex_id(&bridge.model, .vertex = mapped_vertex)!].value == 3])!
    ]
    mapped_edge ::= bridge_edge_handle_images(&bridge, .edge = edge)!
    match mapped_edge.second {
        ..none {
            testing.fail()!
        }
        ..some value {
            [
                testing.expect([[edge_id(&bridge.model, .edge = value.value)!] != old_edge])!
            ]
        }
    }
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = vertex_id(&source, .vertex = mapped_vertex)
        )!
    ]
    foreign ::= idx.IndexDomain()!
    wrong ::= idx.bind_index#(FaceId)(.domain = &foreign, .offset = 0).value
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = bridge_face_handle_image(&bridge, .face = wrong)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = bridge_face_image(&bridge, .source_face = (.value = 1))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = bridge_edge_images(&bridge, .source_edge = (.value = 8))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = bridge_vertex_image(&bridge, .source_vertex = (.value = 8))
        )!
    ]
}

test model_bridge_preserves_other_hole_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_two_holes#(Float32)()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    bridge ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    [
        testing.expect(
            [
                entity_counts(&bridge.model).loops == 2
                and entity_counts(&bridge.model).faces == 1
            ]
        )!
    ]
    [
        testing.expect([[loop_info(&bridge.model, .loop = (.value = 0))!].count == 10])!
    ]
    [
        testing.expect([[loop_info(&bridge.model, .loop = (.value = 1))!].count == 4])!
    ]
    [
        testing.expect(
            [
                [
                    halfedge_vertex(
                        [
                            halfedge_info(
                                &bridge.model
                                .halfedge = [loop_info(&bridge.model, .loop = (.value = 1))!].first
                            )!
                        ]
                    )!
                ].value
                == 8
            ]
        )!
    ]
}

test model_bridge_rejects_crossings_and_wrong_loops := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = bridge_planar_face(
                &source
                .face     = (.value = 0)
                .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
                .hole     = (.halfedge = (.value = 6), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..endpoint_not_on_boundary
            .actual_result   = bridge_planar_face(
                &source
                .face     = (.value = 0)
                .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
                .hole     = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..endpoint_not_on_boundary
            .actual_result   = bridge_planar_face(
                &source
                .face     = (.value = 0)
                .exterior = (.halfedge = (.value = 4), .parameter = 0.0)
                .hole     = (.halfedge = (.value = 6), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_parameter
            .actual_result   = bridge_planar_face(
                &source
                .face     = (.value = 0)
                .exterior = (.halfedge = (.value = 0), .parameter = -0.1)
                .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
            )
        )!
    ]
    testing.expect(entity_counts(&source).loops == 2 and entity_counts(&source).edges == 8)!
    other_input ::= _split_two_holes#(Float64)()
    multiple ::= [
        from_planar_faces(
            .points           = view(&other_input.points)
            .vertex_indices   = view(&other_input.indices)
            .contour_lengths  = view(&other_input.lengths)
            .face_loop_counts = view(&other_input.face_loops)
            .require_closed   = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = bridge_planar_face(
                &multiple
                .face     = (.value = 0)
                .exterior = (.halfedge = (.value = 3), .parameter = 0.5)
                .hole     = (.halfedge = (.value = 8), .parameter = 0.5)
            )
        )!
    ]
}

_bridge_owned := (.allocator: $&Virtual#(Allocator)) -> (
    .result : Errable#(Model#(Float64), SplitErrors)
) {
    input ::= _planar_annulus()
    source ::= from_planar_faces(
        .points           = view(&input.points)
        .vertex_indices   = view(&input.indices)
        .contour_lengths  = view(&input.lengths)
        .face_loop_counts = view(&input.face_loops)
        .require_closed   = false
        .allocator        = allocator
    )!
    bridge ::= bridge_planar_face(
        &source
        .face      = (.value = 0)
        .exterior  = (.halfedge = (.value = 3), .parameter = 1.0)
        .hole      = (.halfedge = (.value = 7), .parameter = 1.0)
        .allocator = allocator
    )!
    result = ..ok ~bridge.model
}

test model_bridge_owns_geometry_and_rejects_hole_crossing := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    model ::= _bridge_owned(.allocator = allocator)!
    [
        testing.expect(
            [
                entity_counts(&model).loops == 1
                and [point(&model, .vertex = (.value = 4))!].x == 1.0
            ]
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = split_planar_face(
                &model
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
}

_walk_test_use := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .loop: LoopId, .vertex: VertexId
) -> (.result: Errable#(HalfEdgeId, SplitErrors)) {
    for entry in loop_halfedges(model, .loop = loop)! {
        if halfedge_vertex(entry.halfedge)! == vertex {
            bridge ::= false
            match opposite(model, .halfedge = entry.id)! {
                ..none {}
                ..some twin {
                    bridge = halfedge_info(model, .halfedge = twin.value)!.loop == loop
                }
            }
            if bridge == false {
                result = ..ok entry.id
                return
            }
        }
    }
    result = ..error(.reason = ..endpoint_not_on_boundary)
}

test model_walk_split_retains_bridge := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    source ::= _bridge_owned(.allocator = allocator)!
    bottom ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 0))!
    top ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 2))!
    operation ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.875)
            .end   = (.halfedge = top, .parameter = 0.125)
        )!
    ]
    counts ::= entity_counts(&operation.model)
    testing.expect(counts.vertices == 10 and counts.edges == 12 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 14)!
    testing.expect(entity_counts(&source).edges == 9)!
    -- The original bridge still has two uses in one output face.
    bridge ::= edge_info(&operation.model, .edge = (.value = 8))!
    match bridge.second {
        ..none { [testing.fail()!] }
        ..some other {
            a ::= halfedge_info(&operation.model, .halfedge = bridge.first)!
            b ::= halfedge_info(&operation.model, .halfedge = other.value)!
            testing.expect(a.loop == b.loop and a.reversed != b.reversed)!
        }
    }
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = bottom, .parameter = 0.125)
                .end   = (.halfedge = top, .parameter = 0.875)
            )
        )!
    ]
}

test model_walk_split_between_joined_contours := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    source ::= _bridge_owned(.allocator = allocator)!
    outer ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 3))!
    inner ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 5))!
    operation ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = outer, .parameter = 0.0)
            .end   = (.halfedge = inner, .parameter = 0.0)
        )!
    ]
    counts ::= entity_counts(&operation.model)
    testing.expect(counts.vertices == 8 and counts.edges == 10 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 12)!
    bridge ::= edge_info(&operation.model, .edge = (.value = 8))!
    match bridge.second {
        ..none { [testing.fail()!] }
        ..some other {
            a ::= halfedge_info(&operation.model, .halfedge = bridge.first)!
            b ::= halfedge_info(&operation.model, .halfedge = other.value)!
            testing.expect(a.loop != b.loop and a.reversed != b.reversed)!
        }
    }
    merged ::= [
        merge_coplanar_faces(&operation.model, .first = (.value = 0), .second = (.value = 1))!
    ]
    [
        testing.expect([[face_info(&merged.model, .face = (.value = 0))!].loop_count == 2])!
    ]
    testing.expect(entity_counts(&merged.model).edges == 8)!
}

test model_walk_multiple_bridges_and_cut_float32 := (.system: System) -> !() {
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
    first ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    exterior ::= _walk_test_use(&first.model, .loop = (.value = 0), .vertex = (.value = 1))!
    hole ::= _walk_test_use(&first.model, .loop = (.value = 1), .vertex = (.value = 11))!
    second ::= [
        bridge_planar_face(
            &first.model
            .face     = (.value = 0)
            .exterior = (.halfedge = exterior, .parameter = 0.0)
            .hole     = (.halfedge = hole, .parameter = 0.0)
        )!
    ]
    testing.expect(entity_counts(&second.model).loops == 1)!
    bottom ::= _walk_test_use(&second.model, .loop = (.value = 0), .vertex = (.value = 0))!
    top ::= _walk_test_use(&second.model, .loop = (.value = 0), .vertex = (.value = 2))!
    cut ::= [
        split_planar_face(
            &second.model
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.5)
            .end   = (.halfedge = top, .parameter = 0.5)
        )!
    ]
    counts ::= entity_counts(&cut.model)
    testing.expect(counts.vertices == 14 and counts.edges == 17 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 20)!
    testing.expect(counts.vertices + counts.faces == counts.edges - 1)!
}

test model_walk_cut_splits_bridge_and_maps_history := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    source ::= _bridge_owned(.allocator = allocator)!
    edge ::= edge_info(&source, .edge = (.value = 8))!
    top ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 2))!
    operation ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = edge.first, .parameter = 0.5)
            .end   = (.halfedge = top, .parameter = 0.875)
        )!
    ]
    counts ::= entity_counts(&operation.model)
    testing.expect(counts.vertices == 10 and counts.edges == 12 and counts.halfedges == 15)!
    position ::= point(&operation.model, .vertex = operation.cut_start)!
    testing.expect(position.x == 0.5 and position.y == 0.5)!
    images ::= split_edge_images(&operation, .source_edge = (.value = 8))!
    testing.expect(images.first.value == 8)!
    match images.second {
        ..none { [testing.fail()!] }
        ..some part {
            match [edge_info(&operation.model, .edge = part.value)!].second {
                ..none {
                    testing.fail()!
                }
                ..some _ {}
            }
        }
    }
    source_handle ::= idx.bind_index#(EdgeId)(.domain = &source._domain, .offset = 8).value
    mapped ::= split_edge_handle_images(&operation, .edge = source_handle)!
    [
        testing.expect([[edge_id(&operation.model, .edge = mapped.first)!].value == 8])!
    ]
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = edge_id(&source, .edge = mapped.first)
        )!
    ]
}

test model_walk_bridge_branch_and_cut := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_two_holes#(Float64)()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    first ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    bridge ::= edge_info(&first.model, .edge = first.bridge_edge)!
    hole ::= _walk_test_use(&first.model, .loop = (.value = 1), .vertex = (.value = 8))!
    branch ::= [
        bridge_planar_face(
            &first.model
            .face     = (.value = 0)
            .exterior = (.halfedge = bridge.first, .parameter = 0.5)
            .hole     = (.halfedge = hole, .parameter = 0.0)
        )!
    ]
    [
        testing.expect(
            [
                entity_counts(&branch.model).vertices == 13
                and entity_counts(&branch.model).loops == 1
            ]
        )!
    ]
    bottom ::= _walk_test_use(&branch.model, .loop = (.value = 0), .vertex = (.value = 0))!
    top ::= _walk_test_use(&branch.model, .loop = (.value = 0), .vertex = (.value = 2))!
    cut ::= [
        split_planar_face(
            &branch.model
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.9)
            .end   = (.halfedge = top, .parameter = 0.1)
        )!
    ]
    counts ::= entity_counts(&cut.model)
    testing.expect(counts.vertices == 15 and counts.edges == 18 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 22)!
    merged ::= merge_coplanar_faces(&cut.model, .first = (.value = 0), .second = (.value = 1))!
    restored ::= entity_counts(&merged.model)
    testing.expect(restored.vertices == 15 and restored.edges == 17 and restored.faces == 1)!
    testing.expect(restored.loops == 1 and restored.halfedges == 20)!
}

test model_walk_repeated_vertex_selects_side := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    source ::= _bridge_owned(.allocator = allocator)!
    top ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 2))!
    wrong_side ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 0))!
    [
        testing.expect_error(
            .expected_reason = ..invalid_region_nesting
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = wrong_side, .parameter = 0.0)
                .end   = (.halfedge = top, .parameter = 0.875)
            )
        )!
    ]
    right_side ::= [edge_info(&source, .edge = (.value = 8))!].first
    cut ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = right_side, .parameter = 0.0)
            .end   = (.halfedge = top, .parameter = 0.875)
        )!
    ]
    testing.expect(entity_counts(&cut.model).faces == 2)!
    testing.expect(entity_counts(&source).faces == 1)!
}

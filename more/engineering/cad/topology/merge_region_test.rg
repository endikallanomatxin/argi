test model_merge_retains_bridge_after_split := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    source ::= _bridge_owned(.allocator = allocator)!
    bottom ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 0))!
    top ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 2))!
    cut ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.875)
            .end   = (.halfedge = top, .parameter = 0.125)
        )!
    ]
    merged ::= merge_coplanar_faces(&cut.model, .first = cut.faces[0], .second = cut.faces[1])!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 10 and counts.edges == 11 and counts.faces == 1)!
    testing.expect(counts.loops == 1 and counts.halfedges == 12)!
    [
        testing.expect([[mapped_face(&merged, .source_face = cut.faces[0])!].value == 0])!
    ]
    [
        testing.expect([[mapped_face(&merged, .source_face = cut.faces[1])!].value == 0])!
    ]
    match [mapped_edge(&merged, .source_edge = cut.cut_edge)!] {
        ..some _ { [testing.fail()!] }
        ..none {}
    }
    bridge :: EdgeId = (.value = 0)
    match [mapped_edge(&merged, .source_edge = (.value = 8))!] {
        ..none { [testing.fail()!] }
        ..some image { bridge = image.value }
    }
    edge ::= edge_info(&merged.model, .edge = bridge)!
    match edge.second {
        ..none { [testing.fail()!] }
        ..some other {
            a ::= halfedge_info(&merged.model, .halfedge = edge.first)!
            b ::= halfedge_info(&merged.model, .halfedge = other.value)!
            testing.expect(a.loop == b.loop and a.reversed != b.reversed)!
        }
    }
    handle ::= idx.bind_index#(EdgeId)(.domain = &cut.model._domain, .offset = 8).value
    match [mapped_edge_handle(&merged, .edge = handle)!] {
        ..none { [testing.fail()!] }
        ..some image {
            [
                testing.expect([[edge_id(&merged.model, .edge = image.value)!] == bridge])!
            ]
            [
                testing.expect_error(
                    .expected_reason = ..wrong_domain
                    .actual_result   = edge_id(&cut.model, .edge = image.value)
                )!
            ]
        }
    }
    removed_offset ::= cut.cut_edge | convert#(.to: UIntNative)(_)
    removed ::= idx.bind_index#(EdgeId)(
        .domain = &cut.model._domain, .offset = removed_offset
    ).value
    match [mapped_edge_handle(&merged, .edge = removed)!] {
        ..none {}
        ..some _ {
            testing.fail()!
        }
    }
    testing.expect(entity_counts(&cut.model).faces == 2 and entity_counts(&source).edges == 9)!
    -- Cutting again checks that the merged bridge walk remains editable.
    right_bottom ::= [
        _walk_test_use(&merged.model, .loop = (.value = 0), .vertex = (.value = 1))!
    ]
    inner ::= _walk_test_use(&merged.model, .loop = (.value = 0), .vertex = (.value = 7))!
    next ::= [
        split_planar_face(
            &merged.model
            .face  = (.value = 0)
            .start = (.halfedge = right_bottom, .parameter = 0.0)
            .end   = (.halfedge = inner, .parameter = 0.0)
        )!
    ]
    testing.expect(entity_counts(&next.model).faces == 2)!
}

test model_merge_multiple_bridges_float32_reverse_arguments := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
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
    outer ::= _walk_test_use(&first.model, .loop = (.value = 0), .vertex = (.value = 1))!
    hole ::= _walk_test_use(&first.model, .loop = (.value = 1), .vertex = (.value = 11))!
    second ::= [
        bridge_planar_face(
            &first.model
            .face     = (.value = 0)
            .exterior = (.halfedge = outer, .parameter = 0.0)
            .hole     = (.halfedge = hole, .parameter = 0.0)
        )!
    ]
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
    merged ::= merge_coplanar_faces(&cut.model, .first = cut.faces[1], .second = cut.faces[0])!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 14 and counts.edges == 16 and counts.faces == 1)!
    testing.expect(counts.loops == 1 and counts.halfedges == 18)!
    bridge_ids: [2]EdgeId = (first.bridge_edge, second.bridge_edge)
    for id in bridge_ids {
        match [mapped_edge(&merged, .source_edge = id)!] {
            ..none {
                testing.fail()!
            }
            ..some image {
                uses :: UIntNative = 0
                for entry in [loop_halfedges(&merged.model, .loop = (.value = 0))!] {
                    if entry.halfedge.edge == image.value { uses = uses + 1 }
                }
                testing.expect(uses == 2)!
            }
        }
    }
    [
        testing.expect(
            [
                [face_surface_id(&merged.model, .face = (.value = 0))!]
                == [face_surface_id(&cut.model, .face = cut.faces[1])!]
            ]
        )!
    ]
}

test model_merge_bridge_and_unjoined_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
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
    bridge ::= [
        bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    bottom ::= _walk_test_use(&bridge.model, .loop = (.value = 0), .vertex = (.value = 0))!
    top ::= _walk_test_use(&bridge.model, .loop = (.value = 0), .vertex = (.value = 2))!
    cut ::= [
        split_planar_face(
            &bridge.model
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.5)
            .end   = (.halfedge = top, .parameter = 0.5)
        )!
    ]
    merged ::= merge_coplanar_faces(&cut.model, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 14 and counts.edges == 15 and counts.faces == 1)!
    testing.expect(counts.loops == 2 and counts.halfedges == 16)!
    [
        testing.expect([[loop_info(&merged.model, .loop = (.value = 0))!].count == 12])!
    ]
    [
        testing.expect([[loop_info(&merged.model, .loop = (.value = 1))!].count == 4])!
    ]
    -- Both a geometric hole inside the bridged walk and the separate hole survive.
    outer ::= _walk_test_use(&merged.model, .loop = (.value = 0), .vertex = (.value = 1))!
    hole ::= _walk_test_use(&merged.model, .loop = (.value = 1), .vertex = (.value = 11))!
    joined ::= [
        bridge_planar_face(
            &merged.model
            .face     = (.value = 0)
            .exterior = (.halfedge = outer, .parameter = 0.0)
            .hole     = (.halfedge = hole, .parameter = 0.0)
        )!
    ]
    testing.expect(entity_counts(&joined.model).loops == 1)!
}

test model_merge_fills_hole_and_retains_internal_bridge := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    vertices: [12]UIntNative = (0, 1, 2, 3, 4, 5, 6, 7, 4, 7, 6, 5)
    lengths: [3]UIntNative = (4, 4, 4)
    face_loops: [2]UIntNative = (2, 1)
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&face_loops)
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
    merged ::= [
        merge_coplanar_faces(&bridge.model, .first = (.value = 0), .second = (.value = 1))!
    ]
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 5 and counts.edges == 5 and counts.faces == 1)!
    testing.expect(counts.loops == 1 and counts.halfedges == 6)!
    -- The bridge was not an interface. Its interior tip stays explicitly stored.
    match [mapped_vertex(&merged, .source_vertex = (.value = 4))!] {
        ..none {
            testing.fail()!
        }
        ..some id {
            position ::= point(&merged.model, .vertex = id.value)!
            testing.expect(position.x == 1.0 and position.y == 1.0)!
        }
    }
    match [mapped_vertex(&merged, .source_vertex = (.value = 5))!] {
        ..none {}
        ..some _ { [testing.fail()!] }
    }
    match [mapped_edge(&merged, .source_edge = bridge.bridge_edge)!] {
        ..none {
            testing.fail()!
        }
        ..some image {
            uses :: UIntNative = 0
            for entry in [loop_halfedges(&merged.model, .loop = (.value = 0))!] {
                if entry.halfedge.edge == image.value { uses = uses + 1 }
            }
            testing.expect(uses == 2)!
        }
    }
}

test model_merge_refined_bridge_on_hole_and_reedit := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    source ::= _bridge_owned(.allocator = allocator)!
    bridge ::= edge_info(&source, .edge = (.value = 8))!
    top ::= _walk_test_use(&source, .loop = (.value = 0), .vertex = (.value = 2))!
    cut ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = bridge.first, .parameter = 0.5)
            .end   = (.halfedge = top, .parameter = 0.875)
        )!
    ]
    images ::= split_edge_images(&cut, .source_edge = (.value = 8))!
    merged ::= merge_coplanar_faces(&cut.model, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 10 and counts.edges == 10 and counts.faces == 1)!
    testing.expect(counts.loops == 2 and counts.halfedges == 11)!
    match [mapped_edge(&merged, .source_edge = images.first)!] {
        ..none {}
        ..some _ {
            testing.fail()!
        }
    }
    match images.second {
        ..none { [testing.fail()!] }
        ..some part {
            match [mapped_edge(&merged, .source_edge = part.value)!] {
                ..none {
                    testing.fail()!
                }
                ..some image {
                    edge ::= edge_info(&merged.model, .edge = image.value)!
                    match edge.second {
                        ..none {
                            testing.fail()!
                        }
                        ..some other {
                            a ::= halfedge_info(&merged.model, .halfedge = edge.first)!
                            b ::= halfedge_info(&merged.model, .halfedge = other.value)!
                            testing.expect(a.loop.value == 1 and b.loop.value == 1)!
                        }
                    }
                }
            }
        }
    }
    bottom ::= _walk_test_use(&merged.model, .loop = (.value = 0), .vertex = (.value = 0))!
    right ::= _walk_test_use(&merged.model, .loop = (.value = 0), .vertex = (.value = 1))!
    next ::= [
        split_planar_face(
            &merged.model
            .face  = (.value = 0)
            .start = (.halfedge = bottom, .parameter = 0.875)
            .end   = (.halfedge = right, .parameter = 0.5)
        )!
    ]
    after ::= entity_counts(&next.model)
    testing.expect(after.vertices == 12 and after.edges == 13 and after.faces == 2)!
    testing.expect(after.loops == 3 and after.halfedges == 15)!
}

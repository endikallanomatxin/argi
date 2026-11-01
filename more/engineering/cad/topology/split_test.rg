_split_square := () -> (.points: [4]g.Point#(Float64), .faces: [1][4]UIntNative) {
    points = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    faces = ((0, 1, 2, 3))
}

test model_split_diagonal := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.0)
            .end   = (.halfedge = (.value = 2), .parameter = 0.0)
        )!
    ]
    counts ::= entity_counts(&split.model)
    testing.expect(counts.vertices == 4 and counts.edges == 5 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 6)!
    [
        testing.expect([[loop_info(&split.model, .loop = (.value = 0))!].count == 3])!
    ]
    [
        testing.expect([[loop_info(&split.model, .loop = (.value = 1))!].count == 3])!
    ]
    [
        testing.expect(
            [
                [face_surface_id(&split.model, .face = (.value = 0))!]
                == [face_surface_id(&split.model, .face = (.value = 1))!]
            ]
        )!
    ]
    testing.expect(entity_counts(&source).faces == 1)!
    match [edge_info(&split.model, .edge = split.cut_edge)!].second {
        ..none { [testing.fail()!] }
        ..some _ {}
    }
    merged ::= [
        merge_coplanar_faces(&split.model, .first = split.faces[0], .second = split.faces[1])!
    ]
    [
        testing.expect(
            [
                entity_counts(&merged.model).edges == 4
                and entity_counts(&merged.model).faces == 1
            ]
        )!
    ]
}

test model_split_edge_interiors := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.25)
            .end   = (.halfedge = (.value = 2), .parameter = 0.75)
        )!
    ]
    counts ::= entity_counts(&split.model)
    [
        testing.expect(
            [
                counts.vertices == 6
                and counts.edges == 7
                and counts.faces == 2
                and counts.halfedges == 8
            ]
        )!
    ]
    [
        testing.expect([[point(&split.model, .vertex = split.cut_start)!].x == 0.5])!
    ]
    [
        testing.expect([point(&split.model, .vertex = split.cut_end)!].x == 0.5)!
    ]
    [
        testing.expect(
            [
                [[loop_info(&split.model, .loop = (.value = 0))!].count == 4]
                and [[loop_info(&split.model, .loop = (.value = 1))!].count == 4]
            ]
        )!
    ]
    a ::= [halfedge_info(&source, .halfedge = (.value = 0))!].edge
    b ::= [halfedge_info(&source, .halfedge = (.value = 2))!].edge
    match [split_edge_images(&split, .source_edge = a)!].second {
        ..none { [testing.fail()!] }
        ..some image {
            match [edge_curve(&split.model, .edge = a)!] {
                ..circle _ {
                    testing.fail()!
                }
                ..ellipse _ {
                    testing.fail()!
                }
                ..segment s {
                    testing.expect(s.end.x == 0.5 and s.end.y == 0.0)!
                }
            }
            match [edge_curve(&split.model, .edge = image.value)!] {
                ..circle _ {
                    testing.fail()!
                }
                ..ellipse _ {
                    testing.fail()!
                }
                ..segment s {
                    testing.expect(s.start.x == 0.5 and s.end.x == 2.0)!
                }
            }
        }
    }
    match [split_edge_images(&split, .source_edge = b)!].second {
        ..none { [testing.fail()!] }
        ..some _ {}
    }
    merged ::= [
        merge_coplanar_faces(&split.model, .first = split.faces[0], .second = split.faces[1])!
    ]
    [
        testing.expect(
            [
                entity_counts(&merged.model).vertices == 6
                and entity_counts(&merged.model).edges == 6
            ]
        )!
    ]
}

_split_cube := () -> (.points: [8]g.Point#(Float64), .faces: [6][4]UIntNative) {
    points = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 1.0),
        (1.0, 1.0, 1.0),
        (0.0, 1.0, 1.0)
    )
    faces = (
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7)
    )
}

test model_split_shared_edges_preserves_closed_shell := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_cube()
    source ::= [
        from_equal_length_faces(.points = view(&input.points), .faces = view(&input.faces))!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.5)
        )!
    ]
    counts ::= entity_counts(&split.model)
    testing.expect(counts.vertices == 10 and counts.edges == 15 and counts.faces == 7)!
    testing.expect(counts.halfedges == 30 and counts.loops == 7 and is_closed(&split.model).ok)!
    testing.expect(counts.vertices + counts.faces == counts.edges + 2)!
    paired :: UIntNative = 0
    i :: UIntNative = 0
    while i < counts.edges {
        id ::= i | convert#(.to: EdgeId)(_)
        edge ::= edge_info(&split.model, .edge = id)!
        match edge.second {
            ..none {
                testing.fail()!
            }
            ..some other {
                a ::= halfedge_info(&split.model, .halfedge = edge.first)!
                b ::= halfedge_info(&split.model, .halfedge = other.value)!
                testing.expect(a.reversed != b.reversed)!
                origin ::= halfedge_vertex(a)!
                opposite_next ::= halfedge_info(&split.model, .halfedge = b.next)!
                testing.expect(origin == [halfedge_vertex(opposite_next)!])!
                paired = paired + 1
            }
        }
        i = i + 1
    }
    testing.expect(paired == counts.edges)!
    -- The neighboring sides must use the very same inserted vertex IDs.
    [
        testing.expect(
            [
                [
                    loop_info(
                        &split.model, .loop = [face_loop(&split.model, .face = (.value = 3))!]
                    )!
                ].count
                == 5
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    loop_info(
                        &split.model, .loop = [face_loop(&split.model, .face = (.value = 5))!]
                    )!
                ].count
                == 5
            ]
        )!
    ]
    testing.expect(entity_counts(&source).vertices == 8 and entity_counts(&source).faces == 6)!
}

test model_split_rejects_invalid_endpoints := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 1)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 4), .parameter = 0.0)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_parameter
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = -0.1)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_parameter
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 1.1)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_cut
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 3), .parameter = 1.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_cut
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 1), .parameter = 0.0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_cut
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.2)
                .end   = (.halfedge = (.value = 0), .parameter = 0.8)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_cut
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.0000001)
                .end   = (.halfedge = (.value = 2), .parameter = 0.5)
            )
        )!
    ]
    testing.expect(entity_counts(&source).vertices == 4 and entity_counts(&source).edges == 4)!
}

test model_split_concave_and_exterior_chord := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    vertices: [6]UIntNative = (0, 1, 2, 3, 4, 5)
    lengths: [1]UIntNative = (6)
    loops: [1]UIntNative = (1)
    source ::= [
        from_planar_faces(
            .points           = view(&points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.0)
            .end   = (.halfedge = (.value = 3), .parameter = 0.0)
        )!
    ]
    [
        testing.expect(
            [entity_counts(&split.model).faces == 2 and entity_counts(&split.model).edges == 7]
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..cut_outside_face
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 2), .parameter = 0.0)
                .end   = (.halfedge = (.value = 4), .parameter = 0.0)
            )
        )!
    ]
}

test model_split_float32_reversed_endpoints := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [4]g.Point#(Float32) = (
        (0.0, 0.0, 1.0),
        (2.0, 0.0, 1.0),
        (2.0, 2.0, 1.0),
        (0.0, 2.0, 1.0)
    )
    faces: [1][4]UIntNative = ((0, 3, 2, 1))
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 2), .parameter = 0.5)
            .end   = (.halfedge = (.value = 0), .parameter = 0.5)
        )!
    ]
    [
        testing.expect(
            [
                entity_counts(&split.model).vertices == 6
                and [[face_plane(&split.model, .face = (.value = 0))!].normal.z == -1.0]
            ]
        )!
    ]
    [
        testing.expect([[point(&split.model, .vertex = split.cut_start)!].z == 1.0])!
    ]
}

test model_split_rejects_hole_endpoints_and_foreign_boundary := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    annulus ::= _planar_annulus()
    vertices: [8]UIntNative = (0, 1, 2, 3, 4, 5, 6, 7)
    lengths: [2]UIntNative = (4, 4)
    loops: [1]UIntNative = (2)
    source ::= [
        from_planar_faces(
            .points           = view(&annulus.points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..endpoint_not_on_boundary
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 4), .parameter = 0.0)
            )
        )!
    ]
    cube ::= _split_cube()
    closed ::= [
        from_equal_length_faces(.points = view(&cube.points), .faces = view(&cube.faces))!
    ]
    [
        testing.expect_error(
            .expected_reason = ..endpoint_not_on_boundary
            .actual_result   = split_planar_face(
                &closed
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 4), .parameter = 0.0)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
}

test model_split_history_checks_domains := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    face ::= idx.bind_index#(FaceId)(.domain = &source._domain, .offset = 0).value
    vertex ::= idx.bind_index#(VertexId)(.domain = &source._domain, .offset = 2).value
    old_edge ::= [halfedge_info(&source, .halfedge = (.value = 0))!].edge
    offset ::= old_edge | convert#(.to: UIntNative)(_)
    edge ::= idx.bind_index#(EdgeId)(.domain = &source._domain, .offset = offset).value
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.0)
        )!
    ]
    [
        testing.expect(
            [
                entity_counts(&split.model).vertices == 5
                and entity_counts(&split.model).edges == 6
            ]
        )!
    ]
    images ::= split_face_handle_images(&split, .face = face)!
    [
        testing.expect([[face_id(&split.model, .face = images.first)!].value == 0])!
    ]
    match images.second {
        ..none { [testing.fail()!] }
        ..some value {
            [
                testing.expect([[face_id(&split.model, .face = value.value)!].value == 1])!
            ]
        }
    }
    edge_images ::= split_edge_handle_images(&split, .edge = edge)!
    [
        testing.expect([[edge_id(&split.model, .edge = edge_images.first)!] == old_edge])!
    ]
    match edge_images.second {
        ..none { [testing.fail()!] }
        ..some value {
            [
                testing.expect([[edge_id(&split.model, .edge = value.value)!] != old_edge])!
            ]
        }
    }
    mapped ::= split_vertex_handle_image(&split, .vertex = vertex)!
    testing.expect([vertex_id(&split.model, .vertex = mapped)!].value == 2)!
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = vertex_id(&source, .vertex = mapped)
        )!
    ]
    foreign ::= idx.IndexDomain()!
    wrong_face ::= idx.bind_index#(FaceId)(.domain = &foreign, .offset = 0).value
    wrong_edge ::= idx.bind_index#(EdgeId)(.domain = &foreign, .offset = offset).value
    wrong_vertex ::= idx.bind_index#(VertexId)(.domain = &foreign, .offset = 2).value
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = split_face_handle_images(&split, .face = wrong_face)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = split_edge_handle_images(&split, .edge = wrong_edge)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = split_vertex_handle_image(&split, .vertex = wrong_vertex)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = split_face_images(&split, .source_face = (.value = 1))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = split_edge_images(&split, .source_edge = (.value = 4))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = split_vertex_image(&split, .source_vertex = (.value = 4))
        )!
    ]
}

_split_owned_patch := (.allocator: $&Virtual#(Allocator)) -> (
    .result : Errable#(Model#(Float64), SplitErrors)
) {
    input ::= _split_square()
    source ::= from_equal_length_faces(
        .points         = view(&input.points)
        .faces          = view(&input.faces)
        .require_closed = false
        .allocator      = allocator
    )!
    split ::= split_planar_face(
        &source
        .face      = (.value = 0)
        .start     = (.halfedge = (.value = 3), .parameter = 1.0)
        .end       = (.halfedge = (.value = 2), .parameter = 0.5)
        .allocator = allocator
    )!
    result = ..ok ~split.model
}

test model_split_result_owns_geometry := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    model ::= _split_owned_patch(.allocator = allocator)!
    testing.expect(entity_counts(&model).faces == 2 and entity_counts(&model).vertices == 5)!
    testing.expect([point(&model, .vertex = (.value = 4))!].x == 1.0)!
    [
        testing.expect([[face_plane(&model, .face = (.value = 1))!].normal.z == 1.0])!
    ]
}

test model_split_preserves_unrelated_analytic_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_

    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    frame ::= [
        g.frame(.origin = g.Point#(Float64)(0.0, 0.0, 5.0), .axis = (0.0, 0.0, 1.0))!
    ]
    circle: Curve#(Float64) = ..circle(.value = (.frame = frame, .radius = 2.0))
    curve ::= [
        _pool_add_curve(.pools = $&source._geometry, .curve = circle, .allocator = allocator)!
    ]
    disk: g.Surface#(Float64) = ..plane(
        .value = (.origin = frame.origin, .normal = frame.z)
    )
    support ::= [
        _pool_add_surface(.pools = $&source._geometry, .surface = disk, .allocator = allocator)!
    ]
    edge: Edge = (.first = (.value = 4), .second = ..none, .curve = ..some(.value = curve))
    use: HalfEdge = (
        .origin   = ..none
        .edge     = (.value = 4)
        .next     = (.value = 4)
        .loop     = (.value = 1)
        .reversed = true
    )
    loop: Loop = (.first = (.value = 4), .count = 1)
    face: Face = (.first_loop = (.value = 1), .loop_count = 1, .genus = 0)
    [push($&source._topology._edges, .value = edge, .allocator = allocator)!]
    [push($&source._topology._halfedges, .value = use, .allocator = allocator)!]
    [push($&source._topology._loops, .value = loop, .allocator = allocator)!]
    [push($&source._topology._faces, .value = face, .allocator = allocator)!]
    [push($&source._face_surfaces, .value = support, .allocator = allocator)!]
    sphere: g.Surface#(Float64) = ..sphere(.frame = frame, .radius = 1.0)
    sphere_support ::= [
        _pool_add_surface(
            .pools = $&source._geometry, .surface = sphere, .allocator = allocator
        )!
    ]
    sphere_face: Face = (.first_loop = (.value = 2), .loop_count = 0, .genus = 0)
    [push($&source._topology._faces, .value = sphere_face, .allocator = allocator)!]
    [push($&source._face_surfaces, .value = sphere_support, .allocator = allocator)!]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.5)
        )!
    ]
    testing.expect(entity_counts(&split.model).faces == 4)!
    disk_use ::= [
        loop_info(&split.model, .loop = [face_loop(&split.model, .face = (.value = 1))!])!
    ].first
    original ::= halfedge_point(&source, .halfedge = (.value = 4), .parameter = 0.25)!
    sample ::= halfedge_point(&split.model, .halfedge = disk_use, .parameter = 0.25)!
    [
        testing.expect(
            sample.x == original.x and sample.y == original.y and sample.z == original.z
        )!
    ]
    [
        testing.expect([[face_info(&split.model, .face = (.value = 2))!].loop_count == 0])!
    ]
    match [face_surface(&split.model, .face = (.value = 2))!] {
        ..sphere value { [testing.expect(value.radius == 1.0)!] }
        ..plane _ { [testing.fail()!] }
        ..cylinder _ { [testing.fail()!] }
        ..torus _ { [testing.fail()!] }
    }
    match [split_face_images(&split, .source_face = (.value = 1))!].second {
        ..none {}
        ..some _ { [testing.fail()!] }
    }
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 2)
                .start = (.halfedge = (.value = 0), .parameter = 0.0)
                .end   = (.halfedge = (.value = 2), .parameter = 0.0)
            )
        )!
    ]
}

test model_split_nonfirst_face_and_repeated_edit := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_cube()
    source ::= [
        from_equal_length_faces(.points = view(&input.points), .faces = view(&input.faces))!
    ]
    first ::= [
        split_planar_face(
            &source
            .face  = (.value = 4)
            .start = (.halfedge = (.value = 16), .parameter = 0.25)
            .end   = (.halfedge = (.value = 18), .parameter = 0.75)
        )!
    ]
    testing.expect(first.faces[0].value == 4 and first.faces[1].value == 6)!
    [
        testing.expect([[point(&first.model, .vertex = first.cut_start)!].x == 0.75])!
    ]
    [
        testing.expect([[point(&first.model, .vertex = first.cut_end)!].x == 0.75])!
    ]
    match [split_face_images(&first, .source_face = (.value = 0))!].second {
        ..none {}
        ..some _ { [testing.fail()!] }
    }
    boundary ::= [
        loop_info(&first.model, .loop = [face_loop(&first.model, .face = (.value = 1))!])!
    ]
    next ::= [halfedge_info(&first.model, .halfedge = boundary.first)!].next
    other ::= [halfedge_info(&first.model, .halfedge = next)!].next
    second ::= [
        split_planar_face(
            &first.model
            .face  = (.value = 1)
            .start = (.halfedge = boundary.first, .parameter = 0.0)
            .end   = (.halfedge = other, .parameter = 0.0)
        )!
    ]
    counts ::= entity_counts(&second.model)
    testing.expect(counts.vertices == 10 and counts.edges == 16 and counts.faces == 8)!
    [
        testing.expect(
            [is_closed(&second.model).ok and counts.vertices + counts.faces == counts.edges + 2]
        )!
    ]
}

test model_split_preserves_admitted_coordinates_and_support := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    input.points[3].z = 0.0000005
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    -- A support normal may oppose the topological winding.
    support ::= face_surface_id(&source, .face = (.value = 0))!
    reference ::= [
        get(&source._geometry.surfaces, .index = [[support | convert#(.to: UIntNative)(_)]])!
    ]
    plane ::= get_mutable_reference($&source._geometry.planes, .index = reference.index)!
    original ::= plane&
    plane&= g.Plane#(Float64)(
        .origin = original.origin
        .normal = (
            .x = 0.0 - original.normal.x
            .y = 0.0 - original.normal.y
            .z = [0.0 - original.normal.z]
        )
    )
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.5)
        )!
    ]
    [
        testing.expect([[point(&split.model, .vertex = (.value = 3))!].z == input.points[3].z])!
    ]
    [
        testing.expect([[point(&split.model, .vertex = split.cut_end)!].z == 0.00000025])!
    ]
    testing.expect(validation_tolerance(&split.model) == validation_tolerance(&source))!
    [
        testing.expect([[face_surface_id(&split.model, .face = split.faces[0])!] == support])!
    ]
    [
        testing.expect([[face_surface_id(&split.model, .face = split.faces[1])!] == support])!
    ]
}

test model_split_cut_direction_and_nonfinite_parameter := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_square()
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&input.faces), .require_closed = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.5)
        )!
    ]
    start ::= point(&split.model, .vertex = split.cut_start)!
    end ::= point(&split.model, .vertex = split.cut_end)!
    match [edge_curve(&split.model, .edge = split.cut_edge)!] {
        ..circle _ { [testing.fail()!] }
        ..ellipse _ { [testing.fail()!] }
        ..segment segment {
            testing.expect(segment.start.x == start.x and segment.start.y == start.y)!
            testing.expect(segment.end.x == end.x and segment.end.y == end.y)!
        }
    }
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .expected_reason = ..invalid_parameter
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = nan)
                .end   = (.halfedge = (.value = 2), .parameter = 0.5)
            )
        )!
    ]
}

test model_split_respects_halfedge_parameter_direction := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _split_cube()
    source ::= [
        from_equal_length_faces(.points = view(&input.points), .faces = view(&input.faces))!
    ]
    index :: UIntNative = 0
    use ::= halfedge_info(&source, .halfedge = (.value = 0))!
    while use.reversed == false {
        index = index + 1
        id ::= index | convert#(.to: HalfEdgeId)(_)
        use = [halfedge_info(&source, .halfedge = id)!]
    }
    first ::= index | convert#(.to: HalfEdgeId)(_)
    next ::= halfedge_info(&source, .halfedge = use.next)!
    -- This fixture's six source faces have exactly one loop each.
    face_index ::= use.loop | convert#(.to: UIntNative)(_)
    face ::= face_index | convert#(.to: FaceId)(_)
    a ::= point(&source, .vertex = [halfedge_vertex(use)!])!
    b ::= point(&source, .vertex = [halfedge_vertex(next)!])!
    split ::= [
        split_planar_face(
            &source
            .face  = face
            .start = (.halfedge = first, .parameter = 0.25)
            .end   = (.halfedge = next.next, .parameter = 0.75)
        )!
    ]
    inserted ::= point(&split.model, .vertex = split.cut_start)!
    testing.expect(inserted.x == 0.75 * a.x + 0.25 * b.x)!
    testing.expect(inserted.y == 0.75 * a.y + 0.25 * b.y)!
    testing.expect(inserted.z == 0.75 * a.z + 0.25 * b.z)!
    match [split_edge_images(&split, .source_edge = use.edge)!].second {
        ..none { [testing.fail()!] }
        ..some second {
            match [edge_curve(&split.model, .edge = use.edge)!] {
                ..circle _ {
                    testing.fail()!
                }
                ..ellipse _ {
                    testing.fail()!
                }
                ..segment segment {
                    [
                        testing.expect(
                            [
                                segment.end.x == inserted.x
                                and segment.end.y == inserted.y
                                and segment.end.z == inserted.z
                            ]
                        )!
                    ]
                }
            }
            match [edge_curve(&split.model, .edge = second.value)!] {
                ..circle _ {
                    testing.fail()!
                }
                ..ellipse _ {
                    testing.fail()!
                }
                ..segment segment {
                    [
                        testing.expect(
                            [
                                segment.start.x == inserted.x
                                and segment.start.y == inserted.y
                                and segment.start.z == inserted.z
                            ]
                        )!
                    ]
                }
            }
        }
    }
}

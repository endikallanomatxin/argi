test model_merge_two_triangles := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 4 and counts.edges == 4 and counts.faces == 1)!
    testing.expect(counts.halfedges == 4 and counts.loops == 1)!
    testing.expect(entity_counts(&source).faces == 2)!
    [
        testing.expect(
            [
                [mapped_face(&merged, .source_face = (.value = 0))!]
                == [mapped_face(&merged, .source_face = (.value = 1))!]
            ]
        )!
    ]
    [
        testing.expect([[loop_info(&merged.model, .loop = (.value = 0))!].count == 4])!
    ]
}

test model_merge_concave_boundary := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [6]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    faces: [2][4]UIntNative = (
        (0, 1, 2, 3),
        (0, 3, 4, 5)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 1), .second = (.value = 0))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 6 and counts.edges == 6 and counts.faces == 1)!
    [
        testing.expect([[loop_info(&merged.model, .loop = (.value = 0))!].count == 6])!
    ]
    [
        testing.expect(
            [
                [[mapped_face(&merged, .source_face = (.value = 0))!].value == 0]
                and [[mapped_face(&merged, .source_face = (.value = 1))!].value == 0]
            ]
        )!
    ]
}

test model_merge_preserves_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    original ::= _planar_annulus()
    points: [10]g.Point#(Float64) = (
        original.points[0],
        original.points[1],
        original.points[2],
        original.points[3],
        original.points[4],
        original.points[5],
        original.points[6],
        original.points[7],
        (6.0, 0.0, 0.0),
        (6.0, 4.0, 0.0)
    )
    vertices: [12]UIntNative = (0, 1, 2, 3, 4, 5, 6, 7, 1, 8, 9, 2)
    lengths: [3]UIntNative = (4, 4, 4)
    loops: [2]UIntNative = (2, 1)
    source ::= [
        from_planar_faces(
            .points           = view(&points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.faces == 1 and counts.loops == 2 and counts.edges == 10)!
    [
        testing.expect([[face_info(&merged.model, .face = (.value = 0))!].loop_count == 2])!
    ]
    [
        testing.expect(
            [
                [[loop_info(&merged.model, .loop = (.value = 0))!].count == 6]
                and [[loop_info(&merged.model, .loop = (.value = 1))!].count == 4]
            ]
        )!
    ]
}

test model_merge_fills_hole_and_removes_vertices := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    original ::= _planar_annulus()
    vertices: [12]UIntNative = (0, 1, 2, 3, 4, 5, 6, 7, 4, 7, 6, 5)
    lengths: [3]UIntNative = (4, 4, 4)
    loops: [2]UIntNative = (2, 1)
    source ::= [
        from_planar_faces(
            .points           = view(&original.points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    [
        testing.expect(
            [
                counts.faces == 1
                and counts.vertices == 4
                and counts.edges == 4
                and counts.loops == 1
            ]
        )!
    ]
    match [mapped_vertex(&merged, .source_vertex = (.value = 4))!] {
        ..none {}
        ..some _ {
            testing.fail()!
        }
    }
    removed :: UIntNative = 0
    e :: UIntNative = 0
    while e < entity_counts(&source).edges {
        id ::= e | convert#(.to: EdgeId)(_)
        match [mapped_edge(&merged, .source_edge = id)!] {
            ..none {
                removed = removed + 1
                handle ::= idx.bind_index#(EdgeId)(.domain = &source._domain, .offset = e).value
                match [mapped_edge_handle(&merged, .edge = handle)!] {
                    ..none {}
                    ..some _ {
                        testing.fail()!
                    }
                }
            }
            ..some _ {}
        }
        e = e + 1
    }
    testing.expect(removed == 4)!
}

test model_merge_rejects_same_or_invalid_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    input ::= _triangle()
    faces: [1][3]UIntNative = ((0, 1, 2))
    source ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&faces), .require_closed = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..same_face
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 0)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 1)
            )
        )!
    ]
}

test model_merge_rejects_nonadjacent_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (3, 4, 5)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..not_adjacent
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 1)
            )
        )!
    ]
}

test model_merge_closed_cube_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [8]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 1.0),
        (1.0, 1.0, 1.0),
        (0.0, 1.0, 1.0)
    )
    vertices: [26]UIntNative = (
        0,
        3,
        2,
        0,
        2,
        1,
        4,
        5,
        6,
        7,
        0,
        1,
        5,
        4,
        1,
        2,
        6,
        5,
        2,
        3,
        7,
        6,
        3,
        0,
        4,
        7
    )
    lengths: [7]UIntNative = (3, 3, 4, 4, 4, 4, 4)
    source ::= [
        from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&vertices)
            .face_lengths   = view(&lengths)
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    [
        testing.expect(
            [
                counts.faces == 6
                and counts.edges == 12
                and counts.vertices == 8
                and counts.halfedges == 24
            ]
        )!
    ]
    testing.expect(is_closed(&merged.model).ok)!
    e :: UIntNative = 0
    while e < counts.edges {
        edge ::= e | convert#(.to: EdgeId)(_)
        match [edge_info(&merged.model, .edge = edge)!].second {
            ..none { [testing.fail()!] }
            ..some _ {}
        }
        e = e + 1
    }
    [
        testing.expect_error(
            .expected_reason = ..not_coplanar
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 2)
            )
        )!
    ]
}

_merge_owned_patch := (.allocator: Virtual#(Allocator)) -> (
    .result : Errable#(Model#(Float64), MergeErrors)
) {
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= from_equal_length_faces(
        .points         = view(&points)
        .faces          = view(&faces)
        .require_closed = false
        .allocator      = allocator
    )!
    merged ::= merge_coplanar_faces(
        &source, .first = (.value = 0), .second = (.value = 1), .allocator = allocator
    )!
    result = ..ok ~merged.model
}

test model_merge_result_owns_geometry := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _merge_owned_patch(.allocator = allocator)!
    testing.expect(entity_counts(&model).faces == 1)!
    testing.expect([point(&model, .vertex = (.value = 2))!].x == 1.0)!
    [
        testing.expect([[face_plane(&model, .face = (.value = 0))!].normal.z == 1.0])!
    ]
}

test model_merge_preserves_unrelated_analytic_geometry := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)

    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    polygons: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&polygons), .require_closed = false
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
    disk_support ::= [
        _pool_add_surface(.pools = $&source._geometry, .surface = disk, .allocator = allocator)!
    ]
    disk_edge: Edge = (
        .first  = (.value = 6)
        .second = ..none
        .curve  = ..some(.value = curve)
    )
    disk_use: HalfEdge = (
        .origin   = ..none
        .edge     = (.value = 5)
        .next     = (.value = 6)
        .loop     = (.value = 2)
        .reversed = true
    )
    disk_loop: Loop = (.first = (.value = 6), .count = 1)
    disk_face: Face = (.first_loop = (.value = 2), .loop_count = 1, .genus = 0)
    [push($&source._topology._edges, .value = disk_edge, .allocator = allocator)!]
    [push($&source._topology._halfedges, .value = disk_use, .allocator = allocator)!]
    [push($&source._topology._loops, .value = disk_loop, .allocator = allocator)!]
    [push($&source._topology._faces, .value = disk_face, .allocator = allocator)!]
    [push($&source._face_surfaces, .value = disk_support, .allocator = allocator)!]
    sphere: g.Surface#(Float64) = ..sphere(.frame = frame, .radius = 1.0)
    sphere_support ::= [
        _pool_add_surface(
            .pools = $&source._geometry, .surface = sphere, .allocator = allocator
        )!
    ]
    sphere_face: Face = (.first_loop = (.value = 3), .loop_count = 0, .genus = 0)
    [push($&source._topology._faces, .value = sphere_face, .allocator = allocator)!]
    [push($&source._face_surfaces, .value = sphere_support, .allocator = allocator)!]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    testing.expect(entity_counts(&merged.model).faces == 3)!
    disk_id ::= mapped_face(&merged, .source_face = (.value = 2))!
    [
        testing.expect([[face_info(&merged.model, .face = disk_id)!].loop_count == 1])!
    ]
    boundary ::= face_loop(&merged.model, .face = disk_id)!
    use ::= [loop_info(&merged.model, .loop = boundary)!].first
    sample ::= halfedge_point(&merged.model, .halfedge = use, .parameter = 0.25)!
    original_sample ::= halfedge_point(&source, .halfedge = (.value = 6), .parameter = 0.25)!
    [
        testing.expect(
            [
                sample.x == original_sample.x
                and sample.y == original_sample.y
                and sample.z == 5.0
            ]
        )!
    ]
    sphere_id ::= mapped_face(&merged, .source_face = (.value = 3))!
    [
        testing.expect([[face_info(&merged.model, .face = sphere_id)!].loop_count == 0])!
    ]
    match [face_surface(&merged.model, .face = sphere_id)!] {
        ..sphere s {
            testing.expect(s.radius == 1.0 and s.frame.origin.z == 5.0)!
        }
        ..plane _ { [testing.fail()!] }
        ..cylinder _ {
            testing.fail()!
        }
        ..torus _ { [testing.fail()!] }
    }
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 3)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..unsupported_boundary
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 2)
            )
        )!
    ]
}

test model_merge_handle_history_checks_domains := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    original ::= idx.bind_index#(VertexId)(.domain = &source._domain, .offset = 2).value
    face ::= idx.bind_index#(FaceId)(.domain = &source._domain, .offset = 1).value
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    match [mapped_vertex_handle(&merged, .vertex = original)!] {
        ..none { [testing.fail()!] }
        ..some mapped {
            [
                testing.expect([[vertex_id(&merged.model, .vertex = mapped.value)!].value == 2])!
            ]
            [
                testing.expect_error(
                    .expected_reason = ..wrong_domain
                    .actual_result   = vertex_id(&source, .vertex = mapped.value)
                )!
            ]
        }
    }
    new_face ::= mapped_face_handle(&merged, .face = face)!
    testing.expect([face_id(&merged.model, .face = new_face)!].value == 0)!
    foreign ::= idx.IndexDomain()!
    wrong ::= idx.bind_index#(VertexId)(.domain = &foreign, .offset = 2).value
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = mapped_vertex_handle(&merged, .vertex = wrong)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = mapped_face(&merged, .source_face = (.value = 7))
        )!
    ]
}

test model_merge_creates_hole_from_two_exteriors := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    original ::= _planar_annulus()
    vertices: [12]UIntNative = (0, 1, 7, 4, 5, 6, 2, 3, 1, 2, 6, 7)
    lengths: [2]UIntNative = (8, 4)
    loops: [2]UIntNative = (1, 1)
    source ::= [
        from_planar_faces(
            .points           = view(&original.points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    [
        testing.expect(
            [
                counts.vertices == 8
                and counts.edges == 8
                and counts.faces == 1
                and counts.loops == 2
            ]
        )!
    ]
    [
        testing.expect(
            [
                [[loop_info(&merged.model, .loop = (.value = 0))!].count == 4]
                and [[loop_info(&merged.model, .loop = (.value = 1))!].count == 4]
            ]
        )!
    ]
}

test model_merge_removes_shared_chain_vertex := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.0),
        (0.0, 2.0, 0.0),
        (1.0, 1.0, 0.0)
    )
    vertices: [8]UIntNative = (0, 1, 4, 0, 4, 1, 2, 3)
    lengths: [2]UIntNative = (3, 5)
    loops: [2]UIntNative = (1, 1)
    source ::= [
        from_planar_faces(
            .points           = view(&points)
            .vertex_indices   = view(&vertices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    counts ::= entity_counts(&merged.model)
    testing.expect(counts.vertices == 4 and counts.edges == 4 and counts.faces == 1)!
    match [mapped_vertex(&merged, .source_vertex = (.value = 4))!] {
        ..none {}
        ..some _ { [testing.fail()!] }
    }
}

test model_merge_rejects_oppositely_oriented_sheets := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    input ::= _triangle()
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (2, 1, 0)
    )
    source ::= from_equal_length_faces(.points = view(&input.points), .faces = view(&faces))!
    [
        testing.expect_error(
            .expected_reason = ..inconsistent_orientation
            .actual_result   = merge_coplanar_faces(
                &source, .first = (.value = 0), .second = (.value = 1)
            )
        )!
    ]
}

test model_merge_preserves_coordinates_within_tolerance := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points :: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0000005)
    )
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    merged ::= merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    [
        testing.expect([[point(&merged.model, .vertex = (.value = 3))!].z == points[3].z])!
    ]
    testing.expect(validation_tolerance(&merged.model) == validation_tolerance(&source))!
    points[3].z = 0.000004
    tilted ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..not_coplanar
            .actual_result   = merge_coplanar_faces(
                &tilted, .first = (.value = 0), .second = (.value = 1)
            )
        )!
    ]
}

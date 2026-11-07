test model_builder_explicit_shared_edges := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder#(Float64)()!
    a ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= builder | add_vertex($&_, (1.0, 0.0, 0.0))!
    c ::= builder | add_vertex($&_, (1.0, 1.0, 0.0))!
    d ::= builder | add_vertex($&_, (0.0, 1.0, 0.0))!
    ab ::= builder | add_edge($&_, a, b)!
    bc ::= builder | add_edge($&_, b, c)!
    ca ::= builder | add_edge($&_, c, a)!
    cd ::= builder | add_edge($&_, c, d)!
    da ::= builder | add_edge($&_, d, a)!
    plane: g.Surface#(Float64) = ..plane(
        .value = (
            .origin = (0.0, 0.0, 0.0)
            .normal = (0.0, 0.0, 1.0)
        )
    )
    support ::= builder | add_surface($&_, .surface = plane)!
    first :: [3]EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
    second :: [3]EdgeUse = ((.edge = ca, .reversed = true), (.edge = cd), (.edge = da))
    f0 ::= builder | add_face($&_, .surface = support, .boundary = view(&first))!
    f1 ::= builder | add_face($&_, .surface = support, .boundary = view(&second))!
    model ::= builder | finish_model(~_, .require_closed = false)!
    testing.expect(entity_counts(&model).vertices == 4 and entity_counts(&model).edges == 5)!
    [
        testing.expect(
            [
                [face_surface_id(&model, .face = (.value = 0))!]
                == [face_surface_id(&model, .face = (.value = 1))!]
            ]
        )!
    ]
    testing.expect([vertex_id(&model, .vertex = a)!].value == 0)!
    testing.expect([edge_id(&model, .edge = ca)!].value == 2)!
    [
        testing.expect(
            [
                [face_id(&model, .face = f0)!].value == 0
                and [face_id(&model, .face = f1)!].value == 1
            ]
        )!
    ]
    storage ::= geometry_storage_info(&model)
    testing.expect(storage.surfaces == 1 and storage.planes == 1 and storage.curves == 0)!
    testing.expect(storage.payload_bytes < 2 * _pool_type_size#(g.Surface#(Float64))())!
    curve ::= edge_curve(&model, .edge = (.value = 2))!
    start ::= curve_point(.curve = curve, .parameter = 0.0)!
    end ::= curve_point(.curve = curve, .parameter = 1.0)!
    testing.expect(start.x == 1.0 and start.y == 1.0 and end.x == 0.0 and end.y == 0.0)!
}

_builder_plane := () -> (.surface: g.Surface#(Float64)) {
    surface = ..plane(
        .value = (
            .origin = (0.0, 0.0, 0.0)
            .normal = (0.0, 0.0, 1.0)
        )
    )
}

test model_builder_rejects_foreign_handles := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    first ::= ModelBuilder#(Float64)()!
    second ::= ModelBuilder#(Float64)()!
    a ::= first | add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= second | add_vertex($&_, (1.0, 0.0, 0.0))!
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain, .actual_result = [second | add_edge($&_, a, b)]
        )!
    ]
    support ::= first | add_surface($&_, .surface = _builder_plane().surface)!
    c ::= second | add_vertex($&_, (0.0, 1.0, 0.0))!
    edge ::= second | add_edge($&_, b, c)!
    boundary: [3]EdgeUse = ((.edge = edge), (.edge = edge), (.edge = edge))
    [
        testing.expect_error(
            .expected_reason = ..wrong_domain
            .actual_result   = [
                second
                | add_face($&_, .surface = support, .boundary = view(&boundary))
            ]
        )!
    ]
}

test model_builder_rejects_disconnected_boundary := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder#(Float64)()!
    a ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= builder | add_vertex($&_, (1.0, 0.0, 0.0))!
    c ::= builder | add_vertex($&_, (0.0, 1.0, 0.0))!
    ab ::= builder | add_edge($&_, a, b)!
    bc ::= builder | add_edge($&_, b, c)!
    ca ::= builder | add_edge($&_, c, a)!
    support ::= builder | add_surface($&_, .surface = _builder_plane().surface)!
    boundary: [3]EdgeUse = ((.edge = ab), (.edge = ca), (.edge = bc))
    builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = [builder | finish_model(~_, .require_closed = false)]
        )!
    ]
}

test model_builder_rejects_unrelated_support := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder#(Float64)()!
    a ::= builder | add_vertex($&_, (0.0, 0.0, 1.0))!
    b ::= builder | add_vertex($&_, (1.0, 0.0, 1.0))!
    c ::= builder | add_vertex($&_, (0.0, 1.0, 1.0))!
    ab ::= builder | add_edge($&_, a, b)!
    bc ::= builder | add_edge($&_, b, c)!
    ca ::= builder | add_edge($&_, c, a)!
    support ::= builder | add_surface($&_, .surface = _builder_plane().surface)!
    boundary: [3]EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
    builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = [builder | finish_model(~_, .require_closed = false)]
        )!
    ]
}

test model_builder_preserves_explicit_coincident_vertices := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder#(Float64)()!
    support ::= builder | add_surface($&_, .surface = _builder_plane().surface)!
    i :: UIntNative = 0
    while i < 2 {
        a ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
        b ::= builder | add_vertex($&_, (1.0, 0.0, 0.0))!
        c ::= builder | add_vertex($&_, (0.0, 1.0, 0.0))!
        ab ::= builder | add_edge($&_, a, b)!
        bc ::= builder | add_edge($&_, b, c)!
        ca ::= builder | add_edge($&_, c, a)!
        boundary: [3]EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
        builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
        i = i + 1
    }
    model ::= builder | finish_model(~_, .require_closed = false)!
    counts ::= entity_counts(&model)
    testing.expect(counts.vertices == 6 and counts.edges == 6 and counts.faces == 2)!
    testing.expect(geometry_storage_info(&model).surfaces == 1)!
}

test model_builder_requires_closed := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder#(Float64)()!
    a ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= builder | add_vertex($&_, (1.0, 0.0, 0.0))!
    c ::= builder | add_vertex($&_, (0.0, 1.0, 0.0))!
    ab ::= builder | add_edge($&_, a, b)!
    bc ::= builder | add_edge($&_, b, c)!
    ca ::= builder | add_edge($&_, c, a)!
    support ::= builder | add_surface($&_, .surface = _builder_plane().surface)!
    boundary: [3]EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
    builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
    [
        testing.expect_error(
            .expected_reason = ..open_boundary
            .actual_result   = [builder | finish_model(~_, .require_closed = true)]
        )!
    ]
}

test model_builder_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder()!
    a ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= builder | add_vertex($&_, (1.0, 0.0, 0.0))!
    c ::= builder | add_vertex($&_, (0.0, 1.0, 0.0))!
    ab ::= builder | add_edge($&_, a, b)!
    bc ::= builder | add_edge($&_, b, c)!
    ca ::= builder | add_edge($&_, c, a)!
    plane: g.Surface#(Float32) = ..plane(
        .value = (
            .origin = (0.0, 0.0, 0.0)
            .normal = (0.0, 0.0, 1.0)
        )
    )
    support ::= builder | add_surface($&_, .surface = plane)!
    boundary: [3]EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
    face ::= builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
    model ::= builder | finish_model(~_, .require_closed = false)!
    testing.expect([face_id(&model, .face = face)!].value == 0)!
    [
        testing.expect([[point(&model, .vertex = [vertex_id(&model, .vertex = b)!])!].x == 1.0])!
    ]
}

test model_builder_closed_tetrahedron := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0)
    )
    faces: [4][3]UIntNative = (
        (0, 2, 1),
        (0, 1, 3),
        (1, 2, 3),
        (2, 0, 3)
    )
    reference ::= from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
    builder ::= ModelBuilder#(Float64)()!
    a ::= builder | add_vertex($&_, points[0])!
    b ::= builder | add_vertex($&_, points[1])!
    c ::= builder | add_vertex($&_, points[2])!
    d ::= builder | add_vertex($&_, points[3])!
    ab ::= builder | add_edge($&_, a, b)!
    ac ::= builder | add_edge($&_, a, c)!
    ad ::= builder | add_edge($&_, a, d)!
    bc ::= builder | add_edge($&_, b, c)!
    bd ::= builder | add_edge($&_, b, d)!
    cd ::= builder | add_edge($&_, c, d)!
    boundaries: [4][3]EdgeUse = (
        ((.edge = ac), (.edge = bc, .reversed = true), (.edge = ab, .reversed = true)),
        ((.edge = ab), (.edge = bd), (.edge = ad, .reversed = true)),
        ((.edge = bc), (.edge = cd), (.edge = bd, .reversed = true)),
        ((.edge = ac, .reversed = true), (.edge = ad), (.edge = cd, .reversed = true))
    )
    f :: UIntNative = 0
    while f < 4 {
        face ::= f | convert#(.to: FaceId)(_)
        support ::= [
            [builder | add_surface($&_, .surface = [face_surface(&reference, .face = face)!])]!
        ]
        boundary ::= boundaries[f]
        builder | add_face($&_, .surface = support, .boundary = view(&boundary))!
        f = f + 1
    }
    model ::= builder | finish_model(~_)!
    counts ::= entity_counts(&model)
    testing.expect(is_closed(&model).ok and counts.edges == 6 and counts.faces == 4)!
    edge ::= edge_id(&model, .edge = ab)!
    curve ::= edge_curve(&model, .edge = edge)!
    start ::= curve_point(.curve = curve, .parameter = 0.0)!
    end ::= curve_point(.curve = curve, .parameter = 1.0)!
    testing.expect(start.x == 0.0 and end.x == 1.0)!
}

test model_builder_defaults_to_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= ModelBuilder()!
    vertex ::= builder | add_vertex($&_, (0.0, 0.0, 0.0))!
    point: g.Point#(Float32) = get(&builder._points, .index = 0)!
    testing.expect(point.x == 0.0)!
    match ModelBuilder(.tolerance = -1.0) {
        ..ok ~value { testing.fail()! }
        ..error error { testing.expect(error.reason == ..invalid_tolerance)! }
    }
}

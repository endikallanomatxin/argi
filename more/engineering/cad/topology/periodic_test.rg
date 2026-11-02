_PeriodicTestErrors := (
    ..wrong_domain,
    ..unused_edge,
    ..invalid_tolerance,
    ..invalid_surface,
    ..invalid_coordinate,
    ..degenerate_face,
    ..nonplanar_face,
    ..nonconvex_face,
    ..numeric_range,
    ..numerical_ambiguity,
    ..out_of_bounds,
    ..invalid_region_lengths,
    ..intersecting_contours,
    ..invalid_region_nesting,
    ..inconsistent_orientation,
    ..test_failed,
    ..out_of_memory
)

_periodic_frame := #(.Scalar: Type: Float) () -> (.value: g.Frame#(Scalar)) {
    value = unwrap_or_abort(
        .value = g.frame#(Scalar)(.origin = (2.0, -3.0, 4.0), .axis = (0.0, 0.0, 5.0))
    ).result
}

_check_periodic_closed := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .i: UIntNative) -> !Void {

    counts ::= entity_counts#(Scalar)(model)
    testing.expect(counts.vertices == 0 and counts.edges == 0 and counts.halfedges == 0)!
    testing.expect(counts.loops == 0 and counts.faces == 1 and is_closed#(Scalar)(model).ok)!
    face ::= face_info#(Scalar)(model, .face = (.value = 0))!
    testing.expect(face.loop_count == 0 and face.genus == i)!
    visited :: UIntNative = 0
    for entry in [face_loops#(Scalar)(model, .face = (.value = 0))!] {
        visited = [visited + 1]
    }
    testing.expect(visited == 0)!
    actual ::= face_surface#(Scalar)(model, .face = (.value = 0))!
    periods ::= g.surface_periodicity#(Scalar)(actual)
    testing.expect(periods.u and periods.v == [i == 1])!
    a ::= g.surface_point#(Scalar)(.surface = actual, .u = 0.0, .v = 0.0)!
    b ::= g.surface_point#(Scalar)(.surface = actual, .u = 6.283185307179586, .v = 0.0)!
    [
        testing.expect(
            [g.norm#(Scalar)(g.between#(Scalar)(.from = a, .to = b).result).value < 0.00001]
        )!
    ]
    if i == 1 {
        c ::= [
            g.surface_point#(Scalar)(.surface = actual, .u = 0.0, .v = 6.283185307179586)!
        ]
        [
            testing.expect(
                [g.norm#(Scalar)(g.between#(Scalar)(.from = a, .to = c).result).value < 0.00001]
            )!
        ]
    }
    result = ..ok Void()
}

test model_periodic_closed_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float32)().value
    sphere: g.Surface#(Float32) = ..sphere(.frame = basis, .radius = 2.0)
    torus: g.Surface#(Float32) = ..torus(
        .frame        = basis
        .major_radius = 3.0
        .minor_radius = 1.0
    )
    ball ::= from_periodic_surface(.surface = sphere)!
    ring ::= from_periodic_surface(.surface = torus)!
    [_check_periodic_closed(.model = &ball, .i = 0)!]
    [_check_periodic_closed(.model = &ring, .i = 1)!]
}

test model_periodic_closed_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float64)().value
    sphere: g.Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    torus: g.Surface#(Float64) = ..torus(
        .frame        = basis
        .major_radius = 3.0
        .minor_radius = 1.0
    )
    ball ::= from_periodic_surface(.surface = sphere)!
    ring ::= from_periodic_surface(.surface = torus)!
    [_check_periodic_closed(.model = &ball, .i = 0)!]
    [_check_periodic_closed(.model = &ring, .i = 1)!]
}

_check_periodic_cylinder := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .capped: Bool) -> !Void {

    counts ::= entity_counts#(Scalar)(model)
    testing.expect(counts.vertices == 0 and counts.edges == 2)!
    testing.expect(is_closed#(Scalar)(model).ok == capped)!
    [
        testing.expect([[face_info#(Scalar)(model, .face = (.value = 0))!].loop_count == 2])!
    ]
    if capped {
        testing.expect(counts.faces == 3 and counts.loops == 4 and counts.halfedges == 4)!
        [
            testing.expect(
                [[face_plane#(Scalar)(model, .face = (.value = 1))!].normal.z == -1.0]
            )!
        ]
        [
            testing.expect(
                [[face_plane#(Scalar)(model, .face = (.value = 2))!].normal.z == 1.0]
            )!
        ]
    } else {
        testing.expect(counts.faces == 1 and counts.loops == 2 and counts.halfedges == 2)!
    }
    boundaries :: UIntNative = 0
    for entry in [face_loops#(Scalar)(model, .face = (.value = 0))!] {
        testing.expect(entry.loop.count == 1)!
        boundaries = boundaries + 1
    }
    testing.expect(boundaries == 2)!
    i :: UIntNative = 0
    while i < counts.loops {
        loop_id ::= i | convert#(.to: LoopId)(_)
        boundary ::= loop_info#(Scalar)(model, .loop = loop_id)!
        testing.expect(boundary.count == 1)!
        visited :: UIntNative = 0
        for entry in [loop_halfedges#(Scalar)(model, .loop = loop_id)!] {
            testing.expect(entry.halfedge.next == entry.id and entry.halfedge.loop == loop_id)!
            match entry.halfedge.origin {
                ..none {}
                ..some _ {
                    testing.fail()!
                }
            }
            match [edge_curve#(Scalar)(model, .edge = entry.halfedge.edge)!] {
                ..ellipse _ {
                    testing.fail()!
                }
                ..segment _ {
                    testing.fail()!
                }
                ..circle curve {
                    a ::= g.circle_point#(Scalar)(.circle = curve.value, .angle = 0.0)!
                    b ::= [
                        g.circle_point#(Scalar)(
                            .circle = curve.value, .angle = 6.283185307179586
                        )!
                    ]
                    [
                        testing.expect(
                            [
                                g.norm#(Scalar)(
                                    g.between#(Scalar)(.from = a, .to = b).result
                                ).value
                                < 0.00001
                            ]
                        )!
                    ]
                    expected :: Scalar = 4.0
                    if i % 2 == 1 { expected = 7.0 }
                    testing.expect(a.z == expected)!
                }
            }
            match [opposite#(Scalar)(model, .halfedge = entry.id)!] {
                ..none { [testing.expect(capped == false)!] }
                ..some mate {
                    testing.expect(capped)!
                    other ::= halfedge_info#(Scalar)(model, .halfedge = mate.value)!
                    [
                        testing.expect(
                            [
                                other.edge == entry.halfedge.edge
                                and other.reversed != entry.halfedge.reversed
                            ]
                        )!
                    ]
                    a ::= [
                        halfedge_point#(Scalar)(model, .halfedge = entry.id, .parameter = 0.25)!
                    ]
                    b ::= [
                        halfedge_point#(Scalar)(
                            model, .halfedge = mate.value, .parameter = 0.75
                        )!
                    ]
                    [
                        testing.expect(
                            [
                                g.norm#(Scalar)(
                                    g.between#(Scalar)(.from = a, .to = b).result
                                ).value
                                < 0.00001
                            ]
                        )!
                    ]
                    match [opposite#(Scalar)(model, .halfedge = mate.value)!] {
                        ..none {
                            testing.fail()!
                        }
                        ..some back {
                            testing.expect(back.value == entry.id)!
                        }
                    }
                }
            }
            visited = visited + 1
        }
        testing.expect(visited == 1)!
        i = i + 1
    }
    result = ..ok Void()
}

test model_periodic_cylinders_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float32)().value
    support: g.Surface#(Float32) = ..cylinder(
        .frame  = basis
        .radius = 2.0
    )
    open ::= from_periodic_surface(.surface = support, .height = 3.0)!
    closed ::= from_periodic_surface(.surface = support, .cap_cylinder = true, .height = 3.0)!
    [_check_periodic_cylinder(.model = &open, .capped = false)!]
    [_check_periodic_cylinder(.model = &closed, .capped = true)!]
}

test model_periodic_cylinders_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float64)().value
    support: g.Surface#(Float64) = ..cylinder(
        .frame  = basis
        .radius = 2.0
    )
    open ::= from_periodic_surface(.surface = support, .height = 3.0)!
    closed ::= from_periodic_surface(.surface = support, .cap_cylinder = true, .height = 3.0)!
    [_check_periodic_cylinder(.model = &open, .capped = false)!]
    [_check_periodic_cylinder(.model = &closed, .capped = true)!]
}

test model_periodic_rejects_invalid_supports := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float64)().value
    support :: g.Surface#(Float64) = ..sphere(.frame = basis, .radius = 0.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
    support = ..torus(.frame = basis, .major_radius = 1.0, .minor_radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
    support = ..cylinder(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = from_periodic_surface(.surface = support, .height = -1.0)
        )!
    ]
    support = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_tolerance
            .actual_result   = from_periodic_surface(.surface = support, .tolerance = 0.0)
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = from_periodic_surface(
                .surface = support, .cap_cylinder = true, .height = 3.0
            )
        )!
    ]
    basis.x = basis.z
    support = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
}

test model_periodic_query_errors := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float64)().value
    sphere: g.Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    ball ::= from_periodic_surface(.surface = sphere)!
    [
        testing.expect_error(
            .expected_reason = ..missing_boundary
            .actual_result   = face_loop(&ball, .face = (.value = 0))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = face_plane(&ball, .face = (.value = 0))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = point(&ball, .vertex = (.value = 0))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = edge_curve(&ball, .edge = (.value = 0))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = face_surface(&ball, .face = (.value = 1))
        )!
    ]
    cylinder: g.Surface#(Float64) = ..cylinder(
        .frame  = basis
        .radius = 2.0
    )
    side ::= from_periodic_surface(.surface = cylinder, .height = 3.0)!
    [
        testing.expect_error(
            .expected_reason = ..missing_vertex
            .actual_result   = halfedge_vertex(
                [halfedge_info(&side, .halfedge = (.value = 0))!]
            )
        )!
    ]
}

_make_periodic := #(.Scalar: Type: Float) (
    .surface: g.Surface#(Scalar), .allocator: Virtual#(Allocator)
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    result = from_periodic_surface(.surface = surface, .allocator = allocator)
}

test model_periodic_generic_composition := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float32)().value
    support: g.Surface#(Float32) = ..sphere(.frame = basis, .radius = 2.0)
    model ::= _make_periodic(.surface = support, .allocator = allocator)!
    testing.expect(entity_counts(&model).faces == 1)!
}

test model_periodic_nonfinite_and_range := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= _periodic_frame#(Float64)().value
    nan ::= sqrt#(Float64)(.value = -1.0).result
    support :: g.Surface#(Float64) = ..sphere(.frame = basis, .radius = nan)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
    support = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_tolerance
            .actual_result   = from_periodic_surface(.surface = support, .tolerance = nan)
        )!
    ]
    basis.origin.x = nan
    support = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_coordinate
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
    basis = _periodic_frame#(Float64)().value
    basis.origin.x = 1.0e308
    support = ..sphere(.frame = basis, .radius = 1.0e308)
    [
        testing.expect_error(
            .expected_reason = ..numeric_range
            .actual_result   = from_periodic_surface(.surface = support)
        )!
    ]
}

test model_linear_curve_orientation := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    input ::= _triangle()
    model ::= [
        from_any_length_faces(
            .points         = view(&input.points)
            .vertex_indices = view(&input.indices)
            .face_lengths   = view(&input.face_lengths)
            .require_closed = false
        )!
    ]
    for entry in [loop_halfedges(&model, .loop = (.value = 0))!] {
        start ::= [
            point(&model, .vertex = [halfedge_vertex(entry.halfedge)!])!
        ]
        next ::= halfedge_info(&model, .halfedge = entry.halfedge.next)!
        end ::= point(&model, .vertex = [halfedge_vertex(next)!])!
        a ::= halfedge_point(&model, .halfedge = entry.id, .parameter = 0.0)!
        b ::= halfedge_point(&model, .halfedge = entry.id, .parameter = 1.0)!
        testing.expect(a.x == start.x and a.y == start.y and a.z == start.z)!
        testing.expect(b.x == end.x and b.y == end.y and b.z == end.z)!
    }
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = halfedge_point(
                &model, .halfedge = (.value = 0), .parameter = -0.25
            )
        )!
    ]
}

test model_periodic_rotated_cylinder_and_ownership := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    basis ::= [
        g.frame#(Float64)(.origin = (3.0, 4.0, -2.0), .axis = (2.0, -3.0, 4.0))!
    ]
    support :: g.Surface#(Float64) = ..cylinder(
        .frame  = basis
        .radius = 2.0
    )
    model ::= from_periodic_surface(.surface = support, .cap_cylinder = true, .height = 3.0)!
    support = ..sphere(.frame = basis, .radius = 9.0)
    stored ::= face_surface(&model, .face = (.value = 0))!
    match stored {
        ..cylinder c { [testing.expect(c.radius == 2.0)!] }
        ..plane _ { [testing.fail()!] }
        ..sphere _ { [testing.fail()!] }
        ..torus _ { [testing.fail()!] }
    }
    i :: UIntNative = 0
    while i < 2 {
        id ::= i | convert#(.to: EdgeId)(_)
        height :: Float64 = 0.0
        if i == 1 { height = 3.0 }
        angles: [5]Float64 = (0.0, 0.5, 1.0, 3.141592653589793, 6.283185307179586)
        for angle in angles {
            boundary ::= [
                curve_point(
                    .curve     = [edge_curve(&model, .edge = id)!]
                    .parameter = [angle / 6.283185307179586]
                )!
            ]
            on_support ::= g.surface_point(.surface = stored, .u = angle, .v = height)!
            [
                testing.expect(
                    [
                        g.norm(g.between(.from = boundary, .to = on_support).result).value
                        < 0.000000000001
                    ]
                )!
            ]
        }
        i = i + 1
    }
}

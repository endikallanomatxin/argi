_check_prism := #(.Scalar: Type: Float) (
    .model: &t.Model#(Scalar), .sides: UIntNative, .interior: g.Point#(Scalar)
) -> !Void {

    counts ::= t.entity_counts(model)
    testing.expect(counts.vertices == sides * 2 and counts.edges == sides * 3)!
    testing.expect(counts.faces == sides + 2 and counts.halfedges == sides * 6)!
    testing.expect(t.is_closed(model).ok)!
    i :: UIntNative = 0
    while i < counts.faces {
        face ::= i | convert#(.to: t.FaceId)(_)
        plane ::= t.face_plane(model, .face = face)!
        offset ::= g.between(.from = plane.origin, .to = interior).result
        testing.expect(g.dot(.left = plane.normal, .right = offset).value < 0.0)!
        visited :: UIntNative = 0
        for entry in [
            t.loop_halfedges(model, .loop = [t.face_loop(model, .face = face)!])!
        ] {
            match [t.opposite(model, .halfedge = entry.id)!] {
                ..none { [testing.fail()!] }
                ..some other {
                    match [t.opposite(model, .halfedge = other.value)!] {
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
        expected :: UIntNative = 4
        if i < 2 { expected = sides }
        testing.expect(visited == expected)!
        i = i + 1
    }
    result = ..ok Void()
}

test extrusion_triangle_winding_and_direction := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    profile: [3]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    reversed: [3]g.Point#(Float64) = (profile[2], profile[1], profile[0])
    positive ::= [
        _extrude_contour(.profile = view(&profile), .displacement = (0.0, 0.0, 2.0))!
    ]
    [_check_prism(&positive, .sides = 3, .interior = (0.5, 0.5, 1.0))!]
    negative ::= [
        _extrude_contour(.profile = view(&profile), .displacement = (1.0, 0.0, -2.0))!
    ]
    [_check_prism(&negative, .sides = 3, .interior = (1.0, 0.5, -1.0))!]
    other ::= [
        _extrude_contour(.profile = view(&reversed), .displacement = (0.0, 0.0, 2.0))!
    ]
    [_check_prism(&other, .sides = 3, .interior = (0.5, 0.5, 1.0))!]
}

test extrusion_quad_float32_arbitrary_plane := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    profile: [4]g.Point#(Float32) = (
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (2.0, 1.0, 1.0),
        (2.0, 0.0, 1.0)
    )
    model ::= [
        _extrude_contour(.profile = view(&profile), .displacement = (2.0, 0.25, 0.0))!
    ]
    [_check_prism(&model, .sides = 4, .interior = (3.0, 0.625, 0.5))!]
}

test extrusion_polygon_owns_its_points := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    profile :: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (3.0, 1.0, 0.0),
        (1.0, 3.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    model ::= [
        _extrude_contour(.profile = view(&profile), .displacement = (0.0, 0.0, 2.0))!
    ]
    profile[0] = (100.0, 100.0, 100.0)
    testing.expect([t.point(&model, .vertex = (.value = 0))!].x == 0.0)!
    [_check_prism(&model, .sides = 5, .interior = (1.0, 1.0, 1.0))!]
}

_extrude_contour := #(.Scalar: Type: Float) (
    .profile      : ArrayView#(g.Point#(Scalar)),
    .displacement : g.Displacement#(Scalar),
    .tolerance    : Scalar                        = 0.000001,
    .allocator    : $&Virtual#(Allocator)
) -> (.result: Errable#(t.Model#(Scalar), t.BrepErrors)) {
    validated ::= profile_from_contour(
        .points = profile, .tolerance = tolerance, .allocator = allocator
    )!
    built ::= extrude(
        .profile = &validated, .displacement = displacement, .allocator = allocator
    )!
    result = ..ok ~built
}

test extrusion_concave_profile_with_reflex_first_corner := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [6]g.Point#(Float64) = (
        (1.0, 1.0, 0.0),
        (1.0, 3.0, 0.0),
        (0.0, 3.0, 0.0),
        (0.0, 0.0, 0.0),
        (3.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    profile ::= profile_from_contour(.points = view(&points))!
    model ::= extrude(.profile = &profile, .displacement = (0.0, 0.0, 1.0))!
    testing.expect(t.entity_counts(&model).faces == 8)!
    testing.expect(t.is_closed(&model).ok)!
    [
        testing.expect([[t.face_plane(&model, .face = (.value = 0))!].normal.z < 0.0])!
    ]
    [
        testing.expect([[t.face_plane(&model, .face = (.value = 1))!].normal.z > 0.0])!
    ]
}

test extrusion_rejects_tangent_displacement := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [3]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    profile ::= profile_from_contour(.points = view(&points))!
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = extrude(
                .profile = &profile, .displacement = (1.0, 0.0, 0.0000001)
            )
        )!
    ]
}

test extrusion_rejects_translated_overflow := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [3]g.Point#(Float64) = (
        (1.0e308, 0.0, 0.0),
        (1.0e308, 1.0, 0.0),
        (1.0e308, 0.0, 1.0)
    )
    profile ::= profile_from_contour(.points = view(&points))!
    [
        testing.expect_error(
            .expected_reason = ..numeric_range
            .actual_result   = extrude(.profile = &profile, .displacement = (1.0e308, 0.0, 0.0))
        )!
    ]
}

test extrusion_disconnected_regions_with_hole_and_island := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    -- An annulus, an island in its hole, and a separate square.
    points :: [16]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (6.0, 0.0, 0.0),
        (6.0, 6.0, 0.0),
        (0.0, 6.0, 0.0),
        (1.0, 1.0, 0.0),
        (5.0, 1.0, 0.0),
        (5.0, 5.0, 0.0),
        (1.0, 5.0, 0.0),
        (2.0, 2.0, 0.0),
        (3.0, 2.0, 0.0),
        (3.0, 3.0, 0.0),
        (2.0, 3.0, 0.0),
        (8.0, 0.0, 0.0),
        (9.0, 0.0, 0.0),
        (9.0, 1.0, 0.0),
        (8.0, 1.0, 0.0)
    )
    contours: [4]UIntNative = (4, 4, 4, 4)
    regions: [3]UIntNative = (2, 1, 1)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    points[0] = (100.0, 100.0, 100.0)
    displacement: g.Displacement#(Float64) = (0.25, 0.0, 2.0)
    model ::= extrude(.profile = &profile, .displacement = displacement)!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 32 and counts.edges == 48 and counts.faces == 22)!
    testing.expect(counts.loops == 24 and counts.halfedges == 96)!
    testing.expect(t.is_closed(&model).ok)!
    [
        testing.expect([[t.face_info(&model, .face = (.value = 0))!].loop_count == 2])!
    ]
    [
        testing.expect([[t.face_info(&model, .face = (.value = 3))!].loop_count == 2])!
    ]
    [
        testing.expect([[t.face_plane(&model, .face = (.value = 0))!].normal.z < 0.0])!
    ]
    [
        testing.expect([[t.face_plane(&model, .face = (.value = 3))!].normal.z > 0.0])!
    ]
    testing.expect([t.point(&model, .vertex = (.value = 0))!].x == 0.0)!
    -- Hole wall on y=1 faces into the cavity, toward increasing y.
    [
        testing.expect([[t.face_plane(&model, .face = (.value = 12))!].normal.y > 0.0])!
    ]
    negative: g.Displacement#(Float64) = (0.0, 0.25, -2.0)
    back ::= extrude(.profile = &profile, .displacement = negative)!
    testing.expect(t.is_closed(&back).ok)!
    [
        testing.expect([[t.face_plane(&back, .face = (.value = 0))!].normal.z > 0.0])!
    ]
}

test extrusion_profile_rejects_intersections_and_bad_nesting := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points :: [8]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (4.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (5.0, 1.0, 0.0),
        (6.0, 1.0, 0.0),
        (6.0, 2.0, 0.0),
        (5.0, 2.0, 0.0)
    )
    contours: [2]UIntNative = (4, 4)
    regions: [1]UIntNative = (2)
    [
        testing.expect_error(
            .expected_reason = ..invalid_region_nesting
            .actual_result   = planar_profile(
                .points          = view(&points)
                .contour_lengths = view(&contours)
                .region_lengths  = view(&regions)
            )
        )!
    ]
    points[4] = (3.0, 1.0, 0.0)
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = planar_profile(
                .points          = view(&points)
                .contour_lengths = view(&contours)
                .region_lengths  = view(&regions)
            )
        )!
    ]
    points[4] = (0.0, 1.0, 0.0)
    points[5] = (1.0, 1.0, 0.0)
    points[6] = (1.0, 2.0, 0.0)
    points[7] = (0.0, 2.0, 0.0)
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = planar_profile(
                .points          = view(&points)
                .contour_lengths = view(&contours)
                .region_lengths  = view(&regions)
            )
        )!
    ]
    wrong: [1]UIntNative = (1)
    [
        testing.expect_error(
            .expected_reason = ..invalid_region_lengths
            .actual_result   = planar_profile(
                .points          = view(&points)
                .contour_lengths = view(&contours)
                .region_lengths  = view(&wrong)
            )
        )!
    ]
}

test extrusion_region_with_two_holes := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [12]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (8.0, 0.0, 0.0),
        (8.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (1.0, 1.0, 0.0),
        (2.0, 1.0, 0.0),
        (2.0, 2.0, 0.0),
        (1.0, 2.0, 0.0),
        (5.0, 1.0, 0.0),
        (5.0, 2.0, 0.0),
        (6.0, 2.0, 0.0),
        (6.0, 1.0, 0.0)
    )
    contours: [3]UIntNative = (4, 4, 4)
    regions: [1]UIntNative = (3)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    model ::= extrude(.profile = &profile, .displacement = (0.0, 0.0, 1.0))!
    testing.expect(t.is_closed(&model).ok)!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 24 and counts.edges == 36 and counts.faces == 14)!
    testing.expect(counts.loops == 18)!
    [
        testing.expect([[t.face_info(&model, .face = (.value = 0))!].loop_count == 3])!
    ]
}

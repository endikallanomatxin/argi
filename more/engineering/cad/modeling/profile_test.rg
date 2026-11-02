test extrusion_profile_smoke := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [3]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    profile ::= profile_from_contour(.points = view(&points))!
    displacement: g.Displacement#(Float64) = (0.0, 0.0, 1.0)
    model ::= extrude(.profile = &profile, .displacement = displacement)!
    testing.expect(t.is_closed(&model).ok)!
}

test extrusion_profile_collinear_corners := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    profile ::= profile_from_contour(.points = view(&points))!
    model ::= extrude(.profile = &profile, .displacement = (0.0, 0.0, 1.0))!
    testing.expect(t.entity_counts(&model).vertices == 10)!
    testing.expect(t.is_closed(&model).ok)!
}

test extrusion_profile_rejects_self_intersection := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (3.0, 3.0, 0.0),
        (0.0, 3.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 1.0, 0.0)
    )
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = profile_from_contour(.points = view(&points))
        )!
    ]
}

test extrusion_profile_rejects_nonplanar_contours := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.0),
        (0.0, 2.0, 0.1)
    )
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = profile_from_contour(.points = view(&points))
        )!
    ]
}

test extrusion_profile_rejects_overlapping_regions := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [8]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (4.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (1.0, 1.0, 0.0),
        (2.0, 1.0, 0.0),
        (2.0, 2.0, 0.0),
        (1.0, 2.0, 0.0)
    )
    contours: [2]UIntNative = (4, 4)
    regions: [2]UIntNative = (1, 1)
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
}

test extrusion_profile_rejects_repeated_closing_point := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 0.0)
    )
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = profile_from_contour(.points = view(&points))
        )!
    ]
}

test extrusion_profile_projects_nearly_planar_input := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0000009),
        (0.0, 100.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    shift :: UIntNative = 0
    while shift < 5 {
        permuted :: [5]g.Point#(Float64) = points
        i :: UIntNative = 0
        while i < 5 {
            permuted[i] = points[[i + shift] % 5]
            i = i + 1
        }
        profile ::= profile_from_contour(.points = view(&permuted))!
        i = 0
        while i < 5 {
            stored ::= profile_point(&profile, .index = i)!
            distance ::= g.dot(
                .left  = profile_plane(&profile).plane.normal
                .right = g.between(
                    .from = profile_plane(&profile).plane.origin, .to = stored
                ).result
            ).value
            testing.expect(distance < 0.000000000001 and distance > -0.000000000001)!
            i = i + 1
        }
        shift = shift + 1
    }
    profile ::= profile_from_contour(.points = view(&points))!
    model ::= extrude(.profile = &profile, .displacement = (0.0, 0.0, 1.0))!
    testing.expect(t.is_closed(&model).ok)!
}

test extrusion_profile_plane_independent_of_region_order := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0000001),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    reordered: [6]g.Point#(Float64) = (
        points[3],
        points[4],
        points[5],
        points[0],
        points[1],
        points[2]
    )
    contours: [2]UIntNative = (3, 3)
    regions: [2]UIntNative = (1, 1)
    first ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    second ::= [
        planar_profile(
            .points          = view(&reordered)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    [
        testing.expect(
            [
                [
                    profile_plane(&first).plane.origin.x
                    == profile_plane(&second).plane.origin.x
                ]
                and [
                    profile_plane(&first).plane.origin.y
                    == profile_plane(&second).plane.origin.y
                ]
                and [
                    profile_plane(&first).plane.origin.z
                    == profile_plane(&second).plane.origin.z
                ]
            ]
        )!
    ]
    i :: UIntNative = 0
    while i < 6 {
        a ::= profile_point(&first, .index = i)!
        b ::= profile_point(&second, .index = [i + 3] % 6)!
        testing.expect(a.x == b.x and a.y == b.y and a.z == b.z)!
        i = i + 1
    }
}

test extrusion_profile_reports_numerical_ambiguity := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [3]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (2.0, 2.0000000000000004, 0.0)
    )
    tolerance: Float64 = 0.000000000000000001
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = profile_from_contour(
                .points = view(&points), .tolerance = tolerance
            )
        )!
    ]
}

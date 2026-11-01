test extrusion_analytic_profile_preserves_arcs := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    frame: g.Frame#(Float64) = (
        .origin = (3.0, 4.0, 5.0)
        .x      = (1.0, 0.0, 0.0)
        .y      = (0.0, 0.0, 1.0)
        .z      = (0.0, -1.0, 0.0)
    )
    spans: [3]g.ContourSpan#(Float64) = (
        (
            .start = (2.0, 0.0)
            .end   = (-2.0, 0.0)
            .sweep = 3.141592653589793
        ),
        (
            .start = (-2.0, 0.0)
            .end   = (2.0, 0.0)
            .sweep = 3.141592653589793
        ),
        (
            .start = (0.5, 0.0)
            .end   = (0.5, 0.0)
            .sweep = -6.283185307179586
        )
    )
    lengths: [2]UIntNative = (2, 1)
    profile ::= [
        profile_from_spans(
            .spans = view(&spans), .contour_lengths = view(&lengths), .frame = frame
        )!
    ]
    spans[0].sweep = 0.0
    stored ::= profile_spans(&profile).spans
    testing.expect([get(&stored, .index = 0)!].sweep == 3.141592653589793)!
    model ::= profile_brep(&profile)!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.faces == 1 and counts.loops == 2 and counts.edges == 3)!
    testing.expect(t.geometry_storage_info(&model).circles == 3)!
    [
        testing.expect(
            [t.face_contains_parameters(&model, .face = (.value = 0), .u = 1.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    second ::= profile_brep(&profile)!
    testing.expect(t.entity_counts(&second).edges == counts.edges)!
}

test extrusion_polygonal_profile_publishes_disconnected_regions := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    contours: [2]UIntNative = (3, 3)
    regions: [2]UIntNative = (1, 1)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    faces ::= profile_brep(&profile)!
    testing.expect(t.entity_counts(&faces).faces == 2)!
    testing.expect(t.entity_counts(&faces).edges == 6)!
}

test extrusion_curved_profile_is_rejected_without_consuming_it := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    frame ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    spans: [1]g.ContourSpan#(Float64) = (
        (
            .start = (1.0, 0.0)
            .end   = (1.0, 0.0)
            .sweep = 6.283185307179586
        ),
    )
    lengths: [1]UIntNative = (1,)
    profile ::= [
        profile_from_spans(
            .spans = view(&spans), .contour_lengths = view(&lengths), .frame = frame
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = extrude(.profile = &profile, .displacement = (0.0, 0.0, 2.0))
            .expected_reason = ..unsupported_boundary
        )!
    ]
    stored ::= profile_spans(&profile).spans
    testing.expect([get(&stored, .index = 0)!].sweep == spans[0].sweep)!
}

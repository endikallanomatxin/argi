_placed_profile_without_source := #(.Provider: Type: Allocator) (.allocator: $&Provider) -> (
    .result : Errable#(PlanarProfile#(Float64), t.BuildErrors)
) {
    frame ::= g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    spans: [2]g.ContourSpan#(Float64) = (
        (
            .start = (2.0, 0.0)
            .end   = (2.0, 0.0)
            .sweep = 6.283185307179586
        ),
        (
            .start = (0.5, 0.0)
            .end   = (0.5, 0.0)
            .sweep = -6.283185307179586
        )
    )
    lengths: [2]UIntNative = (1, 1)
    source ::= profile_from_spans(
        .spans           = view(&spans)
        .contour_lengths = view(&lengths)
        .frame           = frame
        .allocator       = allocator
    )!
    destination: g.Frame#(Float64) = (
        .origin = (3.0, 4.0, 5.0)
        .x      = (0.8, 0.0, -0.6)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.6, 0.0, 0.8)
    )
    placed ::= profile_on_frame(&source, .frame = destination, .allocator = allocator)!
    result = ..ok ~placed
}

test profile_placement_owns_analytic_geometry_and_preserves_publication_positions := (
    .system : System
) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    placed ::= _placed_profile_without_source(.allocator = allocator)!
    publication ::= profile_brep_with_history(&placed)!
    testing.expect(t.entity_counts(&publication.model).loops == 2)!
    i :: UIntNative = 0
    while i < 2 {
        use ::= published_profile_halfedge(&publication, .span = i)!
        loop ::= published_profile_loop(&publication, .contour = i)!
        [
            testing.expect(
                [[t.halfedge_info(&publication.model, .halfedge = use)!].loop == loop]
            )!
        ]
        radius :: Float64 = 2.0
        sweep :: Float64 = 6.283185307179586
        if i == 1 {
            radius = 0.5;
            sweep = 0.0 - sweep
        }
        parameter :: Float64 = 0.0
        while parameter <= 1.0 {
            local: g.ContourPoint#(Float64) = (
                .x = radius * cos(sweep * parameter).result
                .y = [radius * sin(sweep * parameter).result]
            )
            expected ::= _profile_world_point(
                .frame = profile_frame(&placed).frame, .point = local
            ).value
            actual ::= [
                t.halfedge_point(&publication.model, .halfedge = use, .parameter = parameter)!
            ]
            [
                testing.expect(
                    [g.norm(g.between(.from = expected, .to = actual).result).value < 0.000001]
                )!
            ]
            parameter = parameter + 0.25
        }
        i = i + 1
    }
    match [locate_in_profile(&placed, .point = (3.0, 5.0, 5.0))!] {
        ..inside found { [testing.expect(found.region == 0)!] }
        ..outside { [testing.fail()!] }
        ..boundary _ { [testing.fail()!] }
    }
}

test profile_placement_rejects_invalid_frame_without_consuming_source := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    points: [3]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    source ::= profile_from_contour(.points = view(&points))!
    frame ::= profile_frame(&source).frame
    invalid ::= frame
    invalid.z = invalid.x
    [
        testing.expect_error(
            .actual_result   = profile_on_frame(&source, .frame = invalid)
            .expected_reason = ..degenerate_face
        )!
    ]
    placed ::= profile_on_frame(&source, .frame = frame)!
    extrusion ::= [
        extrude_with_history(.profile = &placed, .displacement = (0.0, 0.0, 1.0))!
    ]
    testing.expect(t.is_closed(&extrusion.model).ok)!
    original ::= profile_brep(&source)!
    testing.expect(t.entity_counts(&original).faces == 1)!
}

test profile_placement_preserves_disconnected_regions := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
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
    source ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contours)
            .region_lengths  = view(&regions)
        )!
    ]
    frame ::= profile_frame(&source).frame
    frame.origin = (5.0, 6.0, 7.0)
    placed ::= profile_on_frame(&source, .frame = frame)!
    lengths ::= profile_region_lengths(&placed).lengths
    testing.expect(Indexable#(ArrayView#(UIntNative)).length(&lengths).count == 2)!
    [
        testing.expect(
            [[get(&lengths, .index = 0)!] == 1 and [get(&lengths, .index = 1)!] == 1]
        )!
    ]
    publication ::= profile_brep_with_history(&placed)!
    extrusion ::= extrude_with_history(.profile = &placed, .displacement = frame.z)!
    testing.expect(t.entity_counts(&publication.model).faces == 2)!
    testing.expect(t.entity_counts(&extrusion.model).faces == 10)!
    span ::= get(&placed._spans, .index = 3)!
    next ::= get(&placed._spans, .index = 4)!
    local: g.ContourPoint#(Float64) = (
        .x = [span.start.x + span.end.x + next.end.x] / 3.0
        .y = [[span.start.y + span.end.y + next.end.y] / 3.0]
    )
    point ::= _profile_world_point(.frame = frame, .point = local).value
    match [locate_in_profile(&placed, .point = point)!] {
        ..inside found { [testing.expect(found.region == 1)!] }
        ..outside { [testing.fail()!] }
        ..boundary _ { [testing.fail()!] }
    }
}
